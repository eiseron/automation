# frozen_string_literal: true

module EiseronAutomation
  module DB
    class Clock
      def now = Time.now

      def sleep(seconds) = Kernel.sleep(seconds)
    end
  end
end
