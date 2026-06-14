# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module DB
    class HealthcheckTest < Minitest::Test
      class FakeClock
        def initialize(time) = @time = time
        def now = @time
      end

      def setup
        @dir = Dir.mktmpdir
        @file = File.join(@dir, "hb")
        @clock = FakeClock.new(Time.utc(2026, 6, 14, 0, 0, 0))
      end

      def teardown = FileUtils.remove_entry(@dir)

      def healthcheck
        Healthcheck.new(
          env: { "BACKUP_HEARTBEAT_FILE" => @file, "BACKUP_HEARTBEAT_MAX_AGE" => "120" },
          io: StringIO.new, clock: @clock
        )
      end

      def test_passes_when_the_heartbeat_is_fresh
        File.write(@file, (@clock.now.to_i - 10).to_s)
        healthcheck.run
      end

      def test_fails_when_the_heartbeat_is_stale
        File.write(@file, (@clock.now.to_i - 300).to_s)
        error = assert_raises(Error) { healthcheck.run }
        assert_match(/stale/, error.message)
      end

      def test_fails_when_there_is_no_heartbeat
        assert_raises(Error) { healthcheck.run }
      end
    end
  end
end
