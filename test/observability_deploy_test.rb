# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ObservabilityDeployTest < Minitest::Test
    class FakeRunner
      attr_reader :calls

      def initialize(capture_result: "")
        @calls = []
        @capture_result = capture_result
      end

      def run(_env, *cmd)
        @calls << cmd
      end

      def capture(*cmd)
        @calls << cmd
        @capture_result
      end
    end

    def env(over = {})
      {
        "CI_COMMIT_SHORT_SHA" => "abc1234",
        "PROD_HOST" => "10.0.0.1",
        "OBSERVABILITY_HOST" => "observe.example.test",
        "OBSERVABILITY_OTLP_BASIC" => "dXNlcjpwYXNz"
      }.merge(over)
    end

    def deploy(runner, vars, http: ->(_url, _auth) { "HTTP 200 {}" })
      Observability::Deploy.new(env: vars, io: StringIO.new, runner: runner, http: http)
    end

    def kamal_calls(runner)
      runner.calls.select { |cmd| cmd.first == "kamal" }
    end

    def test_deploy_runs_kamal_deploy_then_reboots_all_accessories
      runner = FakeRunner.new
      deploy(runner, env).deploy
      assert_equal ["kamal", "deploy", "--skip-push", "--version=abc1234"], kamal_calls(runner).first
      assert_equal ["kamal", "accessory", "reboot", "all", "--version=abc1234"], kamal_calls(runner).last
    end

    def test_root_reset_is_skipped_when_flag_unset
      runner = FakeRunner.new(capture_result: "a1b2c3")
      deploy(runner, env).deploy
      refute(runner.calls.any? { |cmd| cmd.join(" ").include?("openobserve reset --component root") },
             "reset must not run without OBSERVABILITY_RESET_METADATA=1")
    end

    def test_root_reset_runs_over_ssh_when_flag_set
      runner = FakeRunner.new(capture_result: "a1b2c3\n")
      deploy(runner, env("OBSERVABILITY_RESET_METADATA" => "1")).deploy
      reset = runner.calls.find { |cmd| cmd.join(" ").include?("openobserve reset --component root") }
      refute_nil reset, "reset must run when the flag is set"
      assert_includes reset, "ssh"
      assert_includes reset, "deploy@10.0.0.1"
      assert_match(%r{docker exec a1b2c3 /openobserve reset --component root}, reset.join(" "))
    end

    def test_root_reset_raises_when_container_missing
      runner = FakeRunner.new(capture_result: "")
      error = assert_raises(Error) { deploy(runner, env("OBSERVABILITY_RESET_METADATA" => "1")).deploy }
      assert_match(/container not found/, error.message)
    end

    def test_root_reset_rejects_a_non_hex_container_id
      runner = FakeRunner.new(capture_result: "abc; rm -rf /")
      error = assert_raises(Error) { deploy(runner, env("OBSERVABILITY_RESET_METADATA" => "1")).deploy }
      assert_match(/unexpected container id/, error.message)
      refute(runner.calls.any? { |cmd| cmd.join(" ").include?("openobserve reset") },
             "reset must not run with a suspicious container id")
    end

    def test_verify_is_informational_and_does_not_fail_on_error_status
      io = StringIO.new
      http = ->(_url, _auth) { "HTTP 401 unauthorized" }
      d = Observability::Deploy.new(env: env, io: io, runner: FakeRunner.new, http: http)
      d.deploy
      assert_includes io.string, "HTTP 401 unauthorized"
    end

    def test_verify_calls_the_streams_api_with_basic_auth
      seen = {}
      http = lambda do |url, auth|
        seen[:url] = url
        seen[:auth] = auth
        "HTTP 200 {}"
      end
      deploy(FakeRunner.new, env, http: http).deploy
      assert_equal "https://observe.example.test/api/default/streams", seen[:url]
      assert_equal "Basic dXNlcjpwYXNz", seen[:auth]
    end

    def test_verify_is_skipped_without_auth
      called = false
      http = lambda do |_url, _auth|
        called = true
        ""
      end
      deploy(FakeRunner.new, env("OBSERVABILITY_OTLP_BASIC" => ""), http: http).deploy
      refute called, "verify must be skipped when the auth is absent"
    end
  end
end
