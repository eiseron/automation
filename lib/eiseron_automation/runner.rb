# frozen_string_literal: true

require "English"
require "open3"

module EiseronAutomation
  class Runner
    def run(env, *cmd)
      system(env, *cmd) || raise(Error, "command failed: #{cmd.join(' ')}")
    end

    def run_stdin(input, env, *cmd)
      IO.popen(env, cmd, "w") { |io| io.write(input) }
      raise(Error, "command failed: #{cmd.join(' ')}") unless $CHILD_STATUS.success?
    end

    def pipeline(env, *commands)
      statuses = Open3.pipeline(*commands.map { |cmd| [env, *cmd] })
      commands.zip(statuses).each do |cmd, status|
        raise(Error, "command failed: #{cmd.join(' ')}") unless status.success?
      end
    end
  end
end
