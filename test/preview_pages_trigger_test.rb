# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class PreviewPagesTriggerTest < Minitest::Test
    class FakeClient
      attr_reader :calls

      def initialize
        @calls = []
      end

      def trigger_pipeline(**kwargs)
        @calls << kwargs
        { "web_url" => "https://gitlab.com/down/-/pipelines/7" }
      end
    end

    class FakeRunner
      attr_reader :commands

      def initialize
        @commands = []
      end

      def run(_env, *cmd)
        @commands << cmd
      end
    end

    def base_env
      {
        "PREVIEW_TRIGGER_ACTION" => "deploy",
        "CI_MERGE_REQUEST_IID" => "12",
        "CI_COMMIT_SHA" => "abc123def",
        "PREVIEW_DIST_DIR" => ".vitepress/dist",
        "PREVIEW_DEPLOYER_PROJECT" => "acme/app/app-ops",
        "PREVIEW_DEPLOYER_TRIGGER_TOKEN" => "trig-tok",
        "CI_JOB_TOKEN" => "job-tok",
        "CI_PROJECT_ID" => "555",
        "CI_API_V4_URL" => "https://gitlab.com/api/v4"
      }
    end

    def run_trigger(env)
      client = FakeClient.new
      runner = FakeRunner.new
      uploads = []
      uploader = ->(url, path, token) { uploads << [url, path, token] }
      PreviewPagesTrigger.new(env: env, io: StringIO.new, runner: runner, client: client, uploader: uploader).run
      [client, runner, uploads]
    end

    def test_deploy_seals_dist_and_uploads_before_triggering
      _client, runner, uploads = run_trigger(base_env)

      tar = runner.commands.find { |c| c.first == "tar" }
      assert_equal ["tar", "-czf", "preview-dist.tgz", "-C", ".vitepress/dist", "."], tar

      url, path, token = uploads.fetch(0)
      assert_equal "job-tok", token
      assert_equal "preview-dist.tgz", path
      assert_includes url, "/projects/555/packages/generic/site-preview/abc123def/preview-dist.tgz"
    end

    def test_deploy_passes_pages_kind_and_context_but_no_project
      client, = run_trigger(base_env)
      vars = client.calls.fetch(0)[:variables]

      assert_equal "deploy", vars["PREVIEW_ACTION"]
      assert_equal "pages", vars["PREVIEW_KIND"]
      assert_equal "12", vars["PREVIEW_MR_IID"]
      assert_equal "abc123def", vars["PREVIEW_SHA"]
      refute vars.key?("PREVIEW_PAGES_PROJECT"), "deploy target must be pinned on the deployer"
    end

    def test_stop_does_not_package
      _client, runner, uploads = run_trigger(base_env.merge("PREVIEW_TRIGGER_ACTION" => "stop"))

      assert_empty uploads, "stop must not upload an artifact"
      assert_nil runner.commands.find { |c| c.first == "tar" }, "stop must not build a tarball"
    end

    def test_rejects_unknown_action
      assert_raises(Error) { run_trigger(base_env.merge("PREVIEW_TRIGGER_ACTION" => "wipe")) }
    end
  end
end
