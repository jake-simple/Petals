#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "jwt"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

APP_STORE_CONNECT_API_URL = "https://api.appstoreconnect.apple.com".freeze
APP_STORE_CONNECT_BUNDLE_ID = ENV.fetch("APP_STORE_CONNECT_BUNDLE_ID", "com.onessa.Petals").freeze
APP_STORE_CONNECT_KEY_ID = ENV.fetch("APP_STORE_CONNECT_KEY_ID", "LDMZ45D4WV").freeze
APP_STORE_CONNECT_ISSUER_ID = ENV.fetch("APP_STORE_CONNECT_ISSUER_ID", "18a54441-d89b-48cf-b3b6-c17f85fc41e5").freeze
PLATFORM_NAMES = { "IOS" => "iOS", "MAC_OS" => "macOS" }.freeze

class AppStoreConnectClient
  def initialize(key_path:)
    @private_key = OpenSSL::PKey::EC.new(File.read(key_path))
  end

  def builds(version:, platform:)
    query = URI.encode_www_form(
      "filter[app]" => app_id,
      "filter[preReleaseVersion.version]" => version,
      "filter[preReleaseVersion.platform]" => platform,
      "sort" => "-uploadedDate",
      "limit" => "200"
    )
    get("/v1/builds?#{query}").fetch("data")
  end

  private

  def app_id
    return @app_id if defined?(@app_id)
    app = get("/v1/apps?#{URI.encode_www_form('filter[bundleId]' => APP_STORE_CONNECT_BUNDLE_ID)}").fetch("data").first
    raise "App Store Connect에서 #{APP_STORE_CONNECT_BUNDLE_ID} 앱을 찾지 못했습니다." unless app
    @app_id = app.fetch("id")
  end

  def get(path)
    uri = URI("#{APP_STORE_CONNECT_API_URL}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
    message = JSON.parse(response.body).fetch("errors", []).map { |error| error["detail"] }.join("; ")
    raise "App Store Connect 조회 실패 (HTTP #{response.code}): #{message}"
  end

  def token
    JWT.encode({ iss: APP_STORE_CONNECT_ISSUER_ID, aud: "appstoreconnect-v1", exp: Time.now.to_i + 600 }, @private_key, "ES256", { kid: APP_STORE_CONNECT_KEY_ID })
  end
end

options = { timeout_seconds: 4_500, poll_seconds: 60 }
OptionParser.new do |parser|
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--platform PLATFORM") { |value| options[:platform] = value }
  parser.on("--timeout-seconds SECONDS", Integer) { |value| options[:timeout_seconds] = value }
  parser.on("--poll-seconds SECONDS", Integer) { |value| options[:poll_seconds] = value }
end.parse!
version = options.fetch(:version).to_s
platform = options.fetch(:platform).to_s.upcase
abort("--version을 지정하세요.") unless version.match?(/\A\d+(?:\.\d+){1,2}\z/)
abort("--platform은 IOS 또는 MAC_OS여야 합니다.") unless PLATFORM_NAMES.key?(platform)
abort("--poll-seconds는 1 이상이어야 합니다.") unless options[:poll_seconds].positive?
key_path = ENV.fetch("APP_STORE_CONNECT_API_KEY_PATH")
abort("App Store Connect API 키 파일이 없습니다.") unless File.file?(key_path)

client = AppStoreConnectClient.new(key_path: key_path)
deadline = Time.now + options[:timeout_seconds]
build_number = nil
loop do
  candidates = client.builds(version: version, platform: platform).filter_map do |build|
    attributes = build.fetch("attributes")
    next unless attributes["processingState"] == "VALID"
    next unless attributes["buildAudienceType"] == "APP_STORE_ELIGIBLE"
    next if attributes["expired"]
    attributes.fetch("version")
  end
  build_number = candidates.max_by { |number| number.split(".").map(&:to_i) }
  break if build_number
  raise "#{PLATFORM_NAMES.fetch(platform)} #{version} VALID App Store 빌드를 찾지 못했습니다." if Time.now >= deadline
  warn "#{PLATFORM_NAMES.fetch(platform)} #{version} VALID App Store 빌드를 기다리는 중입니다."
  sleep options[:poll_seconds]
end
puts "#{PLATFORM_NAMES.fetch(platform)} #{version} VALID App Store 빌드: #{build_number}"
if (output_path = ENV["GITHUB_OUTPUT"])
  File.open(output_path, "a") do |output|
    output.puts "build_number=#{build_number}"
    output.puts "version=#{version}"
  end
end
