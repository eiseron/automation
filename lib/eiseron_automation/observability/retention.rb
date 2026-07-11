# frozen_string_literal: true

require "net/http"
require "uri"

module EiseronAutomation
  module Observability
    class Retention
      TIMEOUT = 25

      SIGNALS = {
        "logs" => { tables: %w[otel_logs], column: "Timestamp" },
        "traces" => { tables: %w[otel_traces], column: "Timestamp" },
        "metrics" => {
          tables: %w[
            otel_metrics_gauge
            otel_metrics_sum
            otel_metrics_histogram
            otel_metrics_exponential_histogram
            otel_metrics_summary
          ],
          column: "TimeUnix"
        }
      }.freeze

      DEFAULTS = { "logs" => "7d", "traces" => "3d", "metrics" => "30d" }.freeze
      UNIT_SQL = { "s" => "SECOND", "m" => "MINUTE", "h" => "HOUR", "d" => "DAY" }.freeze

      def initialize(env:, io:, args: [])
        @env = env
        @io = io
        @args = args
      end

      def apply
        build_statements.each { |sql| execute(sql) }
        @io.puts("applied retention: #{SIGNALS.keys.map { |signal| "#{signal}=#{window(signal)}" }.join(' ')}")
      end

      def build_statements
        SIGNALS.flat_map do |signal, meta|
          ttl = ttl_expr(meta[:column], window(signal))
          meta[:tables].map { |table| "ALTER TABLE #{database}.#{table} MODIFY TTL #{ttl}" }
        end
      end

      def ttl_expr(column, win)
        match = win.match(/\A(\d+)([smhd])\z/) or raise Error, "invalid retention '#{win}' (use <n>[smhd])"
        "toDateTime(#{column}) + INTERVAL #{match[1]} #{UNIT_SQL.fetch(match[2])}"
      end

      def window(signal) = option("--#{signal}", DEFAULTS.fetch(signal))

      private

      def option(flag, default)
        index = @args.index(flag)
        index && @args[index + 1] ? @args[index + 1] : default
      end

      def database = @env.fetch("CLICKHOUSE_DATABASE", "otel")

      def execute(sql)
        uri = URI("#{require_env('CLICKHOUSE_URL')}/?#{URI.encode_www_form(database: database)}")
        response = http(uri).request(build_request(uri, sql))
        return if response.is_a?(Net::HTTPSuccess)

        raise Error, "clickhouse ddl failed: #{response.code} #{response.body}"
      end

      def build_request(uri, sql)
        request = Net::HTTP::Post.new(uri)
        request["X-ClickHouse-User"] = require_env("CLICKHOUSE_USER")
        request["X-ClickHouse-Key"] = require_env("CLICKHOUSE_PASSWORD")
        cf_access(request)
        request.body = sql
        request
      end

      def cf_access(request)
        return unless @env["CF_ACCESS_CLIENT_ID"]

        request["CF-Access-Client-Id"] = @env["CF_ACCESS_CLIENT_ID"]
        request["CF-Access-Client-Secret"] = require_env("CF_ACCESS_CLIENT_SECRET")
      end

      def http(uri)
        client = Net::HTTP.new(uri.host, uri.port)
        client.use_ssl = uri.scheme == "https"
        client.open_timeout = TIMEOUT
        client.read_timeout = TIMEOUT
        client
      end

      def require_env(key) = @env[key] || raise(Error, "missing env #{key}")
    end
  end
end
