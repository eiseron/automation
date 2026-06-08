# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "uri"

module EiseronAutomation
  class GitlabClient
    def initialize(api_url:, project_id:, token:)
      @base = "#{api_url}/projects/#{project_id}"
      @token = token
    end

    def tag_exists?(tag)
      http(Net::HTTP::Get, "/repository/tags/#{encode(tag)}").is_a?(Net::HTTPSuccess)
    end

    def create_tag(tag, ref)
      post("/repository/tags", tag_name: tag, ref: ref)
    end

    def release_tags
      names = []
      page = 1
      while page <= 50
        response = http(Net::HTTP::Get, "/repository/tags?per_page=100&page=#{page}")
        raise Error, "GET /repository/tags failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        batch = JSON.parse(response.body)
        break if batch.empty?

        names.concat(batch.map { |tag| tag["name"].to_s })
        page += 1
      end
      names
    end

    def open_merge_request_iids
      iids = []
      page = 1
      while page <= 50
        response = http(Net::HTTP::Get, "/merge_requests?state=opened&per_page=100&page=#{page}")
        raise Error, "GET /merge_requests failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        batch = JSON.parse(response.body)
        break if batch.empty?

        iids.concat(batch.map { |merge_request| merge_request["iid"].to_s })
        page += 1
      end
      iids
    end

    private

    def encode(value)
      CGI.escape(value)
    end

    def post(path, params)
      response = http(Net::HTTP::Post, path, params)
      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, "POST #{path} failed: #{response.code} #{response.body}"
    end

    def http(verb, path, params = nil)
      uri = URI("#{@base}#{path}")
      request = verb.new(uri)
      request["PRIVATE-TOKEN"] = @token
      request.set_form_data(params) if params
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |client|
        client.request(request)
      end
    end
  end
end
