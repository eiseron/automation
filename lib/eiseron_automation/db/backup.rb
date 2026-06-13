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

      def prune_remote
        store.list(bucket, prefix).select { |key| key.end_with?(".sql.age") }.each do |key|
          store.delete(bucket, key) if File.basename(key, ".sql.age") < cutoff
        end
      end

      def prune_local
        Dir.glob(File.join(backup_dir, "*.sql*")).each do |path|
          File.delete(path) if File.mtime(path) < now - (retention_days * 86_400)
        end
      end

      def cutoff
        (now - (retention_days * 86_400)).strftime("%Y-%m-%dT%H%M%SZ")
      end

      def backup_dir
        dir = @env.fetch("PROD_BACKUP_DIR", "/backups")
        FileUtils.mkdir_p(dir)
        dir
      end

      def pg_host
        @env.fetch("PGHOST", "#{prefix}-db")
      end

      def pg_user
        @env.fetch("PGUSER", prefix)
      end

      def database
        @env.fetch("PROD_BACKUP_DATABASE", "#{prefix}_prod")
      end

      def retention_days
        Integer(@env.fetch("PROD_BACKUP_RETENTION_DAYS", "15"))
      end

      def prefix
        value = @env.fetch("PROD_BACKUP_NAME", "app")
        raise Error, "PROD_BACKUP_NAME '#{value}' is not a valid postgres identifier" unless value.match?(IDENTIFIER)

        value
      end

      def bucket
        require_env("PROD_BACKUP_BUCKET")
      end

      def now
        @now ||= Time.now.utc
      end

      def store
        @store ||= R2.new(account_id: require_env("CLOUDFLARE_ACCOUNT_ID"))
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
