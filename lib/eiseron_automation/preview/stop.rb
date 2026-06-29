# frozen_string_literal: true

module EiseronAutomation
  module Preview
    class Stop
      def initialize(env: ENV, io: $stdout, runner: Runner.new, ssh: nil, registry: nil, teardown: nil)
        @env = env
        @io = io
        @runner = runner
        @ssh = ssh
        @registry = registry
        @teardown = teardown
      end

      def run
        ref = require_env("PREVIEW_REF")
        teardown.run(project: Names.project("mr", ref), ref: ref)
      end

      private

      def teardown
        @teardown ||= Teardown.new(env: @env, io: @io, ssh: ssh, registry: registry)
      end

      def ssh
        @ssh ||= SshSession.new(env: @env, runner: @runner)
      end

      def registry
        @registry ||= Registry.new(env: @env, io: @io)
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
