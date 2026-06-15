# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class DbRestoreTest < Minitest::Test
    class FakeStore
      attr_reader :downloaded

      def initialize(keys)
        @keys = keys
        @downloaded = []
      end

      def list(_bucket, prefix)
        @keys.map { |key| "#{prefix}/#{key}" }
      end

      def download(_bucket, key, dest)
        @downloaded << key
        File.write(dest, "ciphertext")
      end
    end

    class FakeRunner
      attr_reader :calls

      def initialize
        @calls = []
      end

      def run(_env, *cmd)
        identity = cmd[cmd.index("--identity") + 1] if cmd.include?("--identity")
        @calls << { cmd: cmd, identity: identity && File.read(identity) }
      end

      def run_stdin(input, _env, *cmd)
        @calls << { cmd: cmd, sql: input }
      end
    end

    class FakeBackup
      attr_reader :ran

      def initialize
        @ran = false
      end

      def run
        @ran = true
      end
    end

    def env(over = {})
      {
        "PROD_BACKUP_BUCKET" => "afinados-backups",
        "PROD_BACKUP_NAME" => "afinados",
        "CLOUDFLARE_ACCOUNT_ID" => "acct",
        "PGHOST" => "platform-db",
        "PGUSER" => "afinados",
        "PROD_RESTORE_KEY" => "latest",
        "PROD_RESTORE_CONFIRM" => "afinados_prod"
      }.merge(over)
    end

    def perform(store, vars, identity: "AGE-SECRET-KEY-1DRILL\n")
      @runner = FakeRunner.new
      @backup = FakeBackup.new
      restore = DB::Restore.new(env: vars, io: StringIO.new, runner: @runner, store: store, backup: @backup)
      old = $stdin
      $stdin = StringIO.new(identity)
      begin
        restore.run
      ensure
        $stdin = old
      end
    end

    def keys
      ["2026-06-10T0200Z.sql.age", "2026-06-13T0200Z.sql.age", "2026-06-11T0200Z.sql.age"]
    end

    def sql_texts
      @runner.calls.select { |c| c[:sql] }.map { |c| c[:sql] }
    end

    def loaded_dump?
      @runner.calls.any? { |c| c[:cmd].include?("-f") && c[:cmd].last.end_with?("backup.sql") }
    end

    def test_refuses_when_confirmation_does_not_match_the_database
      error = assert_raises(Error) { perform(FakeStore.new(keys), env("PROD_RESTORE_CONFIRM" => "wrong")) }
      assert_match(/PROD_RESTORE_CONFIRM=afinados_prod/, error.message)
      assert_empty @runner.calls
      refute @backup.ran
    end

    def test_snapshots_the_database_before_overwriting_it
      perform(FakeStore.new(keys), env)
      assert @backup.ran, "must take a pre-restore backup before resetting the schema"
    end

    def test_resets_the_public_schema_before_loading
      perform(FakeStore.new(keys), env)
      assert(sql_texts.any? { |s| s.include?("DROP SCHEMA IF EXISTS public CASCADE") })
    end

    def test_loads_the_decrypted_dump
      perform(FakeStore.new(keys), env)
      assert loaded_dump?
    end

    def test_verifies_tables_after_load
      perform(FakeStore.new(keys), env)
      assert(sql_texts.any? { |s| s.include?("restore produced no tables") })
    end

    def test_decrypts_with_the_identity_piped_over_stdin_not_a_file
      perform(FakeStore.new(keys), env)
      age = @runner.calls.find { |c| c[:cmd].include?("age") }
      assert_equal "AGE-SECRET-KEY-1DRILL", age[:sql]
      assert_equal "-", age[:cmd][age[:cmd].index("--identity") + 1]
    end

    def test_latest_resolves_to_the_lexicographically_highest_object
      store = FakeStore.new(keys)
      perform(store, env)
      assert_equal "afinados/2026-06-13T0200Z.sql.age", store.downloaded.fetch(0)
    end

    def test_an_explicit_key_is_restored_verbatim
      store = FakeStore.new(keys)
      perform(store, env("PROD_RESTORE_KEY" => "afinados/2026-06-11T0200Z.sql.age"))
      assert_equal "afinados/2026-06-11T0200Z.sql.age", store.downloaded.fetch(0)
    end

    def test_rejects_a_key_outside_the_product_prefix
      bad = env("PROD_RESTORE_KEY" => "holter/2026-06-13T0200Z.sql.age")
      error = assert_raises(Error) { perform(FakeStore.new(keys), bad) }
      assert_match(%r{not a afinados/ backup object}, error.message)
    end

    def test_requires_an_identity_on_stdin
      error = assert_raises(Error) { perform(FakeStore.new(keys), env, identity: "  \n") }
      assert_match(/no drill key on stdin/, error.message)
    end
  end
end
