# frozen_string_literal: true

require "cgi"
require "net/http"
require "uri"

module EiseronAutomation
  class PreviewPagesTrigger
    ACTIONS = %w[deploy stop].freeze
    PACKAGE_NAME = "site-preview"
    TARBALL = "preview-dist.tgz"

    def initialize(env: ENV, io: $stdout, runner: Runner.new, client: nil, uploader: nil)
      @env = env
      @io = io
      @runner = runner
      @client = client
      @uploader = uploader
    end

    def run
      action = require_in("PREVIEW_TRIGGER_ACTION", ACTIONS)
      variables = {
        "PREVIEW_ACTION" => action,
        "PREVIEW_KIND" => "pages",
        "PREVIEW_MR_IID" => require_env("CI_MERGE_REQUEST_IID"),
        "PREVIEW_SHA" => require_env("CI_COMMIT_SHA")
      }
      package if action == "deploy"
      result = client.trigger_pipeline(
        trigger_token: require_env("PREVIEW_DEPLOYER_TRIGGER_TOKEN"),
        ref: @env.fetch("PREVIEW_DEPLOYER_REF", "production"),
        variables: variables
      )
      @io.puts "Downstream pipeline: #{result['web_url']}"
    end

    private

    def package
      dist = require_env("PREVIEW_DIST_DIR")
      @runner.run({}, "tar", "-czf", TARBALL, "-C", dist, ".")
      uploader.call(package_url, TARBALL, require_env("CI_JOB_TOKEN"))
      @io.puts "Uploaded sealed dist to #{package_url}"
    end

    def package_url
      "#{require_env('CI_API_V4_URL')}/projects/#{require_env('CI_PROJECT_ID')}" \
        "/packages/generic/#{PACKAGE_NAME}/#{require_env('CI_COMMIT_SHA')}/#{TARBALL}"
    end

    def uploader
      @uploader ||= method(:put_package)
    end

    def put_package(url, path, job_token)
      uri = URI(url)
      request = Net::HTTP::Put.new(uri)
      request["JOB-TOKEN"] = job_token
      request.body = File.binread(path)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "package upload failed: #{response.code} #{response.body}"
    end

    def client
      @client ||= GitlabClient.new(
        api_url: require_env("CI_API_V4_URL"),
        project_id: CGI.escape(require_env("PREVIEW_DEPLOYER_PROJECT")),
        token: ""
      )
    end

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end

    def require_in(name, allowed)
      value = require_env(name)
      return value if allowed.include?(value)

      raise Error, "#{name}='#{value}' is not one of: #{allowed.join(', ')}"
    end
  end
end
