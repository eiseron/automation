# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "uri"

module EiseronAutomation
  class GitlabClient
    def initialize(api_url:, project_id:, token:, token_header: "PRIVATE-TOKEN")
      @base = "#{api_url}/projects/#{project_id}"
      @token = token
      @token_header = token_header
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

    def trigger_pipeline(trigger_token:, ref:, variables: {})
      params = { "token" => trigger_token, "ref" => ref }
      variables.each { |key, value| params["variables[#{key}]"] = value }
      response = http(Net::HTTP::Post, "/trigger/pipeline", params, auth: false)
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

      raise Error, "POST /trigger/pipeline failed: #{response.code} #{response.body}"
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

    def merge_request_state(iid)
      response = http(Net::HTTP::Get, "/merge_requests/#{encode(iid.to_s)}")
      return "not_found" if response.is_a?(Net::HTTPNotFound)
      return "error" unless response.is_a?(Net::HTTPSuccess)

      state = JSON.parse(response.body).fetch("state", "")
      %w[opened merged closed].include?(state) ? state : "error"
    rescue StandardError
      "error"
    end

    def find_registry_repository(suffix)
      page = 1
      while page <= 50
        response = http(Net::HTTP::Get, "/registry/repositories?per_page=100&page=#{page}")
        raise Error, "GET /registry/repositories failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        batch = JSON.parse(response.body)
        break if batch.empty?

        match = batch.find { |repo| repo["path"].to_s.end_with?(suffix) }
        return match["id"] if match

        page += 1
      end
      nil
    end

    def list_registry_tags(repo_id)
      tags = []
      page = 1
      while page <= 50
        response = http(Net::HTTP::Get, "/registry/repositories/#{repo_id}/tags?per_page=100&page=#{page}")
        raise Error, "GET registry tags failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        batch = JSON.parse(response.body)
        break if batch.empty?

        tags.concat(batch.map { |tag| tag["name"].to_s })
        page += 1
      end
      tags
    end

    def delete_registry_tag(repo_id, name)
      response = http(Net::HTTP::Delete, "/registry/repositories/#{repo_id}/tags/#{encode(name)}")
      case response
      when Net::HTTPSuccess, Net::HTTPNotFound then true
      else
        raise Error, "DELETE registry tag #{name} failed: #{response.code}"
      end
    end

    def pipeline_jobs(pipeline_id)
      jobs = []
      page = 1
      while page <= 50
        response = http(Net::HTTP::Get, "/pipelines/#{encode(pipeline_id.to_s)}/jobs?per_page=100&page=#{page}")
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "GET /pipelines/#{pipeline_id}/jobs failed: #{response.code}"
        end

        batch = JSON.parse(response.body)
        break if batch.empty?

        jobs.concat(batch)
        page += 1
      end
      jobs
    end

    def last_successful_pipeline(ref)
      response = http(Net::HTTP::Get, "/pipelines?ref=#{encode(ref)}&status=success&per_page=1")
      raise Error, "GET /pipelines failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).first
    end

    def project_variable_exists?(key, scope:)
      http(Net::HTTP::Get, variable_path(key, scope)).is_a?(Net::HTTPSuccess)
    end

    def set_project_variable(key, value, scope:, masked: false, protected: true)
      params = { "value" => value, "masked" => masked.to_s, "protected" => protected.to_s,
                 "environment_scope" => scope }
      response = http(Net::HTTP::Put, variable_path(key, scope), params)
      return if response.is_a?(Net::HTTPSuccess)

      post("/variables", params.merge("key" => key))
    end

    def delete_project_variable(key, scope:)
      response = http(Net::HTTP::Delete, variable_path(key, scope))
      case response
      when Net::HTTPSuccess, Net::HTTPNotFound then true
      else
        raise Error, "DELETE variable #{key} (#{scope}) failed: #{response.code}"
      end
    end

    def create_pipeline(ref:)
      response = post("/pipeline", "ref" => ref)
      JSON.parse(response.body)
    end

    private

    def variable_path(key, scope)
      "/variables/#{encode(key)}?filter%5Benvironment_scope%5D=#{encode(scope)}"
    end

    def encode(value)
      CGI.escape(value)
    end

    def post(path, params)
      response = http(Net::HTTP::Post, path, params)
      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, "POST #{path} failed: #{response.code} #{response.body}"
    end

    def http(verb, path, params = nil, auth: true)
      uri = URI("#{@base}#{path}")
      request = verb.new(uri)
      request[@token_header] = @token if auth
      request.set_form_data(params) if params
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |client|
        client.request(request)
      end
    end
  end
end
