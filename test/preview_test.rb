# frozen_string_literal: true

require "test_helper"
require "json"

module EiseronAutomation
  class PreviewTest < Minitest::Test
    class FakeRunner
      attr_reader :runs, :capture_cmd

      def initialize(capture_output: "")
        @runs = []
        @capture_output = capture_output
      end

      def run(env, *cmd)
        @runs << { env: env, cmd: cmd }
      end

      def capture(*cmd)
        @capture_cmd = cmd
        @capture_output
      end
    end

    FakeClient = Struct.new(:iids) do
      def open_merge_request_iids
        iids
      end
    end

    def base_env
      {
        "EISERON_PREVIEW_APP" => "holter",
        "EISERON_PREVIEW_SUFFIX" => "-preview",
        "EISERON_PREVIEW_ZONE" => "holter.dev",
        "EISERON_PREVIEW_DB_SCHEME" => "ecto",
        "PREVIEW_HOST_IP" => "1.2.3.4",
        "PREVIEW_TENANT_NAME" => "holter",
        "PREVIEW_TENANT_PASSWORD" => "p@ss/word",
        "ANSIBLE_PRIVATE_KEY_FILE" => "/tmp/key"
      }
    end

    def test_database_url_percent_encodes_the_password
      url = PreviewPlan.database_url(
        dsn: "ecto://shared-pg:5432", tenant: "holter",
        password: "p@ss/word", database: "holter_mr5"
      )
      assert_equal "ecto://holter:p%40ss%2Fword@shared-pg:5432/holter_mr5", url
    end

    def test_app_env_merges_extra_over_database_url
      json = PreviewPlan.app_env("ecto://u:p@h:5432/d", '{"SECRET_KEY_BASE":"s"}')
      parsed = JSON.parse(json)
      assert_equal "ecto://u:p@h:5432/d", parsed["DATABASE_URL"]
      assert_equal "s", parsed["SECRET_KEY_BASE"]
    end

    def test_deployed_iids_matches_only_this_apps_previews
      names = ["holter-mr-5-preview", "holter-mr-12-preview", "shared-pg", "afinados-mr-1-preview"]
      assert_equal %w[5 12], PreviewPlan.deployed_iids(names, "holter", "-preview")
    end

    def test_stale_iids_is_deployed_minus_open
      assert_equal %w[5 12], PreviewPlan.stale_iids(%w[5 9 12], %w[9])
    end

    def deploy_vars(image: "registry/holter:abc", extra: '{"SECRET_KEY_BASE":"s"}')
      env = base_env.merge(
        "PREVIEW_MR_IID" => "5",
        "PREVIEW_APP_IMAGE" => image,
        "PREVIEW_APP_EXTRA_ENV" => extra
      )
      runner = FakeRunner.new
      Preview.new(env: env, io: StringIO.new, runner: runner).deploy
      runner.runs.fetch(0)
    end

    def test_deploy_invokes_the_playbook_with_present_state
      call = deploy_vars
      assert_equal ["ansible-playbook", "-i", "1.2.3.4,", "eiseron.provisioning.preview_app"], call[:cmd]
      vars = call[:env]
      assert_equal "present", vars["PREVIEW_APP_STATE"]
      assert_equal "holter-mr-5-preview", vars["PREVIEW_APP_NAME"]
      assert_equal "holter-mr-5-preview.holter.dev", vars["PREVIEW_APP_HOST"]
      assert_equal "holter_mr5", vars["PREVIEW_APP_DB_NAME"]
      assert_equal "registry/holter:abc", vars["PREVIEW_APP_IMAGE"]
    end

    def test_deploy_assembles_database_url_and_merges_extra_env
      app_env = JSON.parse(deploy_vars[:env]["PREVIEW_APP_ENV"])
      assert_equal "ecto://holter:p%40ss%2Fword@shared-pg:5432/holter_mr5", app_env["DATABASE_URL"]
      assert_equal "s", app_env["SECRET_KEY_BASE"]
    end

    def test_stop_runs_the_playbook_with_absent_state
      env = base_env.merge("PREVIEW_MR_IID" => "5")
      runner = FakeRunner.new
      Preview.new(env: env, io: StringIO.new, runner: runner).stop

      vars = runner.runs.fetch(0)[:env]
      assert_equal "absent", vars["PREVIEW_APP_STATE"]
      assert_equal "holter-mr-5-preview", vars["PREVIEW_APP_NAME"]
      assert_equal "holter_mr5", vars["PREVIEW_APP_DB_NAME"]
    end

    DEPLOYED_PREVIEWS = "holter-mr-5-preview\nholter-mr-9-preview\nshared-pg\nholter-mr-12-preview\n"

    def test_sweep_tears_down_only_previews_whose_mr_is_closed
      env = base_env.merge("EISERON_PREVIEW_SCAN_PROJECT" => "g/holter/holter")
      runner = FakeRunner.new(capture_output: DEPLOYED_PREVIEWS)
      preview = Preview.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new(%w[9]))
      preview.sweep

      torn_down = runner.runs.map { |run| run[:env]["PREVIEW_APP_NAME"] }
      assert_equal %w[holter-mr-12-preview holter-mr-5-preview], torn_down.sort
      assert(runner.runs.all? { |run| run[:env]["PREVIEW_APP_STATE"] == "absent" })
    end

    def test_deploy_raises_when_a_required_variable_is_missing
      env = base_env.merge("PREVIEW_MR_IID" => "5") # no PREVIEW_APP_IMAGE
      error = assert_raises(Error) { Preview.new(env: env, io: StringIO.new, runner: FakeRunner.new).deploy }
      assert_match(/PREVIEW_APP_IMAGE/, error.message)
    end
  end
end
