# frozen_string_literal: true

require "tmpdir"

module EiseronAutomation
  module DB
    class Restore
      IDENTIFIER = /\A[a-z][a-z0-9_]{0,62}\z/

      VERIFY_SQL = <<~SQL
        DO $$
        BEGIN
          IF (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') = 0 THEN
            RAISE EXCEPTION 'restore produced no tables in the public schema';
          END IF;
        END $$;
      SQL

      def initialize(env: ENV, io: $stdout, runner: Runner.new, store: nil, backup: nil)
        @env = env
        @io = io
        @runner = runner
        @store = store
        @backup = backup
      end

      def run
        guard_confirmation
        @io.puts "Snapshotting #{database} before restoring #{backup_object} in place"
        backup.run
        Dir.mktmpdir { |dir| restore(dir) }
        @io.puts "Restore complete: #{database} restored from #{backup_object} and verified."
      end

      private

      def guard_confirmation
        return if confirmation == database

        raise Error, "refusing in-place restore: set PROD_RESTORE_CONFIRM=#{database} to overwrite it"
      end

      def drill_key
        @drill_key ||= begin
          key = $stdin.read.to_s.strip
          raise Error, "no drill key on stdin (pipe the age private key)" if key.empty?

          key
        end
      end

      def restore(dir)
        enc = File.join(dir, "backup.sql.age")
        dump = File.join(dir, "backup.sql")
        store.download(bucket, backup_object, enc)
        decrypt(enc, dump)
        reset_schema
        @runner.run(@env.to_h, *psql, "-f", dump)
        @runner.run_stdin(VERIFY_SQL, @env.to_h, *psql, "-f", "-")
      end

      def decrypt(enc, dump)
        @runner.run_stdin(drill_key, @env.to_h, "age", "--decrypt", "--identity", "-", "--output", dump, enc)
      end

      def reset_schema = @runner.run_stdin(reset_sql, @env.to_h, *psql, "-f", "-")

      def reset_sql
        <<~SQL
          DROP SCHEMA IF EXISTS public CASCADE;
          CREATE SCHEMA public AUTHORIZATION "#{pg_user}";
          GRANT USAGE ON SCHEMA public TO public;
        SQL
      end

      def backup_object
        @backup_object ||= resolve_backup_object
      end

      def resolve_backup_object
        return latest_object if requested_object == "latest"
        unless requested_object.start_with?("#{prefix}/") && requested_object.end_with?(".sql.age")
          raise Error, "PROD_RESTORE_KEY '#{requested_object}' is not a #{prefix}/ backup object"
        end

        requested_object
      end

      def latest_object
        objects = store.list(bucket, prefix).select { |object| object.end_with?(".sql.age") }
        raise Error, "no backups under s3://#{bucket}/#{prefix}/" if objects.empty?

        objects.max
      end

      def psql = ["psql", "-h", pg_host, "-U", pg_user, "-d", database, "-v", "ON_ERROR_STOP=1"]
      def pg_host = @env.fetch("PGHOST", "#{prefix}-db")
      def database = @env.fetch("PROD_BACKUP_DATABASE", "#{prefix}_prod")
      def bucket = require_env("PROD_BACKUP_BUCKET")
      def account_id = require_env("CLOUDFLARE_ACCOUNT_ID")
      def requested_object = require_env("PROD_RESTORE_KEY")
      def confirmation = @env.fetch("PROD_RESTORE_CONFIRM", "")
      def backup = @backup ||= Backup.new(env: @env, io: @io, runner: @runner, store: store)
      def store = @store ||= R2.new(account_id: account_id)
      def pg_user = identifier("PGUSER", prefix)
      def prefix = identifier("PROD_BACKUP_NAME", "app")

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
