# frozen_string_literal: true

require "English"

module EiseronAutomation
  module CI
    class CommandRunner
      def capture(*cmd)
        output = IO.popen(cmd, &:read)
        raise Error, "command failed: #{cmd.join(' ')}" unless $CHILD_STATUS.success?

        output
      end
    end
  end
end
