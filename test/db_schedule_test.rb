# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module DB
    class ScheduleTest < Minitest::Test
      class FakeClock
        attr_reader :now

        def initialize(start)
          @now = start
          @hook = nil
        end

        def sleep(seconds)
          @now += seconds
          @hook&.call
        end

        def on_sleep(&blk) = @hook = blk
      end

      class FakeTrapper
        def initialize = @traps = {}
        def trap(signal, &blk) = @traps[signal] = blk
        def fire(signal) = @traps.fetch(signal).call
      end

      class FakeBackup
        attr_reader :runs

        def initialize(error: nil)
          @runs = 0
          @error = error
        end

        def run
          @runs += 1
          raise @error if @error
        end
      end

      def setup
        @dir = Dir.mktmpdir
        @clock = FakeClock.new(Time.utc(2026, 6, 14, 0, 0, 0))
        @trapper = FakeTrapper.new
      end

      def teardown = FileUtils.remove_entry(@dir)

      def env(over = {})
        {
          "BACKUP_CRON" => "0 4 * * *",
          "BACKUP_HEARTBEAT_FILE" => File.join(@dir, "hb"),
          "BACKUP_HEARTBEAT_INTERVAL" => "100000"
        }.merge(over)
      end

      def schedule(over = {}, backup: FakeBackup.new)
        sched = Schedule.new(env: env(over), io: (@io = StringIO.new), backup: backup,
                             clock: @clock, trapper: @trapper)
        [sched, backup]
      end

      def stop_after_two_sleeps(sched)
        count = 0
        @clock.on_sleep do
          count += 1
          sched.stop if count >= 2
        end
      end

      def test_runs_the_backup_once_the_target_time_arrives
        sched, backup = schedule
        stop_after_two_sleeps(sched)
        sched.run
        assert_equal 1, backup.runs
      end

      def test_writes_a_heartbeat_so_docker_can_detect_liveness
        sched, = schedule
        stop_after_two_sleeps(sched)
        sched.run
        assert File.exist?(File.join(@dir, "hb"))
      end

      def test_stops_gracefully_on_a_termination_signal_without_starting_a_backup
        sched, backup = schedule
        @clock.on_sleep { @trapper.fire("TERM") }
        sched.run
        assert_equal 0, backup.runs
        assert_match(/stopped/, @io.string)
      end

      def test_touches_the_heartbeat_while_a_long_backup_is_running
        file = File.join(@dir, "hb")
        backup = Object.new
        backup.define_singleton_method(:run) do
          Kernel.sleep(0.01) until File.exist?(file)
        end
        sched = Schedule.new(
          env: { "BACKUP_HEARTBEAT_FILE" => file, "BACKUP_HEARTBEAT_INTERVAL" => "1" },
          io: StringIO.new, backup: backup
        )
        sched.send(:run_backup)
        assert File.exist?(file)
      end

      def test_keeps_running_after_a_backup_failure
        sched, backup = schedule(backup: FakeBackup.new(error: Errno::EACCES.new("/backups")))
        stop_after_two_sleeps(sched)
        sched.run
        assert_equal 1, backup.runs
        assert_match(/Backup failed/, @io.string)
      end

      def test_requires_a_cron_expression
        sched, backup = schedule({ "BACKUP_CRON" => "  " })
        error = assert_raises(Error) { sched.run }
        assert_match(/BACKUP_CRON is empty/, error.message)
        assert_equal 0, backup.runs
      end

      def test_rejects_an_invalid_cron_expression
        sched, = schedule({ "BACKUP_CRON" => "0 4 * *" })
        assert_raises(Error) { sched.run }
      end
    end
  end
end
