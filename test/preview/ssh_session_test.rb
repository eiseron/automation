# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class SshSessionTest < Minitest::Test
      class FakeRunner
        attr_reader :runs, :stdins, :captures

        def initialize
          @runs = []
          @stdins = []
          @captures = []
        end

        def run(env, *cmd) = @runs << { env: env, cmd: cmd }
        def run_stdin(input, env, *cmd) = @stdins << { input: input, env: env, cmd: cmd }
        def capture(*cmd) = @captures << cmd
      end

      def base_env(extra = {})
        Dir.mktmpdir do |dir|
          key = File.join(dir, "id_rsa")
          File.write(key, "")
          yield({
            "VPS_USER" => "deploy",
            "PREVIEW_HOST_IP" => "1.2.3.4",
            "ANSIBLE_SSH_PRIVATE_KEY" => key
          }.merge(extra))
        end
      end

      def test_run_builds_ssh_command_with_user_host_and_key
        runner = FakeRunner.new
        base_env do |env|
          SshSession.new(env: env, runner: runner).run("docker pull foo")
        end
        cmd = runner.runs.fetch(0).fetch(:cmd)
        assert_equal "ssh", cmd.first
        assert_equal "deploy@1.2.3.4", cmd[-2]
        assert_equal "docker pull foo", cmd[-1]
        assert_includes cmd, "StrictHostKeyChecking=accept-new"
        assert_includes cmd, "BatchMode=yes"
      end

      def test_bash_uses_run_stdin_with_bash_s
        runner = FakeRunner.new
        base_env do |env|
          SshSession.new(env: env, runner: runner).bash("echo hi")
        end
        call = runner.stdins.fetch(0)
        assert_equal "echo hi", call[:input]
        assert_equal %w[bash -s], call[:cmd].last(2)
      end

      def test_capture_forwards_to_runner_capture
        runner = FakeRunner.new
        base_env do |env|
          SshSession.new(env: env, runner: runner).capture("docker compose ls")
        end
        assert_includes runner.captures.fetch(0), "docker compose ls"
      end

      def test_requires_vps_user
        base_env do |env|
          err = assert_raises(Error) { SshSession.new(env: env.except("VPS_USER"), runner: FakeRunner.new).run("x") }
          assert_match(/VPS_USER/, err.message)
        end
      end

      def test_requires_preview_host_ip
        base_env do |env|
          stripped = env.except("PREVIEW_HOST_IP")
          err = assert_raises(Error) { SshSession.new(env: stripped, runner: FakeRunner.new).run("x") }
          assert_match(/PREVIEW_HOST_IP/, err.message)
        end
      end

      def test_requires_ssh_key
        base_env do |env|
          stripped = env.except("ANSIBLE_SSH_PRIVATE_KEY")
          err = assert_raises(Error) { SshSession.new(env: stripped, runner: FakeRunner.new).run("x") }
          assert_match(/ANSIBLE_SSH_PRIVATE_KEY/, err.message)
        end
      end
    end
  end
end
