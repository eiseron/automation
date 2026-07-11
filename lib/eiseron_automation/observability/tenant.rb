# frozen_string_literal: true

require "digest"
require "net/http"
require "uri"

module EiseronAutomation
  module Observability
    class Tenant
      TIMEOUT = 25
      TABLES = %w[
        otel_logs
        otel_traces
        otel_metrics_gauge
        otel_metrics_sum
        otel_metrics_histogram
        otel_metrics_exponential_histogram
        otel_metrics_summary
      ].freeze

      def initialize(env:, io:, args: [])
        @env = env
        @io = io
        @args = args
      end

      def provision
        product = valid_product
        build_statements(product, password_hash).each { |sql| execute(sql) }
        @io.puts("provisioned tenant #{product}: reader #{reader(product)} scoped to ServiceName='#{product}'")
      end

      def build_statements(product, hash)
        reader = reader(product)
        [
          "CREATE USER IF NOT EXISTS #{reader} IDENTIFIED WITH sha256_hash BY '#{hash}'",
          "GRANT SELECT ON #{database}.* TO #{reader}",
          *TABLES.map { |table| row_policy(product, reader, table) }
        ]
      end

      def valid_product
        product = positional or raise Error, "usage: obs tenant <product>"
        product.match?(/\A[a-z][a-z0-9_-]*\z/) or raise Error, "invalid product '#{product}' (use [a-z][a-z0-9_-]*)"
        product
      end

      def reader(product) = "#{product}_reader"

      private

      def row_policy(product, reader, table)
        "CREATE ROW POLICY IF NOT EXISTS #{product}_#{table} ON #{database}.#{table} " \
          "FOR SELECT USING ServiceName = '#{product}' TO #{reader}"
      end

      def password_hash
        Digest::SHA256.hexdigest(require_env("TENANT_READER_PASSWORD"))
      end

      def positional = @args.find { |arg| !arg.start_with?("--") }

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
