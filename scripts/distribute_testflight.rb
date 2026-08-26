#!/usr/bin/env ruby
# frozen_string_literal: true

# Xcode Cloud는 App Store Connect 업로드까지만 담당하고 TestFlight 테스터 그룹에는
# 빌드를 배포하지 않는다. 이 스크립트가 그 마지막 한 단계를 대신한다.

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
APP_STORE_CONNECT_ISSUER_ID = ENV.fetch(
  "APP_STORE_CONNECT_ISSUER_ID",
  "18a54441-d89b-48cf-b3b6-c17f85fc41e5"
).freeze
PLATFORM_NAMES = { "IOS" => "iOS", "MAC_OS" => "macOS" }.freeze

class AppStoreConnectClient
  def initialize(key_path:)
    @private_key = OpenSSL::PKey::EC.new(File.read(key_path))
  end

  # 내부 테스터 그룹만 대상으로 한다. 외부 그룹 배포는 Apple 베타 앱 심사를 거쳐야 하므로
  # 태그 푸시 흐름에서 자동으로 처리하지 않는다.
  def internal_beta_groups
    query = URI.encode_www_form("filter[app]" => app_id, "limit" => "200")
    get("/v1/betaGroups?#{query}").fetch("data").select do |group|
      group.fetch("attributes").fetch("isInternalGroup")
    end
  end

  def build(version:, build_number:, platform:)
    query = URI.encode_www_form(
      "filter[app]" => app_id,
      "filter[preReleaseVersion.version]" => version,
      "filter[preReleaseVersion.platform]" => platform,
      "filter[version]" => build_number,
      "limit" => "200"
    )
    get("/v1/builds?#{query}").fetch("data").first
  end

  # 모든 빌드에 자동 접근하는 내부 그룹은 개별 배정 요청을 422로 거부한다.
  # 그 422를 그대로 성공으로 삼으면 거짓 성공이 되므로, 실제 배정 여부를 확인한 뒤에만
  # :already_distributed로 처리한다.
  def distribute(group_id:, build_id:)
    body = { data: [{ type: "builds", id: build_id }] }
    response = post("/v1/betaGroups/#{group_id}/relationships/builds", body)
    return :distributed if response.is_a?(Net::HTTPSuccess)
    if response.code == "422" && assigned?(group_id: group_id, build_id: build_id)
      return :already_distributed
    end

    raise "TestFlight 배포 실패 (HTTP #{response.code}): #{error_message(response)}"
  end

  def assigned?(group_id:, build_id:)
    path = "/v1/betaGroups/#{group_id}/relationships/builds?limit=200"
    loop do
      payload = get(path)
      return true if payload.fetch("data").any? { |item| item["id"] == build_id }

      next_link = payload.dig("links", "next")
      return false unless next_link

      path = next_link.delete_prefix(APP_STORE_CONNECT_API_URL)
    end
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

    raise "App Store Connect 조회 실패 (HTTP #{response.code}): #{error_message(response)}"
  end

  def post(path, body)
    uri = URI("#{APP_STORE_CONNECT_API_URL}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  end

  def error_message(response)
    JSON.parse(response.body).fetch("errors", []).map { |error| error["detail"] }.join("; ")
  rescue JSON::ParserError
    response.body.to_s
  end

  def token
    JWT.encode(
      {
        iss: APP_STORE_CONNECT_ISSUER_ID,
        aud: "appstoreconnect-v1",
        exp: Time.now.to_i + 600
      },
      @private_key,
      "ES256",
      { kid: APP_STORE_CONNECT_KEY_ID }
    )
  end
end

options = { platforms: %w[MAC_OS] }
OptionParser.new do |parser|
  parser.on("--version VERSION", "App Store marketing version") { |value| options[:version] = value }
  parser.on("--build-number NUMBER", "Xcode Cloud build number") { |value| options[:build_number] = value }
  parser.on("--platforms LIST", "Comma-separated platforms (IOS,MAC_OS)") do |value|
    options[:platforms] = value.split(",").map { |item| item.strip.upcase }
  end
end.parse!

version = options.fetch(:version).to_s
build_number = options.fetch(:build_number).to_s
platforms = options.fetch(:platforms)
abort("--version을 지정하세요.") unless version.match?(/\A\d+(?:\.\d+){1,2}\z/)
abort("--build-number를 지정하세요.") unless build_number.match?(/\A\d+(?:\.\d+)*\z/)
abort("--platforms는 IOS 또는 MAC_OS여야 합니다.") unless platforms.all? { |item| PLATFORM_NAMES.key?(item) }

key_path = ENV.fetch("APP_STORE_CONNECT_API_KEY_PATH")
abort("App Store Connect API 키 파일이 없습니다.") unless File.file?(key_path)

client = AppStoreConnectClient.new(key_path: key_path)
groups = client.internal_beta_groups
if groups.empty?
  abort("App Store Connect에 내부 TestFlight 그룹이 없습니다. 먼저 내부 테스터 그룹을 만드세요.")
end

results = platforms.flat_map do |platform|
  platform_name = PLATFORM_NAMES.fetch(platform)
  build = client.build(version: version, build_number: build_number, platform: platform)
  raise "#{platform_name} #{version} (#{build_number}) 빌드를 찾지 못했습니다." unless build

  groups.map do |group|
    group_name = group.fetch("attributes").fetch("name")
    status = client.distribute(group_id: group.fetch("id"), build_id: build.fetch("id"))
    label = status == :distributed ? "배포함" : "이미 배포됨"
    puts "#{platform_name} #{version} (#{build_number}) → #{group_name}: #{label}"
    { platform: platform_name, group: group_name, label: label }
  end
end

if (summary_path = ENV["GITHUB_STEP_SUMMARY"])
  File.open(summary_path, "a") do |summary|
    summary.puts "## TestFlight 내부 배포"
    summary.puts
    summary.puts "- 버전: `#{version}` / 빌드: `#{build_number}`"
    results.each do |result|
      summary.puts "- #{result[:platform]} → `#{result[:group]}`: #{result[:label]}"
    end
  end
end
