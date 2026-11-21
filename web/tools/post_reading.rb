#!/usr/bin/env ruby
# frozen_string_literal: true

# Send one soil-moisture reading to the smart planter API (CRuby, stdlib only).
#
#   PLANTER_API_URL=https://smart-planter.example.workers.dev \
#   PLANTER_TOKEN=... \
#   ruby tools/post_reading.rb --device planter-1 --moisture 46 --volt 1.9 --raw 2161
#
#   echo '{"device":"planter-1","moisture":46,"volt":1.9,"raw":2161,"status":"ok"}' |
#     ruby tools/post_reading.rb
#
# Without --status the status is derived from moisture (dry < 30 % <= ok < 60 % <= wet).
# measured_at is optional; the server uses the current UTC time when it is absent.
# Exit status: 0 when stored (201), 1 when the server refused, 2 on usage or network errors.

require "json"
require "net/http"
require "optparse"
require "uri"

def status_for(moisture)
  if moisture < 30 then "dry"
  elsif moisture < 60 then "ok"
  else "wet"
  end
end

def fail_usage(message)
  warn "post_reading: #{message}"
  exit 2
end

options = {}
parser = OptionParser.new do |o|
  o.banner = "usage: post_reading.rb [--device ID --moisture N --volt V --raw N [--status S] [--measured-at ISO8601]]\n" \
             "       (reads one JSON object from stdin when no reading options are given)"
  o.on("--device ID", String) { |v| options["device"] = v }
  o.on("--moisture N", Integer) { |v| options["moisture"] = v }
  o.on("--volt V", Float) { |v| options["volt"] = v }
  o.on("--raw N", Integer) { |v| options["raw"] = v }
  o.on("--status S", %w[dry ok wet]) { |v| options["status"] = v }
  o.on("--measured-at TIME", String) { |v| options["measured_at"] = v }
end
begin
  parser.parse!(ARGV)
rescue OptionParser::ParseError => e
  fail_usage("#{e.message}\n#{parser.banner}")
end

reading =
  if options.empty?
    input = $stdin.read
    begin
      parsed = JSON.parse(input)
    rescue JSON::ParserError => e
      fail_usage("stdin is not valid JSON: #{e.message}")
    end
    fail_usage("stdin must be one JSON object") unless parsed.is_a?(Hash)
    parsed
  else
    missing = %w[device moisture volt raw] - options.keys
    fail_usage("missing #{missing.map { |k| "--#{k}" }.join(', ')}") unless missing.empty?
    options
  end
if reading["status"].nil? && reading["moisture"].is_a?(Integer)
  reading["status"] = status_for(reading["moisture"])
end

base = ENV["PLANTER_API_URL"].to_s
token = ENV["PLANTER_TOKEN"].to_s
fail_usage("set PLANTER_API_URL (e.g. http://127.0.0.1:8787)") if base.empty?

uri = URI.join(base.end_with?("/") ? base : "#{base}/", "api/readings")
request = Net::HTTP::Post.new(uri)
request["Content-Type"] = "application/json"
request["Authorization"] = "Bearer #{token}" unless token.empty?
request.body = JSON.generate(reading)

begin
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                             open_timeout: 10, read_timeout: 15) do |http|
    http.request(request)
  end
rescue StandardError => e
  warn "post_reading: #{e.class}: #{e.message}"
  exit 2
end

puts "#{response.code} #{response.body}"
exit(response.code == "201" ? 0 : 1)
