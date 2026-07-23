# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class PreviewTriggerTest < Minitest::Test
    class FakeClient
      attr_reader :calls

      def initialize
        @calls = []
      end

      def trigger_pipeline(**kwargs)
        @calls << kwargs
        { "web_url" => "https://gitlab.com/down/-/pipelines/42" }
      end
    end

    def base_env
      {
        "PREVIEW_TRIGGER_ACTION" => "deploy",
        "PREVIEW_TRIGGER_KIND" => "mr",
        "PREVIEW_TRIGGER_REF" => "feat-foo",
        "PREVIEW_TRIGGER_MR_IID" => "12",
        "PREVIEW_DEPLOYER_PROJECT" => "acme/app/app-ops",
        "PREVIEW_DEPLOYER_TRIGGER_TOKEN" => "trig-tok",
        "CI_REGISTRY_IMAGE" => "registry.gitlab.com/acme/app/app",
        "CI_COMMIT_SHA" => "abcdef123",
        "CI_API_V4_URL" => "https://gitlab.com/api/v4",
        "CI_PROJECT_PATH" => "acme/app/app"
      }
    end

    def run_trigger(env)
      client = FakeClient.new
      PreviewTrigger.new(env: env, io: StringIO.new, client: client).run
      client
    end

    def test_targets_deployer_ref_production_by_default
      call = run_trigger(base_env).calls.fetch(0)
      assert_equal "production", call[:ref]
      assert_equal "trig-tok", call[:trigger_token]
    end

    def test_deployer_ref_overrides_via_env
      call = run_trigger(base_env.merge("PREVIEW_DEPLOYER_REF" => "release/v1")).calls.fetch(0)
      assert_equal "release/v1", call[:ref]
    end

    def test_mr_deploy_carries_action_kind_ref_sha_iid_and_image_repo
      vars = run_trigger(base_env).calls.fetch(0).fetch(:variables)
      assert_equal "deploy", vars["PREVIEW_ACTION"]
      assert_equal "mr", vars["PREVIEW_KIND"]
      assert_equal "feat-foo", vars["PREVIEW_REF"]
      assert_equal "abcdef123", vars["PREVIEW_SHA"]
      assert_equal "12", vars["PREVIEW_MR_IID"]
      assert_equal "registry.gitlab.com/acme/app/app/preview", vars["PREVIEW_IMAGE_REPO"]
      assert_equal "acme/app/app", vars["PREVIEW_PROJECT_PATH"]
    end

    def test_requires_ci_project_path
      err = assert_raises(Error) { run_trigger(base_env.except("CI_PROJECT_PATH")) }
      assert_match(/CI_PROJECT_PATH/, err.message)
    end

    def test_main_deploy_omits_mr_iid_when_unset
      env = base_env
            .merge("PREVIEW_TRIGGER_KIND" => "main", "PREVIEW_TRIGGER_REF" => "main")
            .except("PREVIEW_TRIGGER_MR_IID")
      vars = run_trigger(env).calls.fetch(0).fetch(:variables)
      refute_includes vars, "PREVIEW_MR_IID"
      assert_equal "main", vars["PREVIEW_KIND"]
      assert_equal "main", vars["PREVIEW_REF"]
    end

    def test_mr_deploy_rejects_missing_mr_iid
      env = base_env.except("PREVIEW_TRIGGER_MR_IID")
      err = assert_raises(Error) { run_trigger(env) }
      assert_match(/PREVIEW_TRIGGER_MR_IID is required when PREVIEW_TRIGGER_KIND=mr/, err.message)
    end

    def test_stop_carries_action_stop
      vars = run_trigger(base_env.merge("PREVIEW_TRIGGER_ACTION" => "stop")).calls.fetch(0).fetch(:variables)
      assert_equal "stop", vars["PREVIEW_ACTION"]
    end

    def test_rejects_unknown_action
      err = assert_raises(Error) { run_trigger(base_env.merge("PREVIEW_TRIGGER_ACTION" => "wipe")) }
      assert_match(/PREVIEW_TRIGGER_ACTION='wipe'/, err.message)
    end

    def test_rejects_unknown_kind
      err = assert_raises(Error) { run_trigger(base_env.merge("PREVIEW_TRIGGER_KIND" => "branch")) }
      assert_match(/PREVIEW_TRIGGER_KIND='branch'/, err.message)
    end

    def test_requires_deployer_trigger_token
      err = assert_raises(Error) { run_trigger(base_env.except("PREVIEW_DEPLOYER_TRIGGER_TOKEN")) }
      assert_match(/PREVIEW_DEPLOYER_TRIGGER_TOKEN/, err.message)
    end

    def test_requires_commit_sha
      err = assert_raises(Error) { run_trigger(base_env.except("CI_COMMIT_SHA")) }
      assert_match(/CI_COMMIT_SHA/, err.message)
    end

    def test_requires_registry_image
      err = assert_raises(Error) { run_trigger(base_env.except("CI_REGISTRY_IMAGE")) }
      assert_match(/CI_REGISTRY_IMAGE/, err.message)
    end
  end
end
