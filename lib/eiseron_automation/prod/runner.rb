# frozen_string_literal: true

require "English"

module EiseronAutomation
  module Prod
    class Runner
      def run(env, *cmd)
        system(env, *cmd) || raise(Error, "command failed: #{cmd.join(' ')}")
      end

      def run_stdin(input, env, *cmd)
        IO.popen(env, cmd, "w") { |io| io.write(input) }
        raise(Error, "command failed: #{cmd.join(' ')}") unless $CHILD_STATUS.success?
      end
    end
  end
end
