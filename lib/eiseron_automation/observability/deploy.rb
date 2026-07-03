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

      def deploy
        tag = require_env("CI_COMMIT_SHORT_SHA")
        @io.puts "Deploying observability #{tag} (pre-built image, skip-push)"
        kamal("deploy", "--skip-push", "--version=#{tag}")
        reset_root(tag) if reset_requested?
        @io.puts "Converging accessories from the manifest"
        kamal("accessory", "reboot", "all", "--version=#{tag}")
        verify_ingestion
      end

      private

      def reset_requested? = @env["OBSERVABILITY_RESET_METADATA"] == "1"

      def reset_root(tag)
        @io.puts "Resetting OpenObserve root user"
        cid = @runner.capture("ssh", *ssh_args, "docker ps -q -f name=observability-web-#{tag}").strip
        raise Error, "observability-web container not found" if cid.empty?
        raise Error, "unexpected container id from docker ps" unless cid.match?(/\A[0-9a-f]+\z/)

        @runner.run(@env, "ssh", *ssh_args, "docker exec #{cid} /openobserve reset --component root")
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
