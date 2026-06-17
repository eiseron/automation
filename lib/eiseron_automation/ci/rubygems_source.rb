# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EiseronAutomation
  module CI
    class RubyGemsSource
      ENDPOINT = "https://rubygems.org/api/v1/versions"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      def initialize(http: Net::HTTP)
        @http = http
      end

      def candidates(entry)
        fetch(entry[:source])
          .reject { |row| row["prerelease"] }
          .map { |row| { version: row["number"], sha: row["sha"] } }
      end

      def finalize(entry, candidate)
        { gem: entry[:source], version: candidate[:version], sha: candidate[:sha] }
      end

      private

      def fetch(name)
        uri = URI.parse("#{ENDPOINT}/#{URI.encode_www_form_component(name)}.json")
        response = @http.start(uri.host, uri.port, use_ssl: true,
                                                   open_timeout: OPEN_TIMEOUT,
                                                   read_timeout: READ_TIMEOUT) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri))
        end
        raise Error, "rubygems #{name} fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
