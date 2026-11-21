# Smart planter API: Sinatra on PicoRuby (Cloudflare Workers) with D1.
#
#   POST /api/readings   store one reading (Authorization: Bearer <INGEST_TOKEN>)
#   GET  /api/readings   latest readings, newest first (?device=...&limit=...)
#   GET  /api/latest     the newest reading per device
#
# Static Assets serve public/ (the Funicular page) without starting PicoRuby.

class PlanterApp < Sinatra::Base
  STATUSES = %w[dry ok wet]
  DEFAULT_LIMIT = 288 # one day at 5-minute intervals
  MAX_LIMIT = 2000
  DEVICE_PATTERN = /\A[A-Za-z0-9_.-]{1,64}\z/
  # UTC only, so that text order in D1 is time order.
  TIME_PATTERN = /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z\z/
  COLUMNS = "device, moisture, volt, raw, status, measured_at"

  before do
    headers "cache-control" => "no-store"
  end

  post "/api/readings" do
    authorize!
    reading = validate_reading(json_body)

    result = database.prepare(
      "INSERT INTO readings (device, moisture, volt, raw, status, measured_at) " \
      "VALUES (?1, ?2, ?3, ?4, ?5, COALESCE(?6, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')))"
    ).bind(
      reading["device"], reading["moisture"], reading["volt"],
      reading["raw"], reading["status"], reading["measured_at"]
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
    json_response rows.map { |row| serialize(row) }
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
    moisture_ok = moisture.is_a?(Integer) && moisture >= 0 && moisture <= 100
    errors << "moisture must be an Integer from 0 to 100" unless moisture_ok

    volt = payload["volt"]
    volt_ok = (volt.is_a?(Float) || volt.is_a?(Integer)) && volt >= 0 && volt <= 10
    errors << "volt must be a number from 0 to 10" unless volt_ok

    raw = payload["raw"]
    errors << "raw must be an Integer from 0 to 4095" unless raw.is_a?(Integer) && raw >= 0 && raw <= 4095

    status = payload["status"]
    if status.nil? && moisture_ok
      status = status_for(moisture)
    elsif !STATUSES.include?(status)
      errors << "status must be one of #{STATUSES.join(', ')}"
    end

    measured_at = payload["measured_at"]
    unless measured_at.nil? || (measured_at.is_a?(String) && measured_at.match?(TIME_PATTERN))
      errors << "measured_at must be ISO8601 UTC, e.g. 2026-11-22T00:00:00Z"
    end

    halt 400, json_response("error" => errors.join("; "), "errors" => errors) unless errors.empty?
    {
      "device" => device, "moisture" => moisture, "volt" => volt.to_f,
      "raw" => raw, "status" => status, "measured_at" => measured_at,
    }
  end

  def status_for(moisture)
    if moisture < 30
      "dry"
    elsif moisture < 60
      "ok"
    else
      "wet"
    end
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

  def json_response(payload)
    content_type "application/json", charset: "utf-8"
    JSON.generate(payload)
  end

  def halt_json(status_code, message)
    halt status_code, json_response("error" => message)
  end
end

Rackup::Handler::CloudflareWorker.run(PlanterApp)
