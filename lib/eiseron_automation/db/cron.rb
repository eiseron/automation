# frozen_string_literal: true

module EiseronAutomation
  module DB
    class Cron
      FIELDS = 5
      HORIZON_SECONDS = 5 * 366 * 24 * 60 * 60

      def initialize(expression)
        @expression = expression.to_s.strip
        compile(split)
      end

      def next_after(time)
        next_run = Time.at(((time.to_i / 60) + 1) * 60, in: time.utc_offset)
        limit = next_run.to_i + HORIZON_SECONDS
        while next_run.to_i < limit
          return next_run if matches?(next_run)

          next_run += day_matches_calendar?(next_run) ? 60 : seconds_to_next_day(next_run)
        end
        raise Error, "BACKUP_CRON '#{@expression}' never occurs"
      end

      private

      def day_matches_calendar?(time)
        @months.include?(time.month) && day_matches?(time)
      end

      def seconds_to_next_day(time)
        midnight = Time.new(time.year, time.month, time.day, 0, 0, 0, time.utc_offset)
        (midnight + 86_400).to_i - time.to_i
      end

      def compile(fields)
        @minutes = expand(fields[0], 0, 59)
        @hours = expand(fields[1], 0, 23)
        @days = expand(fields[2], 1, 31)
        @months = expand(fields[3], 1, 12)
        @weekdays = expand(fields[4], 0, 7).to_set { |day| day == 7 ? 0 : day }
        @day_restricted = fields[2] != "*"
        @weekday_restricted = fields[4] != "*"
      end

      def matches?(time)
        @minutes.include?(time.min) && @hours.include?(time.hour) &&
          @months.include?(time.month) && day_matches?(time)
      end

      def day_matches?(time)
        day = @days.include?(time.day)
        weekday = @weekdays.include?(time.wday)
        return day || weekday if @day_restricted && @weekday_restricted

        day && weekday
      end

      def split
        fields = @expression.split
        raise Error, "BACKUP_CRON '#{@expression}' must have #{FIELDS} fields" unless fields.size == FIELDS

        fields
      end

      def expand(field, min, max)
        field.split(",").flat_map { |part| expand_part(part, min, max) }.to_set
      end

      def expand_part(part, min, max)
        range, step = part.split("/", 2)
        step = step.nil? ? 1 : positive(step)
        low, high = bounds(range, min, max)
        (low..high).step(step).to_a
      end

      def bounds(range, min, max)
        return [min, max] if range == "*"

        low, high = range.split("-", 2)
        low = integer(low)
        high = high.nil? ? low : integer(high)
        raise invalid unless low >= min && high <= max && low <= high

        [low, high]
      end

      def positive(value)
        step = integer(value)
        raise invalid unless step.positive?

        step
      end

      def integer(value)
        Integer(value)
      rescue ArgumentError, TypeError
        raise invalid
      end

      def invalid
        Error.new("BACKUP_CRON '#{@expression}' is not a valid cron expression")
      end
    end
  end
end
