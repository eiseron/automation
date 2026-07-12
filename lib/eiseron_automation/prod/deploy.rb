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
        roll_out(tag)
        migrate(tag)
      end

      def setup
        tag = require_env("PROD_TAG")
        raise Error, "PROD_TAG '#{tag}' is not a release tag (vMAJOR.MINOR.PATCH)" unless Plan.parse(tag)
        unless @env.fetch("CI_PIPELINE_SOURCE", "") == "web"
          raise Error,
                "prod setup skips the latest-release guard; run it from a manual web pipeline."
        end

        ensure_tenant_password
        @io.puts "Setting up #{app} at #{tag} (first deploy)"
        roll_out(tag)
        migrate(tag)
      end

      def backup
        @io.puts "Requesting an on-demand CloudNativePG backup of #{pg_cluster}"
        @runner.run_stdin(backup_manifest, @env.to_h, "kubectl", "create", "-n", pg_namespace, "-f", "-")
      end

      private

      def roll_out(tag)
        @io.puts "Rolling out #{app} to #{tag}"
        kubectl("set", "image", "deployment/#{app}", "#{app}=#{image}:#{tag}", "-n", namespace)
        kubectl("rollout", "status", "deployment/#{app}", "-n", namespace, "--timeout=#{rollout_timeout}")
      end

      def migrate(tag)
        @io.puts "Running migrations for #{tag}"
        kubectl("exec", "-n", namespace, "deployment/#{app}", "--", *migrate_command)
      end

      def ensure_tenant_password = tenant.ensure_password

      def kubectl(*)
        @runner.run(@env.to_h, "kubectl", *)
      end

      def backup_manifest
        <<~YAML
          apiVersion: postgresql.cnpg.io/v1
          kind: Backup
          metadata:
            generateName: #{pg_cluster}-ondemand-
            namespace: #{pg_namespace}
          spec:
            cluster:
              name: #{pg_cluster}
        YAML
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

      def app = @env.fetch("PROD_APP", slug)
      def namespace = @env.fetch("PROD_NAMESPACE", app)
      def image = require_env("PROD_IMAGE")
      def migrate_command = require_env("PROD_MIGRATE_CMD").split
      def rollout_timeout = @env.fetch("PROD_ROLLOUT_TIMEOUT", "300s")
      def pg_cluster = @env.fetch("PG_CLUSTER", "platform-db")
      def pg_namespace = @env.fetch("PG_NAMESPACE", "platform")
      def slug = require_env("PROD_TENANT_SLUG")

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
