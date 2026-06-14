# frozen_string_literal: true

module EiseronAutomation
  module DB
    class Heartbeat
      DEFAULT_FILE = "/tmp/eiseron-backup.heartbeat"
      DEFAULT_INTERVAL = 30
      DEFAULT_MAX_AGE = 120

      attr_reader :interval

      def initialize(env: ENV, clock: Clock.new)
        @file = env.fetch("BACKUP_HEARTBEAT_FILE", DEFAULT_FILE)
        @interval = Integer(env.fetch("BACKUP_HEARTBEAT_INTERVAL", DEFAULT_INTERVAL))
        @max_age = Integer(env.fetch("BACKUP_HEARTBEAT_MAX_AGE", DEFAULT_MAX_AGE))
        @clock = clock
      end

      def touch
        File.write(@file, @clock.now.to_i.to_s)
      end

      def age
        @clock.now.to_i - Integer(File.read(@file).strip)
      rescue Errno::ENOENT, ArgumentError
        Float::INFINITY
      end

      def fresh?
        age <= @max_age
      end
    end
  end
end
