# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module DB
    class HeartbeatTest < Minitest::Test
      class FakeClock
        attr_accessor :time

        def initialize(time) = @time = time
        def now = @time
      end

      def setup
        @dir = Dir.mktmpdir
        @file = File.join(@dir, "hb")
        @clock = FakeClock.new(Time.utc(2026, 6, 14, 0, 0, 0))
      end

      def teardown = FileUtils.remove_entry(@dir)

      def heartbeat(over = {})
        Heartbeat.new(env: { "BACKUP_HEARTBEAT_FILE" => @file }.merge(over), clock: @clock)
      end

      def test_touch_writes_the_current_epoch
        heartbeat.touch
        assert_equal @clock.now.to_i, Integer(File.read(@file))
      end

      def test_age_reflects_time_elapsed_since_the_last_touch
        hb = heartbeat
        hb.touch
        @clock.time += 45
        assert_equal 45, hb.age
      end

      def test_a_missing_heartbeat_is_infinitely_old
        assert_equal Float::INFINITY, heartbeat.age
      end

      def test_freshness_is_bounded_by_the_max_age
        hb = heartbeat("BACKUP_HEARTBEAT_MAX_AGE" => "120")
        hb.touch
        @clock.time += 119
        assert hb.fresh?
        @clock.time += 2
        refute hb.fresh?
      end

      def test_interval_is_configurable
        assert_equal 15, heartbeat("BACKUP_HEARTBEAT_INTERVAL" => "15").interval
      end
    end
  end
end
