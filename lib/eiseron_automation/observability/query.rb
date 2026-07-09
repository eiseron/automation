# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EiseronAutomation
  module Observability
    class Query
      DEFAULT_SIZE = 100
      TIMEOUT = 25
      UNITS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze

      def initialize(env:, io:, args: [], clock: -> { Time.now.to_f })
        @env = env
        @io = io
        @args = args
        @clock = clock
      end

      def search
        sql = positional or raise Error, "usage: obs search \"<SQL>\" [--last 1h] [--size N]"
        emit(run_search(sql))
      end

      def tail
        stream = positional or raise Error, "usage: obs tail <stream> [--last 15m] [--size N]"
        emit(run_search("SELECT * FROM \"#{stream}\" ORDER BY _timestamp DESC LIMIT #{size}"))
      end

      def streams
        body = JSON.parse(request(Net::HTTP::Get, "/api/#{org}/streams"))
        @io.puts(body.fetch("list", []).map { |stream| stream["name"] }.compact.sort.join("\n"))
      end

      def search_body(sql, from, to)
        { query: { sql: sql, start_time: from, end_time: to, from: 0, size: size } }
      end

      def window(last)
        seconds = duration_seconds(last)
        now = (@clock.call * 1_000_000).to_i
        [now - (seconds * 1_000_000), now]
      end

      def duration_seconds(last)
        match = last.match(/\A(\d+)([smhd])\z/) or raise Error, "invalid --last: #{last}"
        match[1].to_i * UNITS.fetch(match[2])
      end

      def authorization
        token = require_env("OBSERVABILITY_TOKEN")
        token.match?(/\A(Basic|Bearer) /) ? token : "Basic #{token}"
      end

      private

      def run_search(sql)
        from, to = window(option("--last", "15m"))
        JSON.parse(request(Net::HTTP::Post, "/api/#{org}/_search", search_body(sql, from, to)))
            .fetch("hits", [])
      end

      def emit(hits) = @io.puts(JSON.pretty_generate(hits))

      def positional = @args.find { |arg| !arg.start_with?("--") }

      def option(flag, default)
        index = @args.index(flag)
        index && @args[index + 1] ? @args[index + 1] : default
      end

      def size = (option("--size", nil) || DEFAULT_SIZE).to_i

      def request(klass, path, body = nil)
        uri = URI("#{require_env('OBSERVABILITY_URL')}#{path}")
        response = http(uri).request(build_request(klass, uri, body))
        return response.body if response.is_a?(Net::HTTPSuccess)

        raise Error, "#{path} failed: #{response.code} #{response.body}"
      end

      def build_request(klass, uri, body)
        request = klass.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = authorization
        cf_access(request)
        request.body = JSON.generate(body) if body
        request
      end

      def cf_access(request)
        return unless @env["CF_ACCESS_CLIENT_ID"]

        request["CF-Access-Client-Id"] = @env["CF_ACCESS_CLIENT_ID"]
        request["CF-Access-Client-Secret"] = @env["CF_ACCESS_CLIENT_SECRET"]
      end

      def http(uri)
        client = Net::HTTP.new(uri.host, uri.port)
        client.use_ssl = uri.scheme == "https"
        client.open_timeout = TIMEOUT
        client.read_timeout = TIMEOUT
        client
      end

      def org = @env.fetch("OBSERVABILITY_ORG", "default")

      def require_env(key) = @env[key] || raise(Error, "missing env #{key}")
    end
  end
end
