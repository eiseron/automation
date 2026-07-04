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

    PER_PAGE = 25

    def deployments(account_id, project)
      base_path = "/accounts/#{account_id}/pages/projects/#{project}/deployments?per_page=#{PER_PAGE}"
      results = []
      page = 1
      loop do
        response = request(Net::HTTP::Get, "#{base_path}&page=#{page}")
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "list deployments failed: #{response.code} #{response.body}"
        end

        body = JSON.parse(response.body)
        page_results = body.fetch("result", [])
        results.concat(page_results)
        total = body.dig("result_info", "total_count")&.to_i
        break if page_results.length < PER_PAGE || (total && results.length >= total)

        page += 1
      end
      results
    end

    def delete_deployment(account_id, project, deployment_id)
      path = "/accounts/#{account_id}/pages/projects/#{project}/deployments/#{deployment_id}?force=true"
      response = request(Net::HTTP::Delete, path)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "delete deployment #{deployment_id} failed: #{response.code} #{response.body}"
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
