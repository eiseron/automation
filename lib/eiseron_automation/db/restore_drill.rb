# frozen_string_literal: true

require "digest"
require "tmpdir"

module EiseronAutomation
  module DB
    class RestoreDrill
      IDENTIFIER = /\A[a-z][a-z0-9_]{0,62}\z/

      DEFAULT_VERIFY_SQL = <<~SQL
        DO $$
        BEGIN
          IF (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') = 0 THEN
            RAISE EXCEPTION 'restore produced no tables in the public schema';
          END IF;
        END $$;
      SQL

      def initialize(env: ENV, io: $stdout, runner: Runner.new, store: nil)
        @env = env
        @io = io
        @runner = runner
        @store = store
      end

      def run
        entry = latest_entry
        @io.puts "Restoring latest backup #{entry.key} into the drill database"
        Dir.mktmpdir { |dir| restore(entry, dir) }
        @io.puts "Restore drill passed: #{entry.key} restored and verified."
      end

      private

      def restore(entry, dir)
        enc = File.join(dir, "backup.sql.age")
        dump = File.join(dir, "backup.sql")
        store.download(bucket, entry.key, enc)
        verify_integrity(entry, enc)
        decrypt(enc, dump, dir)
        load_dump(dump)
      end

      def verify_integrity(entry, enc)
        raise Error, "no integrity hash recorded for #{entry.key}" unless entry.sha256

        actual = Digest::SHA256.file(enc).hexdigest
        return if actual == entry.sha256

        raise Error, "integrity check failed for #{entry.key}: " \
                     "history sha256 #{entry.sha256}, downloaded #{actual}"
      end

      def decrypt(enc, dump, dir)
        identity = File.join(dir, "drill.key")
        File.write(identity, drill_key)
        File.chmod(0o600, identity)
        @runner.run(@env.to_h, "age", "--decrypt", "--identity", identity, "--output", dump, enc)
      end

      def load_dump(dump)
        @runner.run_stdin(prepare_sql, @env.to_h, *psql, "-f", "-")
        @runner.run(@env.to_h, *psql, "-f", dump)
        @runner.run_stdin(verify_sql, @env.to_h, *psql, "-f", "-")
      end

      def latest_entry
        text = store.read_text(bucket, history_key)
        raise Error, "no history at s3://#{bucket}/#{history_key} — has the backup ever run?" unless text

        parsed = History.parse(text)
        raise Error, "no backups in s3://#{bucket}/#{history_key}" if parsed.empty?

        parsed.latest
      end

      def history_key = "#{prefix}/history"

      def prepare_sql
        <<~SQL
          DO $$
          BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{owner}') THEN
              CREATE ROLE "#{owner}";
            END IF;
          END $$;
        SQL
      end

      def psql
        host = @env.fetch("PGHOST", "postgres")
        user = @env.fetch("PGUSER", "postgres")
        database = @env.fetch("PROD_DRILL_DATABASE", "drill")
        ["psql", "-h", host, "-U", user, "-d", database, "-v", "ON_ERROR_STOP=1"]
      end

      def verify_sql
        @env.fetch("PROD_DRILL_VERIFY_SQL", DEFAULT_VERIFY_SQL)
      end

      def owner
        value = prefix
        raise Error, "PROD_BACKUP_NAME '#{value}' is not a valid postgres identifier" unless value.match?(IDENTIFIER)

        value
      end

      def prefix
        @env.fetch("PROD_BACKUP_NAME", "app")
      end

      def bucket
        require_env("PROD_BACKUP_BUCKET")
      end

      def drill_key
        require_env("PROD_BACKUP_DRILL_KEY")
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
