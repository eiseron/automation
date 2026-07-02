# frozen_string_literal: true

module EiseronAutomation
  module DB
    class Verify
      IDENTIFIER = /\A[a-z][a-z0-9_]{0,62}\z/
      STAMP = /(\d{4})-(\d{2})-(\d{2})T(\d{2})(\d{2})(\d{2})Z\.sql\.age\z/
      DEFAULT_STALE_HOURS = 30

      def initialize(env: ENV, io: $stdout, store: nil, now: nil)
        @env = env
        @io = io
        @store = store
        @now = now
      end

      def run
        check_prod_backup_bucket_presence
        raise stale_error if age_hours > stale_hours

        verify_existence
        verify_hash_coverage
        verify_lock_coverage

        @io.puts "Backup fresh: s3://#{bucket}/#{latest_object} (#{age_hours.round(1)}h old, threshold #{stale_hours}h)"
      end

      private

      def history
        @history ||= build_history
      end

      def build_history
        text = store.read_text(bucket, history_key)
        raise Error, "no history at s3://#{bucket}/#{history_key} — has the backup ever run?" unless text

        parsed = History.parse(text)
        raise Error, "no backups in s3://#{bucket}/#{history_key} — has the scheduler ever run?" if parsed.empty?

        parsed
      end

      def latest_object
        @latest_object ||= history.latest.key
      end

      def verify_existence
        missing = history.keys.reject { |key| store.exists?(bucket, key) }
        missing.each { |key| @io.puts "WARNING: missing backup #{key}" }
        raise Error, "latest backup missing: s3://#{bucket}/#{latest_object}" if missing.include?(latest_object)
      end

      def verify_hash_coverage
        unhashed = history.keys.reject { |key| history.sha256_for(key) }
        unhashed.each { |key| @io.puts "WARNING: backup without integrity hash #{key}" }
        return unless unhashed.include?(latest_object)

        raise Error, "latest backup has no integrity hash: s3://#{bucket}/#{latest_object}"
      end

      def verify_lock_coverage
        unless lock_prefix
          @io.puts "Lock coverage check skipped: PROD_BACKUP_LOCK_PREFIX not set " \
                   "(gem key-format drift only; lock presence is Terraform-managed)"
          return
        end

        uncovered = history.keys.reject { |key| key.start_with?(lock_prefix) }
        uncovered.each { |key| @io.puts "WARNING: backup outside the immutable lock prefix #{lock_prefix}: #{key}" }
        if uncovered.include?(latest_object)
          raise Error, "latest backup #{latest_object} is not under the immutable lock prefix " \
                       "#{lock_prefix} — the R2 Object Lock rule would not protect it"
        end

        @io.puts "Lock coverage OK: latest backup under #{lock_prefix} (key-format check; " \
                 "lock presence is Terraform-managed)"
      end

      def lock_prefix
        @lock_prefix ||= @env["PROD_BACKUP_LOCK_PREFIX"].to_s
        @lock_prefix.empty? ? nil : @lock_prefix
      end

      def history_key = "#{prefix}/history"

      def stamp
        @stamp ||= begin
          match = latest_object.match(STAMP)
          raise Error, stamp_format_error unless match

          Time.utc(*match.captures.map(&:to_i))
        end
      end

      def stamp_format_error
        "backup object '#{latest_object}' does not match the expected YYYY-MM-DDTHHMMSSZ.sql.age name"
      end

      def age_hours = @age_hours ||= (now - stamp) / 3600.0

      def stale_error
        Error.new("backup stale: s3://#{bucket}/#{latest_object} is " \
                  "#{age_hours.round(1)}h old, threshold #{stale_hours}h")
      end

      def stale_hours = @stale_hours ||= Integer(@env.fetch("PROD_BACKUP_STALE_HOURS", DEFAULT_STALE_HOURS.to_s))
      def bucket = check_prod_backup_bucket_presence
      def check_prod_backup_bucket_presence = require_env("PROD_BACKUP_BUCKET")
      def prefix = identifier("PROD_BACKUP_NAME", "app")
      def store = @store ||= R2.new(account_id: require_env("CLOUDFLARE_ACCOUNT_ID"))
      def now = @now ||= Time.now.utc

      def identifier(name, default)
        value = @env.fetch(name, default)
        raise Error, "#{name} '#{value}' is not a valid postgres identifier" unless value.match?(IDENTIFIER)

        value
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
