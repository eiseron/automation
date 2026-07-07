# frozen_string_literal: true

require "cgi"

module EiseronAutomation
  module Prod
    class Trigger
      def initialize(env: ENV, io: $stdout, client: nil)
        @env = env
        @io = io
        @client = client
      end

      def run
        project = @env.fetch("PROD_DEPLOYER_PROJECT", "")
        token = @env.fetch("PROD_DEPLOYER_TRIGGER_TOKEN", "")
        if project.empty? || token.empty?
          @io.puts "deployer trigger unset; skipping prod deploy trigger (product not configured for prod)"
          return
        end

        tag = require_env("CI_COMMIT_TAG")
        result = client(project).trigger_pipeline(
          trigger_token: token,
          ref: "production",
          variables: {
            "PROD_TAG" => tag,
            "PROD_IMAGE" => "#{require_env('CI_REGISTRY_IMAGE')}/prod:#{tag}",
            "PROD_PROJECT" => require_env("CI_PROJECT_PATH"),
            "PROD_ACTION" => "deploy"
          }
        )
        @io.puts "Downstream pipeline: #{result['web_url']}"
      end

      private

      def client(project)
        @client ||= GitlabClient.new(
          api_url: require_env("CI_API_V4_URL"),
          project_id: CGI.escape(project),
          token: ""
        )
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
