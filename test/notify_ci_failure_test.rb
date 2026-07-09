# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class NotifyCIFailureTest < Minitest::Test
    class FakeTelegram
      attr_reader :delivered

      def initialize
        @delivered = []
      end

      def deliver(text:)
        @delivered << text
      end
    end

    def env(over = {})
      {
        "CI_PROJECT_PATH" => "acme/app/app-ops",
        "CI_JOB_NAME" => "db-backup-verify",
        "CI_PIPELINE_URL" => "https://gitlab.com/acme/app/app-ops/-/pipelines/123",
        "CI_JOB_URL" => "https://gitlab.com/acme/app/app-ops/-/jobs/456",
        "CI_COMMIT_REF_NAME" => "production",
        "CI_COMMIT_SHORT_SHA" => "abc1234"
      }.merge(over)
    end

    def run_notify(vars = env)
      telegram = FakeTelegram.new
      Notify::CIFailure.new(env: vars, io: StringIO.new, err: StringIO.new, telegram: telegram).run
      telegram.delivered.fetch(0)
    end

    def test_message_includes_project_and_job_name_on_the_first_line
      message = run_notify
      assert_equal "FAIL: acme/app/app-ops · job db-backup-verify", message.lines.fetch(0).chomp
    end

    def test_message_includes_clickable_pipeline_and_job_urls
      message = run_notify
      assert_includes message, "Pipeline: https://gitlab.com/acme/app/app-ops/-/pipelines/123"
      assert_includes message, "Job: https://gitlab.com/acme/app/app-ops/-/jobs/456"
    end

    def test_message_includes_ref_and_short_sha
      message = run_notify
      assert_includes message, "Ref: production @ abc1234"
    end

    def test_optional_fields_omitted_when_empty
      message = run_notify(env("CI_JOB_URL" => "", "CI_COMMIT_REF_NAME" => "", "CI_COMMIT_SHORT_SHA" => ""))
      refute_includes message, "Job:"
      refute_includes message, "Ref:"
      assert_includes message, "Pipeline:"
    end

    def test_ref_alone_is_emitted_without_at_separator
      message = run_notify(env("CI_COMMIT_SHORT_SHA" => ""))
      assert_includes message, "Ref: production"
      refute_includes message, "production @"
    end

    def test_missing_project_path_raises
      error = assert_raises(Error) { run_notify(env.except("CI_PROJECT_PATH")) }
      assert_match(/CI_PROJECT_PATH is empty/, error.message)
    end

    def test_missing_job_name_raises
      error = assert_raises(Error) { run_notify(env.except("CI_JOB_NAME")) }
      assert_match(/CI_JOB_NAME is empty/, error.message)
    end
  end
end
