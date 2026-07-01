# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EiseronAutomation
  class CloudflareClient
    BASE = "https://api.cloudflare.com/client/v4"

    def initialize(token:, base: BASE)
      @token = token
      @base = base
    end

    def deployments(account_id, project)
      path = "/accounts/#{account_id}/pages/projects/#{project}/deployments?env=preview&per_page=100"
      response = request(Net::HTTP::Get, path)
      raise Error, "list deployments failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("result", [])
    end

    def delete_deployment(account_id, project, deployment_id)
      path = "/accounts/#{account_id}/pages/projects/#{project}/deployments/#{deployment_id}?force=true"
      response = request(Net::HTTP::Delete, path)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "delete deployment #{deployment_id} failed: #{response.code}"
    end

    private

    def request(verb, path)
      uri = URI("#{@base}#{path}")
      req = verb.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    end
  end
end
