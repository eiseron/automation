# frozen_string_literal: true

require "fileutils"

module EiseronAutomation
  module DB
    class Backup
      IDENTIFIER = /\A[a-z][a-z0-9_]{0,62}\z/

      def initialize(env: ENV, io: $stdout, runner: Runner.new, store: nil, now: nil)
        @env = env
        @io = io
        @runner = runner
        @store = store
        @now = now
      end

      def run
        prune_local
        stamp = now.strftime("%Y-%m-%dT%H%M%SZ")
        object = "#{prefix}/#{stamp}.sql.age"
        dump_encrypt_upload(object)
        append_history(object)
        prune_remote
        @io.puts "Backup uploaded: s3://#{bucket}/#{object}"
      end

      private

      def dump_encrypt_upload(object)
        encrypted = File.join(backup_dir, File.basename(object))
        @runner.pipeline(
          @env.to_h,
          ["pg_dump", "-h", pg_host, "-U", pg_user, "-d", database],
          ["age", *recipient_args, "--output", encrypted]
        )
        store.upload(bucket, object, encrypted)
      ensure
        File.delete(encrypted) if encrypted && File.exist?(encrypted)
      end

      def recipient_args
        recipients.flat_map { |recipient| ["-r", recipient] }
      end

      def recipients
        list = require_env("PROD_BACKUP_AGE_RECIPIENTS").split(",").map(&:strip).reject(&:empty?)
        raise Error, "PROD_BACKUP_AGE_RECIPIENTS has no recipients" if list.empty?

        list
      end

      def append_history(object)
        history = read_history
        history << object
        store.write_text(bucket, history_key, "#{history.join("\n")}\n")
      end

      def prune_remote
        expired = expired_remote_keys
        expired.each { |key| store.delete(bucket, key) }
        return if expired.empty?

        store.write_text(bucket, history_key, "#{(read_history - expired).join("\n")}\n")
      end

      def expired_remote_keys
        store.list(bucket, prefix).select do |key|
          key.end_with?(".sql.age") && File.basename(key, ".sql.age") < cutoff
        end
      end

      def read_history
        text = store.read_text(bucket, history_key)
        return [] unless text

        text.lines.map(&:strip).reject(&:empty?)
      end

      def history_key = "#{prefix}/history"

      def prune_local
        Dir.glob(File.join(backup_dir, "*.sql*")).each do |path|
          File.delete(path) if File.mtime(path) < now - (retention_days * 86_400)
        end
      end

      def cutoff = (now - (retention_days * 86_400)).strftime("%Y-%m-%dT%H%M%SZ")

      def backup_dir
        dir = @env.fetch("PROD_BACKUP_DIR", "/backups")
        FileUtils.mkdir_p(dir)
        dir
      end

      def pg_host = @env.fetch("PGHOST", "#{prefix}-db")
      def pg_user = @env.fetch("PGUSER", prefix)
      def database = @env.fetch("PROD_BACKUP_DATABASE", "#{prefix}_prod")
      def retention_days = Integer(@env.fetch("PROD_BACKUP_RETENTION_DAYS", "15"))

      def prefix
        value = @env.fetch("PROD_BACKUP_NAME", "app")
        raise Error, "PROD_BACKUP_NAME '#{value}' is not a valid postgres identifier" unless value.match?(IDENTIFIER)

        value
      end

      def bucket = require_env("PROD_BACKUP_BUCKET")
      def now = @now ||= Time.now.utc
      def store = @store ||= R2.new(account_id: require_env("CLOUDFLARE_ACCOUNT_ID"))

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
