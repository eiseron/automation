# frozen_string_literal: true

require "net/http"
require "uri"

module EiseronAutomation
  module Observability
    class Deploy
      def initialize(env: ENV, io: $stdout, runner: Runner.new, http: nil)
        @env = env
        @io = io
        @runner = runner
        @http = http || method(:http_get)
      end

      SAFE_IDENT = /\A[a-zA-Z_][a-zA-Z0-9_-]*\z/

      def deploy
        tag = require_env("CI_COMMIT_SHORT_SHA")
        @io.puts "Deploying observability #{tag} (pre-built image, skip-push)"
        kamal("deploy", "--skip-push", "--version=#{tag}")
        reset_root(tag) if reset_requested?
        ensure_pg_monitor_role
        @io.puts "Converging accessories from the manifest"
        kamal("accessory", "reboot", "all", "--version=#{tag}")
        verify_ingestion
      end

      private

      def reset_requested? = @env["OBSERVABILITY_RESET_METADATA"] == "1"

      def ensure_pg_monitor_role
        password = @env["OBSERVABILITY_PG_MONITOR_PASSWORD"].to_s
        return @io.puts "Skipping pg_monitor role (OBSERVABILITY_PG_MONITOR_PASSWORD unset)" if password.empty?
        raise Error, "pg_monitor password must be alphanumeric" unless password.match?(/\A[A-Za-z0-9]+\z/)

        container = safe_ident("OBSERVABILITY_PG_CONTAINER", "platform-db")
        running = @runner.capture("ssh", *ssh_args, "docker ps -q -f name=^#{container}$").strip
        return @io.puts "Skipping pg_monitor role (#{container} not running)" if running.empty?

        role = safe_ident("OBSERVABILITY_PG_MONITOR_USER", "monitoring")
        admin = safe_ident("PG_ADMIN_USER", "eiseron")
        @io.puts "Ensuring #{role} monitoring role on #{container}"
        @runner.run_stdin(
          build_pg_monitor_sql(password), @env,
          "ssh", *ssh_args,
          "docker exec -i #{container} psql -U #{admin} -d postgres " \
          "-v ON_ERROR_STOP=1 -v rname=#{role} -v climit=5"
        )
      end

      def build_pg_monitor_sql(password)
        <<~SQL
          \\set rpw '#{password}'
          SELECT format('CREATE ROLE %I LOGIN', :'rname')
          WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'rname')
          \\gexec
          ALTER ROLE :"rname" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT :climit PASSWORD :'rpw';
          GRANT pg_monitor TO :"rname";
        SQL
      end

      def safe_ident(name, default)
        value = @env.fetch(name, default)
        raise Error, "#{name} is not a safe identifier: #{value}" unless value.match?(SAFE_IDENT)

        value
      end

      def reset_root(tag)
        @io.puts "Resetting OpenObserve root user"
        cid = @runner.capture("ssh", *ssh_args, "docker ps -q -f name=observability-web-#{tag}").strip
        raise Error, "observability-web container not found" if cid.empty?
        raise Error, "unexpected container id from docker ps" unless cid.match?(/\A[0-9a-f]+\z/)

        @runner.run(@env, "ssh", *ssh_args, "docker exec #{cid} /openobserve reset --component root")
        @io.puts "Restarting observability-web so it reloads the reset metadata"
        @runner.run(@env, "ssh", *ssh_args, "docker restart #{cid}")
      end

      def verify_ingestion
        host = @env["OBSERVABILITY_HOST"].to_s
        basic = @env["OBSERVABILITY_OTLP_BASIC"].to_s
        return @io.puts "Skipping ingestion verify (missing host or auth)" if host.empty? || basic.empty?

        org = @env.fetch("OBSERVABILITY_OTLP_ORG", "default")
        @io.puts "Verifying OpenObserve ingestion (org #{org})"
        @io.puts @http.call("https://#{host}/api/#{org}/streams", "Basic #{basic}")
      end

      def http_get(url, authorization)
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = authorization
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                       open_timeout: 25, read_timeout: 25) do |http|
          http.request(request)
        end
        "HTTP #{response.code} #{response.body}"
      rescue StandardError => e
        "HTTP request failed: #{e.class}"
      end

      def ssh_args
        ["-o", "StrictHostKeyChecking=accept-new",
         "#{@env.fetch('DEPLOY_SSH_USER', 'deploy')}@#{require_env('PROD_HOST')}"]
      end

      def kamal(*) = @runner.run(@env, "kamal", *)

      def require_env(name)
        value = @env[name].to_s
        raise Error, "missing required env #{name}" if value.empty?

        value
      end
    end
  end
end
