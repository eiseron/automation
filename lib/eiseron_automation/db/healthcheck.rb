# frozen_string_literal: true

module EiseronAutomation
  module DB
    class Healthcheck
      def initialize(env: ENV, io: $stdout, clock: Clock.new)
        @io = io
        @heartbeat = Heartbeat.new(env: env, clock: clock)
      end

      def run
        age = @heartbeat.age
        raise Error, "backup scheduler heartbeat is stale (#{age}s old)" unless @heartbeat.fresh?

        @io.puts "Backup scheduler healthy (heartbeat #{age}s old)."
      end
    end
  end
end
