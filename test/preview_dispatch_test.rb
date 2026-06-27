# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class PreviewDispatchTest < Minitest::Test
    class FakeRunner
      attr_reader :runs

      def initialize
        @runs = []
      end

      def run(env, *cmd)
        @runs << { env: env, cmd: cmd }
      end
    end

    def base_env
      {
        "PREVIEW_REF" => "feat-foo",
        "PREVIEW_SHA" => "abcdef123",
        "PREVIEW_MR_IID" => "12"
      }
    end

    def dispatch(env)
      runner = FakeRunner.new
      PreviewDispatch.new(env: env, io: StringIO.new, runner: runner).run
      runner
    end

    def test_deploy_runs_deploy_sh_with_ref_sha_iid
      cmd = dispatch(base_env.merge("PREVIEW_ACTION" => "deploy")).runs.fetch(0).fetch(:cmd)
      assert_equal ["deployer/deploy.sh", "feat-foo", "abcdef123", "12"], cmd
    end

    def test_stop_runs_stop_sh_with_ref_only
      cmd = dispatch(base_env.merge("PREVIEW_ACTION" => "stop")).runs.fetch(0).fetch(:cmd)
      assert_equal ["deployer/stop.sh", "feat-foo"], cmd
    end

    def test_sweep_runs_sweep_sh_with_no_args
      env = { "PREVIEW_ACTION" => "sweep" }
      cmd = dispatch(env).runs.fetch(0).fetch(:cmd)
      assert_equal ["deployer/sweep.sh"], cmd
    end

    def test_deployer_path_overrides_via_env
      env = base_env.merge("PREVIEW_ACTION" => "deploy", "PREVIEW_DEPLOYER_PATH" => "environments/dev/deployer")
      cmd = dispatch(env).runs.fetch(0).fetch(:cmd)
      assert_equal "environments/dev/deployer/deploy.sh", cmd.first
    end

    def test_rejects_unknown_action
      err = assert_raises(Error) { dispatch(base_env.merge("PREVIEW_ACTION" => "bomb")) }
      assert_match(/PREVIEW_ACTION='bomb'/, err.message)
    end

    def test_deploy_requires_ref_and_sha
      env = { "PREVIEW_ACTION" => "deploy", "PREVIEW_SHA" => "abc", "PREVIEW_MR_IID" => "9" }
      err = assert_raises(Error) { dispatch(env) }
      assert_match(/PREVIEW_REF/, err.message)
    end

    def test_main_deploy_passes_empty_mr_iid
      env = { "PREVIEW_ACTION" => "deploy", "PREVIEW_REF" => "main", "PREVIEW_SHA" => "abc", "PREVIEW_KIND" => "main" }
      cmd = dispatch(env).runs.fetch(0).fetch(:cmd)
      assert_equal ["deployer/deploy.sh", "main", "abc", ""], cmd
    end

    def test_stop_requires_ref
      err = assert_raises(Error) { dispatch("PREVIEW_ACTION" => "stop") }
      assert_match(/PREVIEW_REF/, err.message)
    end

    def test_passes_env_through_to_command
      env = base_env.merge("PREVIEW_ACTION" => "deploy", "GITLAB_API_TOKEN" => "tok-1")
      passed = dispatch(env).runs.fetch(0).fetch(:env)
      assert_equal "tok-1", passed["GITLAB_API_TOKEN"]
    end
  end
end
