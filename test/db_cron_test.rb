# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module DB
    class CronTest < Minitest::Test
      def next_after(expression, from)
        Cron.new(expression).next_after(from)
      end

      def test_advances_to_the_next_whole_minute
        assert_equal Time.utc(2026, 6, 14, 0, 1, 0),
                     next_after("* * * * *", Time.utc(2026, 6, 14, 0, 0, 30))
      end

      def test_finds_todays_daily_run
        assert_equal Time.utc(2026, 6, 14, 4, 0, 0),
                     next_after("0 4 * * *", Time.utc(2026, 6, 14, 0, 0, 0))
      end

      def test_rolls_to_tomorrow_once_todays_run_has_passed
        assert_equal Time.utc(2026, 6, 15, 4, 0, 0),
                     next_after("0 4 * * *", Time.utc(2026, 6, 14, 5, 0, 0))
      end

      def test_honours_step_fields
        assert_equal Time.utc(2026, 6, 14, 0, 15, 0),
                     next_after("*/15 * * * *", Time.utc(2026, 6, 14, 0, 1, 0))
      end

      def test_matches_a_day_of_week
        assert_equal Time.utc(2026, 6, 21, 4, 0, 0),
                     next_after("0 4 * * 0", Time.utc(2026, 6, 15, 0, 0, 0))
      end

      def test_treats_seven_as_sunday
        assert_equal Time.utc(2026, 6, 21, 4, 0, 0),
                     next_after("0 4 * * 7", Time.utc(2026, 6, 15, 0, 0, 0))
      end

      def test_ors_day_of_month_and_day_of_week_when_both_are_restricted
        assert_equal Time.utc(2026, 6, 21, 0, 0, 0),
                     next_after("0 0 1 * 0", Time.utc(2026, 6, 15, 0, 0, 0))
      end

      def test_finds_a_sparse_yearly_occurrence_without_scanning_every_minute
        assert_equal Time.utc(2028, 2, 29, 0, 0, 0),
                     next_after("0 0 29 2 *", Time.utc(2026, 6, 14, 0, 0, 0))
      end

      def test_rejects_an_expression_without_five_fields
        error = assert_raises(Error) { Cron.new("0 4 * *") }
        assert_match(/must have 5 fields/, error.message)
      end

      def test_rejects_out_of_range_values
        error = assert_raises(Error) { Cron.new("0 99 * * *") }
        assert_match(/not a valid cron expression/, error.message)
      end

      def test_rejects_non_numeric_fields
        assert_raises(Error) { Cron.new("0 4 * * mon") }
      end
    end
  end
end
