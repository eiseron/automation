# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdTriggerTest < Minitest::Test
    class FakeClient
      attr_reader :calls

      def initialize
        @calls = []
      end

      def trigger_pipeline(**kwargs)
        @calls << kwargs
        { "web_url" => "https://gitlab.com/down/-/pipelines/1" }
      end
    end

    def base_env
      {
        "PROD_DEPLOYER_PROJECT" => "eiseron/afinados/afinados-ops",
        "PROD_DEPLOYER_TRIGGER_TOKEN" => "trigger-tok",
        "CI_COMMIT_TAG" => "v1.2.3",
        "CI_REGISTRY_IMAGE" => "registry.gitlab.com/eiseron/afinados/afinados",
        "CI_PROJECT_PATH" => "eiseron/afinados/afinados",
        "CI_API_V4_URL" => "https://gitlab.com/api/v4"
      }
    end

    def run_trigger(env)
      client = FakeClient.new
      Prod::Trigger.new(env: env, io: StringIO.new, client: client).run
      client
    end

    def test_skips_when_deployer_project_absent
      client = run_trigger(base_env.except("PROD_DEPLOYER_PROJECT"))
      assert_empty client.calls
    end

    def test_skips_when_trigger_token_absent
      client = run_trigger(base_env.except("PROD_DEPLOYER_TRIGGER_TOKEN"))
      assert_empty client.calls
    end

    def test_triggers_with_main_ref_and_token
      call = run_trigger(base_env).calls.fetch(0)
      assert_equal "trigger-tok", call[:trigger_token]
      assert_equal "main", call[:ref]
    end

    def test_trigger_variables_carry_tag_image_project_action
      vars = run_trigger(base_env).calls.fetch(0).fetch(:variables)
      assert_equal "v1.2.3", vars["PROD_TAG"]
      assert_equal "registry.gitlab.com/eiseron/afinados/afinados/prod:v1.2.3", vars["PROD_IMAGE"]
      assert_equal "eiseron/afinados/afinados", vars["PROD_PROJECT"]
      assert_equal "deploy", vars["PROD_ACTION"]
    end
  end
end
