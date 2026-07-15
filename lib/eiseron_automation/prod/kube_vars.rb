# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module EiseronAutomation
  module Prod
    class KubeVars
      SUFFIXES = %w[host cluster_ca_certificate token].freeze

      def initialize(env: ENV, io: $stdout, client: nil, prober: nil)
        @env = env
        @io = io
        @client = client
        @prober = prober
      end

      def gate
        host = @env[key("host")].to_s
        if host.empty?
          @io.puts "kube vars not published; nothing to reconcile"
          return
        end

        if reachable?(host, @env[key("cluster_ca_certificate")].to_s)
          @io.puts "kube endpoint healthy; vars stay"
          return
        end

        @io.puts "kube endpoint unreachable or unverifiable from CI; withdrawing the stale kube vars"
        withdraw
      end

      def publish
        host = require_env("KUBE_PUBLISH_HOST")
        ca = File.read(require_env("KUBE_PUBLISH_CA_FILE"))
        token = File.read(require_env("KUBE_PUBLISH_TOKEN_FILE"))

        unless reachable?(host, ca)
          @io.puts "kube endpoint unreachable or unverifiable from CI; withdrawing kube vars until the API port opens"
          withdraw
          return
        end

        publish_vars(host, ca, token)
      end

      private

      def publish_vars(host, ca_pem, token)
        was_ready = client.project_variable_exists?(key("host"), scope: scopes.last)
        set(key("host"), host, masked: false)
        set(key("cluster_ca_certificate"), ca_pem, masked: false)
        set(key("token"), token, masked: true)
        @io.puts "kube vars published"
        return if was_ready

        @io.puts "kube vars just became ready: triggering exactly one convergence pipeline"
        client.create_pipeline(ref: @env.fetch("KUBE_CONVERGENCE_REF", "production"))
      end

      def key(suffix)
        "#{require_env('KUBE_VARS_PREFIX')}#{suffix}"
      end

      def scopes
        @env.fetch("KUBE_VARS_SCOPES", "*,production").split(",").map(&:strip).reject(&:empty?)
      end

      def withdraw
        SUFFIXES.each do |suffix|
          scopes.each { |scope| client.delete_project_variable(key(suffix), scope: scope) }
        end
      end

      def set(name, value, masked:)
        scopes.each { |scope| client.set_project_variable(name, value, scope: scope, masked: masked) }
      end

      def reachable?(host, ca_pem)
        prober.call(host, ca_pem)
      end

      def prober
        @prober ||= lambda do |host, ca_pem|
          uri = URI.parse("#{host}/version")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 10
          http.read_timeout = 10
          http.cert_store = cert_store(ca_pem) if http.use_ssl?
          http.request(Net::HTTP::Get.new(uri.request_uri)).is_a?(Net::HTTPResponse)
        rescue StandardError
          false
        end
      end

      def cert_store(ca_pem)
        store = OpenSSL::X509::Store.new
        store.add_cert(OpenSSL::X509::Certificate.new(ca_pem))
        store
      end

      def client
        @client ||= GitlabClient.new(
          api_url: require_env("CI_API_V4_URL"),
          project_id: require_env("CI_PROJECT_ID"),
          token: require_env("KUBE_VARS_API_TOKEN")
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
