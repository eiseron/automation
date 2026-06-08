# frozen_string_literal: true

module EiseronAutomation
  module Prod
    class Runner
      def run(env, *cmd)
        system(env, *cmd) || raise(Error, "command failed: #{cmd.join(' ')}")
      end
    end
  end
end
