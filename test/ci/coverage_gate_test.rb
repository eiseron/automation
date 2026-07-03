# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class CoverageGateTest < Minitest::Test
      class FakeClient
        attr_reader :calls

        def initialize(pipeline_jobs_map: {}, pipelines_by_ref: {})
          @pipeline_jobs_map = pipeline_jobs_map
          @pipelines_by_ref = pipelines_by_ref
          @calls = []
        end

        def pipeline_jobs(pipeline_id)
          @calls << [:pipeline_jobs, pipeline_id]
          @pipeline_jobs_map.fetch(pipeline_id, [])
        end

        def last_successful_pipeline(ref)
          @calls << [:last_successful_pipeline, ref]
          @pipelines_by_ref[ref]
        end
      end

      def env(over = {})
        {
          "CI_API_V4_URL" => "https://gitlab.com/api/v4",
          "CI_PROJECT_ID" => "42",
          "CI_JOB_TOKEN" => "job-secret",
          "CI_PIPELINE_ID" => "100",
          "CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => "main"
        }.merge(over)
      end

      def jobs(coverage)
        [{ "name" => "test", "coverage" => coverage }]
      end

      def run_gate(env_vars: env, client: nil, args: [])
        io = StringIO.new
        CoverageGate.new(env: env_vars, io: io, err: StringIO.new, args: args, client: client).run
        io.string
      end

      def test_prints_ok_when_coverage_maintained
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(85.5), "200" => jobs(80.0) },
          pipelines_by_ref: { "main" => { "id" => 200 } }
        )
        output = run_gate(client: client)
        assert_includes output, "Coverage: current=85.5% target(main)=80.0%"
        assert_includes output, "OK: coverage maintained"
      end

      def test_raises_when_coverage_drops
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(70.0), "200" => jobs(80.0) },
          pipelines_by_ref: { "main" => { "id" => 200 } }
        )
        error = assert_raises(Error) { run_gate(client: client) }
        assert_match(/coverage dropped.*70.0%.*80.0%/, error.message)
      end

      def test_skips_when_no_coverage_on_current_pipeline
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(nil) },
          pipelines_by_ref: { "main" => { "id" => 200 } }
        )
        output = run_gate(client: client)
        assert_includes output, "No coverage data for current pipeline"
      end

      def test_skips_when_no_successful_pipeline_on_target_branch
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(85.0) },
          pipelines_by_ref: {}
        )
        output = run_gate(client: client)
        assert_includes output, "No successful pipeline on target branch (main)"
      end

      def test_skips_when_no_coverage_on_target_pipeline
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(85.0), "200" => jobs(nil) },
          pipelines_by_ref: { "main" => { "id" => 200 } }
        )
        output = run_gate(client: client)
        assert_includes output, "No coverage data on target branch (main)"
      end

      def test_uses_custom_test_job_name_from_args
        client = FakeClient.new(
          pipeline_jobs_map: {
            "100" => [{ "name" => "rspec", "coverage" => 90.0 }],
            "200" => [{ "name" => "rspec", "coverage" => 88.0 }]
          },
          pipelines_by_ref: { "main" => { "id" => 200 } }
        )
        output = run_gate(client: client, args: ["--test-job", "rspec"])
        assert_includes output, "Coverage: current=90.0%"
      end

      def test_queries_target_branch_from_env
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(80.0), "300" => jobs(79.0) },
          pipelines_by_ref: { "develop" => { "id" => 300 } }
        )
        run_gate(env_vars: env("CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => "develop"), client: client)
        assert_includes client.calls, [:last_successful_pipeline, "develop"]
      end

      def test_missing_pipeline_id_raises
        error = assert_raises(Error) { run_gate(env_vars: env.except("CI_PIPELINE_ID")) }
        assert_match(/CI_PIPELINE_ID is empty/, error.message)
      end

      def test_missing_target_branch_raises
        error = assert_raises(Error) do
          client = FakeClient.new(
            pipeline_jobs_map: { "100" => jobs(85.0) },
            pipelines_by_ref: {}
          )
          run_gate(env_vars: env.except("CI_MERGE_REQUEST_TARGET_BRANCH_NAME"), client: client)
        end
        assert_match(/CI_MERGE_REQUEST_TARGET_BRANCH_NAME is empty/, error.message)
      end

      def test_missing_job_token_raises_when_no_client_injected
        error = assert_raises(Error) do
          CoverageGate.new(
            env: env.except("CI_JOB_TOKEN"),
            io: StringIO.new,
            err: StringIO.new
          ).run
        end
        assert_match(/CI_JOB_TOKEN is empty/, error.message)
      end

      def test_test_job_flag_without_value_raises
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(85.0) },
          pipelines_by_ref: {}
        )
        error = assert_raises(Error) { run_gate(client: client, args: ["--test-job"]) }
        assert_match(/--test-job requires a value/, error.message)
      end

      def test_test_job_flag_followed_by_another_flag_raises
        client = FakeClient.new(
          pipeline_jobs_map: { "100" => jobs(85.0) },
          pipelines_by_ref: {}
        )
        error = assert_raises(Error) { run_gate(client: client, args: ["--test-job", "--other"]) }
        assert_match(/--test-job requires a value/, error.message)
      end
    end
  end
end
