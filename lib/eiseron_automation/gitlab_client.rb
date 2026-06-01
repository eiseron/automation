# frozen_string_literal: true

require "cgi"
require "net/http"
require "uri"

module EiseronAutomation
  # Thin GitLab REST client covering only the calls the release flow needs.
  # Side-effecting by design: every public method performs one HTTP request.
  class GitlabClient
    def initialize(api_url:, project_id:, token:)
      @base = "#{api_url}/projects/#{project_id}"
      @token = token
    end

    def tag_exists?(tag)
      http(Net::HTTP::Get, "/repository/tags/#{encode(tag)}").is_a?(Net::HTTPSuccess)
    end

    def delete_tag_protection(wildcard = "*")
      http(Net::HTTP::Delete, "/protected_tags/#{encode(wildcard)}")
    end

    def create_tag(tag, ref)
      post("/repository/tags", tag_name: tag, ref: ref)
    end

    def protect_tags_no_one(wildcard = "*")
      post("/protected_tags", name: wildcard, create_access_level: 0)
    end

    private

    # CGI.escape percent-encodes path-unsafe characters (notably '*' -> '%2A'),
    # which URI.encode_www_form_component leaves untouched. Tag names and the
    # wildcard never contain spaces, so the '+'-for-space difference is moot.
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
