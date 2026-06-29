# frozen_string_literal: true

module EiseronAutomation
  module Preview
    class SshSession
      def initialize(env:, runner:)
        @env = env
        @runner = runner
      end

      def run(remote_cmd)
        @runner.run(@env.to_h, "ssh", *ssh_args, "#{ssh_user}@#{ssh_host}", remote_cmd)
      end

      def bash(script)
        @runner.run_stdin(script, @env.to_h, "ssh", *ssh_args, "#{ssh_user}@#{ssh_host}", "bash", "-s")
      end

      def capture(remote_cmd)
        @runner.capture("ssh", *ssh_args, "#{ssh_user}@#{ssh_host}", remote_cmd)
      end

      def prepare_key
        key = require_env("ANSIBLE_SSH_PRIVATE_KEY")
        File.chmod(0o600, key) if File.exist?(key)
        key
      end

      private

      def ssh_args
        ["-i", prepare_key,
         "-o", "StrictHostKeyChecking=accept-new",
         "-o", "BatchMode=yes"]
      end

      def ssh_user
        require_env("VPS_USER")
      end

      def ssh_host
        require_env("PREVIEW_HOST_IP")
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
