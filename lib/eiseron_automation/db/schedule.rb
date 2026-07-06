# frozen_string_literal: true

module EiseronAutomation
  module DB
    class Schedule
      SIGNALS = %w[TERM INT].freeze

      def initialize(env: ENV, io: $stdout, backup: nil, clock: Clock.new, trapper: Signal, telegram: nil)
        @env = env
        @io = io
        @backup = backup
        @clock = clock
        @trapper = trapper
        @telegram = telegram
        @heartbeat = Heartbeat.new(env: env, clock: clock)
        @stopping = false
      end

      def run
        cron = Cron.new(cron_expression)
        @io.puts "Backup scheduler started for '#{cron_expression}'."
        install_traps
        @heartbeat.touch
        until @stopping
          wait_until(cron.next_after(@clock.now))
          run_backup unless @stopping
        end
        @io.puts "Backup scheduler stopped."
      end

      def stop
        @stopping = true
      end

      private

      def install_traps
        SIGNALS.each { |signal| @trapper.trap(signal) { stop } }
      end

      def wait_until(target)
        while !@stopping && @clock.now < target
          @clock.sleep(@heartbeat.interval)
          @heartbeat.touch
        end
      end

      def run_backup
        failure = nil
        worker = Thread.new do
          backup.run
        rescue StandardError => e
          failure = e
        end
        @heartbeat.touch until worker.join(@heartbeat.interval)
        @heartbeat.touch
        raise failure if failure
      rescue StandardError => e
        @io.puts "Backup failed: #{e.message}"
        notify_failure(e)
      end

      def notify_failure(error)
        t = telegram
        return if t.nil?

        name = @env.fetch("PROD_BACKUP_NAME", "app")
        t.deliver(text: "Backup failed on #{name}: #{error.message}")
      rescue StandardError => e
        @io.puts "Telegram notification failed: #{e.message}"
      end

      def telegram
        return @telegram unless @telegram.nil?

        token = @env.fetch("TELEGRAM_BOT_TOKEN", "")
        chat  = @env.fetch("TELEGRAM_CHAT_ID", "")
        return nil if token.empty? || chat.empty?

        Notify::Telegram.new(env: @env, io: @io)
      end

      def backup
        @backup ||= Backup.new(env: @env, io: @io)
      end

      def cron_expression
        @cron_expression ||= begin
          value = @env.fetch("BACKUP_CRON", "").strip
          raise Error, "BACKUP_CRON is empty" if value.empty?

          value
        end
      end
    end
  end
end
