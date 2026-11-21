# Smart planter API: Sinatra on PicoRuby (Cloudflare Workers) with D1.
#
#   POST /api/readings        store one reading (Authorization: Bearer <INGEST_TOKEN>)
#   GET  /api/readings        latest readings, newest first (?device=...&limit=...)
#   GET  /api/latest          the newest reading per device, with its plant profile
#   GET  /api/plants          all plant profiles
#   PUT  /api/plants/:device  create or update a plant profile (Bearer token)
#
# Static Assets serve public/ (the Funicular page) without starting PicoRuby.

class PlanterApp < Sinatra::Base
  STATUSES = %w[dry ok wet]
  # Used when a device has no plant profile (the defaults of chapter 2).
  DEFAULT_RANGE = { "moisture_min" => 30, "moisture_max" => 59 }
  DEFAULT_LIMIT = 288 # one day at 5-minute intervals
  MAX_LIMIT = 2000
  DEVICE_PATTERN = /\A[A-Za-z0-9_.-]{1,64}\z/
  # UTC only, so that text order in D1 is time order.
  TIME_PATTERN = /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z\z/
  COLUMNS = "device, moisture, volt, raw, status, measured_at"
  PLANT_COLUMNS = "device, nickname, species, scientific_name, photo_url, moisture_min, moisture_max"

  before do
    headers "cache-control" => "no-store"
  end

  post "/api/readings" do
    authorize!
    reading = validate_reading(json_body)
    # The server judges the status with the plant's own range.
    judged = status_for(find_plant(reading["device"]), reading["moisture"])

    result = database.prepare(
      "INSERT INTO readings (device, moisture, volt, raw, status, measured_at) " \
      "VALUES (?1, ?2, ?3, ?4, ?5, COALESCE(?6, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')))"
    ).bind(
      reading["device"], reading["moisture"], reading["volt"],
      reading["raw"], judged, reading["measured_at"]
    ).run

    row = database.prepare(
      "SELECT #{COLUMNS} FROM readings WHERE id = ?1"
    ).bind(result.last_row_id).first
    status 201
    json_response serialize(row)
  end

  get "/api/readings" do
    limit = parse_limit(params["limit"])
    device = params["device"]
    rows = if device.nil? || device.empty?
      database.prepare(
        "SELECT #{COLUMNS} FROM readings ORDER BY measured_at DESC, id DESC LIMIT ?1"
      ).bind(limit).rows
    else
      halt_json 400, "device must match #{DEVICE_PATTERN.source}" unless device.match?(DEVICE_PATTERN)
      database.prepare(
        "SELECT #{COLUMNS} FROM readings WHERE device = ?1 " \
        "ORDER BY measured_at DESC, id DESC LIMIT ?2"
      ).bind(device, limit).rows
    end
    json_response rows.map { |row| serialize(row) }
  end

  get "/api/latest" do
    rows = database.prepare(
      "SELECT #{COLUMNS} FROM readings AS r WHERE r.id = (" \
      "SELECT id FROM readings WHERE device = r.device " \
      "ORDER BY measured_at DESC, id DESC LIMIT 1) ORDER BY r.device"
    ).rows
    plants = {}
    all_plants.each { |plant| plants[plant["device"]] = plant }
    json_response(rows.map { |row| serialize(row).merge("plant" => plants[row[:device]]) })
  end

  get "/api/plants" do
    json_response all_plants
  end

  put "/api/plants/:device" do
    authorize!
    device = params[:device].to_s
    halt_json 400, "device must match #{DEVICE_PATTERN.source}" unless device.match?(DEVICE_PATTERN)
    plant = validate_plant(json_body)

    database.prepare(
      "INSERT OR REPLACE INTO plants (#{PLANT_COLUMNS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
    ).bind(
      device, plant["nickname"], plant["species"], plant["scientific_name"],
      plant["photo_url"], plant["moisture_min"], plant["moisture_max"]
    ).run
    json_response find_plant(device)
  end

  error Cloudflare::Error do
    status 502
    json_response("error" => "D1 request failed")
  end

  not_found do
    json_response("error" => "not found")
  end

  private

  def database
    env["cloudflare.env"].DB
  end

  # dry below the plant's range, wet above it, ok inside it (both ends included).
  def status_for(plant, moisture)
    range = plant || DEFAULT_RANGE
    if moisture < range["moisture_min"]
      "dry"
    elsif moisture > range["moisture_max"]
      "wet"
    else
      "ok"
    end
  end

  def find_plant(device)
    row = database.prepare("SELECT #{PLANT_COLUMNS} FROM plants WHERE device = ?1").bind(device).first
    row && serialize_plant(row)
  end

  def all_plants
    database.prepare("SELECT #{PLANT_COLUMNS} FROM plants ORDER BY device").rows.map { |row| serialize_plant(row) }
  end

  def authorize!
    expected = ENV["INGEST_TOKEN"]
    halt_json 500, "INGEST_TOKEN is not configured" if expected.nil? || expected.empty?
    header = env["HTTP_AUTHORIZATION"].to_s
    given = header.start_with?("Bearer ") ? header[7..-1].strip : ""
    halt_json 401, "missing or invalid bearer token" unless secure_compare(given, expected)
  end

  # Compare without stopping at the first differing byte.
  def secure_compare(a, b)
    return false unless a.bytesize == b.bytesize
    diff = 0
    i = 0
    while i < a.bytesize
      diff |= a.getbyte(i) ^ b.getbyte(i)
      i += 1
    end
    diff == 0
  end

  def json_body
    begin
      payload = JSON.parse(env["rack.input"].read)
    rescue JSON::JSONError
      halt_json 400, "request body must be valid JSON"
    end
    halt_json 400, "request body must be a JSON object" unless payload.is_a?(Hash)
    payload
  end

  def validate_reading(payload)
    errors = []
    device = payload["device"]
    errors << "device must be a String matching #{DEVICE_PATTERN.source}" unless device.is_a?(String) && device.match?(DEVICE_PATTERN)

    moisture = payload["moisture"]
    errors << "moisture must be an Integer from 0 to 100" unless percent?(moisture)

    volt = payload["volt"]
    volt_ok = (volt.is_a?(Float) || volt.is_a?(Integer)) && volt >= 0 && volt <= 10
    errors << "volt must be a number from 0 to 10" unless volt_ok

    raw = payload["raw"]
    errors << "raw must be an Integer from 0 to 4095" unless raw.is_a?(Integer) && raw >= 0 && raw <= 4095

    # A status sent by the device is accepted for compatibility but ignored.
    sent = payload["status"]
    errors << "status must be one of #{STATUSES.join(', ')}" unless sent.nil? || STATUSES.include?(sent)

    measured_at = payload["measured_at"]
    unless measured_at.nil? || (measured_at.is_a?(String) && measured_at.match?(TIME_PATTERN))
      errors << "measured_at must be ISO8601 UTC, e.g. 2026-11-22T00:00:00Z"
    end

    halt_errors(errors)
    {
      "device" => device, "moisture" => moisture, "volt" => volt.to_f,
      "raw" => raw, "measured_at" => measured_at,
    }
  end

  def validate_plant(payload)
    errors = []
    %w[nickname species].each do |key|
      value = payload[key]
      unless value.is_a?(String) && !value.strip.empty? && value.length <= 40
        errors << "#{key} must be a non-empty String of at most 40 characters"
      end
    end

    scientific_name = payload["scientific_name"]
    unless scientific_name.nil? || (scientific_name.is_a?(String) && scientific_name.length <= 80)
      errors << "scientific_name must be a String of at most 80 characters"
    end

    photo_url = payload["photo_url"]
    unless photo_url.nil? || photo_url?(photo_url)
      errors << "photo_url must be a path starting with \"/\" or an https:// URL"
    end

    min = payload["moisture_min"]
    max = payload["moisture_max"]
    unless percent?(min) && percent?(max) && min <= max
      errors << "moisture_min and moisture_max must be Integers from 0 to 100, min <= max"
    end

    halt_errors(errors)
    {
      "nickname" => payload["nickname"].strip, "species" => payload["species"].strip,
      "scientific_name" => scientific_name, "photo_url" => photo_url,
      "moisture_min" => min, "moisture_max" => max,
    }
  end

  def percent?(value)
    value.is_a?(Integer) && value >= 0 && value <= 100
  end

  # A path on this site ("/images/...", not "//host") or an https URL.
  def photo_url?(value)
    return false unless value.is_a?(String) && value.length <= 500
    (value.start_with?("/") && !value.start_with?("//")) || value.start_with?("https://")
  end

  def halt_errors(errors)
    return if errors.empty?
    halt 400, json_response("error" => errors.join("; "), "errors" => errors)
  end

  def parse_limit(value)
    return DEFAULT_LIMIT if value.nil? || value.empty?
    halt_json 400, "limit must be an Integer from 1 to #{MAX_LIMIT}" unless value.match?(/\A[1-9][0-9]{0,3}\z/)
    limit = value.to_i
    halt_json 400, "limit must be an Integer from 1 to #{MAX_LIMIT}" if limit > MAX_LIMIT
    limit
  end

  def serialize(row)
    {
      "device" => row[:device],
      "moisture" => row[:moisture],
      "volt" => row[:volt].to_f,
      "raw" => row[:raw],
      "status" => row[:status],
      "measured_at" => row[:measured_at],
    }
  end

  def serialize_plant(row)
    {
      "device" => row[:device],
      "nickname" => row[:nickname],
      "species" => row[:species],
      "scientific_name" => row[:scientific_name],
      "photo_url" => row[:photo_url],
      "moisture_min" => row[:moisture_min],
      "moisture_max" => row[:moisture_max],
    }
  end

  def json_response(payload)
    content_type "application/json", charset: "utf-8"
    JSON.generate(payload)
  end

  def halt_json(status_code, message)
    halt status_code, json_response("error" => message)
  end
end

Rackup::Handler::CloudflareWorker.run(PlanterApp)
