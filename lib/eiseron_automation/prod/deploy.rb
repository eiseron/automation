# frozen_string_literal: true

require "cgi"

module EiseronAutomation
  module Prod
    class Deploy
      def initialize(env: ENV, io: $stdout, runner: Runner.new, client: nil)
        @env = env
        @io = io
        @runner = runner
        @client = client
      end

      def deploy
        tag = require_env("PROD_TAG")
        guard_downgrade(tag)
        ensure_tenant_password
        @io.puts "Deploying #{tag} (pre-built image, skip-push)"
        kamal("deploy", "--version=#{tag}", "--skip-push")
        @io.puts "Converging accessories from the manifest"
        kamal("accessory", "reboot", "all", "--version=#{tag}")
      end

      def setup
        tag = require_env("PROD_TAG")
        raise Error, "PROD_TAG '#{tag}' is not a release tag (vMAJOR.MINOR.PATCH)" unless Plan.parse(tag)
        unless @env.fetch("CI_PIPELINE_SOURCE", "") == "web"
          raise Error,
                "prod setup bootstraps a host and skips the latest-release guard; run it from a manual web pipeline."
        end

        ensure_tenant_password
        @io.puts "Setting up #{tag} (first deploy: accessories + env + app, skip-push)"
        kamal("setup", "--version=#{tag}", "--skip-push")
      end

      def backup
        @io.puts "Running an on-demand backup in the backup accessory"
        kamal("accessory", "exec", "backup", "eiseron", "db", "backup")
      end

      private

      def ensure_tenant_password
        tenant.ensure_password
      end

      def kamal(*)
        @runner.run(kamal_env, "kamal", *)
      end

      def kamal_env
        @kamal_env ||= @env.to_h.merge("DATABASE_URL" => tenant.database_url)
      end

      def tenant
        @tenant ||= Tenant.new(env: @env, io: @io, runner: @runner)
      end

      def guard_downgrade(tag)
        raise Error, "PROD_TAG '#{tag}' is not a release tag (vMAJOR.MINOR.PATCH)" unless Plan.parse(tag)

        if allow_old?
          @io.puts "PROD_DEPLOY_ALLOW_OLD set; skipping the latest-release guard (manual rollback)."
          return
        end
        return if Plan.latest?(tag, client.release_tags)

        raise Error,
              "#{tag} is not the latest release of #{require_env('PROD_PROJECT')}; refusing to auto-deploy a " \
              "non-latest tag. Re-run as a manual pipeline with PROD_DEPLOY_ALLOW_OLD=true to roll back."
      end

      def allow_old?
        @env.fetch("PROD_DEPLOY_ALLOW_OLD", "") == "true" && @env.fetch("CI_PIPELINE_SOURCE", "") == "web"
      end

      def client
        @client ||= GitlabClient.new(
          api_url: require_env("CI_API_V4_URL"),
          project_id: CGI.escape(require_env("PROD_PROJECT")),
          token: require_env("PROD_DEPLOY_READ_TOKEN")
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
