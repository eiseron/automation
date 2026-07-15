# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class KubeVarsTest < Minitest::Test
    class FakeClient
      attr_reader :deleted, :set, :pipelines

      def initialize(existing: [])
        @existing = existing
        @deleted = []
        @set = []
        @pipelines = []
      end

      def project_variable_exists?(key, scope:)
        @existing.include?([key, scope])
      end

      def set_project_variable(key, value, scope:, masked: false, protected: true)
        @set << { key: key, value: value, scope: scope, masked: masked, protected: protected }
        nil
      end

      def delete_project_variable(key, scope:)
        @deleted << [key, scope]
        nil
      end

      def create_pipeline(ref:)
        @pipelines << ref
        { "web_url" => "https://gitlab.example/pipelines/1" }
      end
    end

    def setup
      @io = StringIO.new
      @client = FakeClient.new
    end

    def base_env
      {
        "KUBE_VARS_PREFIX" => "TF_VAR_acme_kube_",
        "KUBE_VARS_API_TOKEN" => "secret",
        "CI_API_V4_URL" => "https://gitlab.example/api/v4",
        "CI_PROJECT_ID" => "42"
      }
    end

    def gate(env, reachable:)
      Prod::KubeVars.new(env: base_env.merge(env), io: @io, client: @client,
                         prober: ->(_host, _ca) { reachable }).gate
    end

    def test_gate_skips_when_vars_not_published
      gate({}, reachable: true)
      assert_includes @io.string, "nothing to reconcile"
    end

    def test_gate_keeps_vars_when_endpoint_healthy
      gate({ "TF_VAR_acme_kube_host" => "https://198.51.100.7:6443",
             "TF_VAR_acme_kube_cluster_ca_certificate" => "PEM" }, reachable: true)
      assert_empty @client.deleted
    end

    def test_gate_withdraws_all_vars_in_all_scopes_when_unreachable
      gate({ "TF_VAR_acme_kube_host" => "https://198.51.100.7:6443",
             "TF_VAR_acme_kube_cluster_ca_certificate" => "PEM" }, reachable: false)
      assert_equal 6, @client.deleted.length
      assert_includes @client.deleted, %w[TF_VAR_acme_kube_token production]
      assert_includes @client.deleted, ["TF_VAR_acme_kube_host", "*"]
    end

    def publish_env(dir)
      ca = File.join(dir, "ca.pem")
      token = File.join(dir, "token")
      File.write(ca, "PEM")
      File.write(token, "k8s-token")
      base_env.merge(
        "KUBE_PUBLISH_HOST" => "https://198.51.100.7:6443",
        "KUBE_PUBLISH_CA_FILE" => ca,
        "KUBE_PUBLISH_TOKEN_FILE" => token
      )
    end

    def publish(reachable:, existing: [])
      @client = FakeClient.new(existing: existing)
      Dir.mktmpdir do |dir|
        Prod::KubeVars.new(env: publish_env(dir), io: @io, client: @client,
                           prober: ->(_host, _ca) { reachable }).publish
      end
    end

    def test_publish_withdraws_when_endpoint_unreachable
      publish(reachable: false)
      assert_equal 6, @client.deleted.length
      assert_empty @client.set
    end

    def test_publish_sets_vars_with_masked_token_when_reachable
      publish(reachable: true)
      token_sets = @client.set.select { |entry| entry[:key] == "TF_VAR_acme_kube_token" }
      assert_equal 2, token_sets.length
      assert(token_sets.all? { |entry| entry[:masked] })
    end

    def test_publish_triggers_one_convergence_pipeline_on_first_readiness
      publish(reachable: true)
      assert_equal ["production"], @client.pipelines
    end

    def test_publish_does_not_trigger_when_already_ready
      publish(reachable: true, existing: [%w[TF_VAR_acme_kube_host production]])
      assert_empty @client.pipelines
    end
  end
end
