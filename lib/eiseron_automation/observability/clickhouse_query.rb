# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EiseronAutomation
  module Observability
    class ClickHouseQuery
      DEFAULT_SIZE = 100
      TIMEOUT = 25
      UNITS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze

      def initialize(env:, io:, args: [])
        @env = env
        @io = io
        @args = args
      end

      def search
        sql = positional or raise Error, "usage: obs search \"<SQL>\" [--size N]"
        emit(run(sql))
      end

      def streams
        rows = run("SELECT DISTINCT ServiceName FROM #{table} ORDER BY ServiceName")
        @io.puts(rows.map { |row| row["ServiceName"] }.compact.join("\n"))
      end

      def tail
        service = positional or raise Error, "usage: obs tail <service> [--last 15m] [--size N]"
        emit(run(build_tail_sql(option("--last", "15m")), { "svc" => service }))
      end

      def build_tail_sql(last)
        "SELECT Timestamp, SeverityText, ServiceName, Body FROM #{table} " \
          "WHERE ServiceName = {svc:String} " \
          "AND Timestamp >= now() - INTERVAL #{duration_seconds(last)} SECOND " \
          "ORDER BY Timestamp DESC LIMIT #{size}"
      end

      def duration_seconds(last)
        match = last.match(/\A(\d+)([smhd])\z/) or raise Error, "invalid --last: #{last}"
        match[1].to_i * UNITS.fetch(match[2])
      end

      def table
        "#{database}.otel_logs"
      end

      private

      def run(sql, params = {})
        JSON.parse(request(sql, params)).fetch("data", [])
      end

      def emit(rows) = @io.puts(JSON.pretty_generate(rows))

      def positional = @args.find { |arg| !arg.start_with?("--") }

      def option(flag, default)
        index = @args.index(flag)
        index && @args[index + 1] ? @args[index + 1] : default
      end

      def size = (option("--size", nil) || DEFAULT_SIZE).to_i

      def database = @env.fetch("CLICKHOUSE_DATABASE", "otel")

      def request(sql, params)
        uri = query_uri(params)
        response = http(uri).request(build_request(uri, sql))
        return response.body if response.is_a?(Net::HTTPSuccess)

        raise Error, "clickhouse query failed: #{response.code} #{response.body}"
      end

      def query_uri(params)
        base = { database: database, default_format: "JSON" }
        query = base.merge(params.transform_keys { |key| "param_#{key}" })
        URI("#{require_env('CLICKHOUSE_URL')}/?#{URI.encode_www_form(query)}")
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
