# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class DbRestoreDrillTest < Minitest::Test
    class FakeStore
      attr_reader :downloaded

      def initialize(history_text)
        @history_text = history_text
        @downloaded = []
      end

      def read_text(_bucket, _key)
        @history_text
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

    def env(over = {})
      {
        "PROD_BACKUP_BUCKET" => "afinados-backups",
        "PROD_BACKUP_NAME" => "afinados",
        "PROD_BACKUP_DRILL_KEY" => "AGE-SECRET-KEY-1DRILL",
        "CLOUDFLARE_ACCOUNT_ID" => "acct"
      }.merge(over)
    end

    def history(*keys)
      "#{keys.map { |k| "afinados/#{k}" }.join("\n")}\n"
    end

    def drill(store, vars)
      DB::RestoreDrill.new(env: vars, io: StringIO.new, runner: (@runner = FakeRunner.new), store: store)
    end

    def test_picks_the_lexicographically_latest_backup_object
      store = FakeStore.new(history("2026-06-10T0200Z.sql.age", "2026-06-13T0200Z.sql.age", "2026-06-11T0200Z.sql.age"))
      drill(store, env).run
      assert_equal "afinados/2026-06-13T0200Z.sql.age", store.downloaded.fetch(0)
    end

    def test_ignores_non_backup_entries_in_history
      text = "afinados/2026-06-13T0200Z.sql.age\nafinados/9999-zzz-not-a-backup.txt\n"
      store = FakeStore.new(text)
      drill(store, env).run
      assert_equal "afinados/2026-06-13T0200Z.sql.age", store.downloaded.fetch(0)
    end

    def test_decrypts_with_the_drill_identity_before_restoring
      drill(FakeStore.new(history("2026-06-13T0200Z.sql.age")), env).run
      age = @runner.calls.find { |call| call[:cmd].first == "age" }
      assert_includes age[:cmd], "--decrypt"
      assert_equal "AGE-SECRET-KEY-1DRILL", age[:identity]
    end

    def test_precreates_the_owner_role_so_a_plain_dump_restores_cleanly
      drill(FakeStore.new(history("2026-06-13T0200Z.sql.age")), env).run
      prepare = @runner.calls.find { |call| call[:sql]&.include?("CREATE ROLE") }
      assert_match(/rolname = 'afinados'/, prepare[:sql])
      assert_match(/CREATE ROLE "afinados"/, prepare[:sql])
    end

    def test_restores_the_dump_and_then_verifies_with_on_error_stop
      drill(FakeStore.new(history("2026-06-13T0200Z.sql.age")), env).run
      psql_calls = @runner.calls.select { |call| call[:cmd].include?("psql") }
      assert(psql_calls.all? { |call| call[:cmd].include?("ON_ERROR_STOP=1") })
      verify = psql_calls.last
      assert_match(/information_schema\.tables/, verify[:sql])
      assert_match(/RAISE EXCEPTION/, verify[:sql])
    end

    def test_restore_runs_before_verify
      drill(FakeStore.new(history("2026-06-13T0200Z.sql.age")), env).run
      restore_index = @runner.calls.index { |c| c[:cmd].include?("-f") && c[:sql].nil? }
      verify_index = @runner.calls.index { |c| c[:sql]&.include?("information_schema") }
      assert_operator restore_index, :<, verify_index
    end

    def test_passes_integrity_when_recorded_hash_matches_the_download
      sha256 = Digest::SHA256.hexdigest("ciphertext")
      store = FakeStore.new("afinados/2026-06-13T0200Z.sql.age\t#{sha256}\n")
      drill(store, env).run
      assert_equal "afinados/2026-06-13T0200Z.sql.age", store.downloaded.fetch(0)
    end

    def test_fails_integrity_when_recorded_hash_mismatches_the_download
      store = FakeStore.new("afinados/2026-06-13T0200Z.sql.age\tdeadbeef\n")
      error = assert_raises(Error) { drill(store, env).run }
      assert_match(/integrity check failed/, error.message)
    end

    def test_does_not_decrypt_when_the_integrity_check_fails
      store = FakeStore.new("afinados/2026-06-13T0200Z.sql.age\tdeadbeef\n")
      assert_raises(Error) { drill(store, env).run }
      refute(@runner.calls.any? { |call| call[:cmd].first == "age" })
    end

    def test_skips_the_integrity_check_when_history_has_no_hash
      store = FakeStore.new(history("2026-06-13T0200Z.sql.age"))
      drill(store, env).run
      assert_equal "afinados/2026-06-13T0200Z.sql.age", store.downloaded.fetch(0)
    end

    def test_targets_the_drill_database_on_the_service_host
      vars = env("PROD_DRILL_DATABASE" => "drill", "PGHOST" => "postgres")
      drill(FakeStore.new(history("2026-06-13T0200Z.sql.age")), vars).run
      restore = @runner.calls.find { |call| call[:cmd].include?("psql") && call[:cmd].include?("-d") }
      assert_includes restore[:cmd], "drill"
      assert_includes restore[:cmd], "postgres"
    end

    def test_honours_a_custom_verify_query
      vars = env("PROD_DRILL_VERIFY_SQL" => "SELECT count(*) FROM setups;")
      drill(FakeStore.new(history("2026-06-13T0200Z.sql.age")), vars).run
      verify = @runner.calls.last
      assert_equal "SELECT count(*) FROM setups;", verify[:sql]
    end

    def test_raises_when_no_history_exists
      error = assert_raises(Error) { drill(FakeStore.new(nil), env).run }
      assert_match(/no history/, error.message)
    end

    def test_raises_when_history_has_no_backups
      error = assert_raises(Error) { drill(FakeStore.new(""), env).run }
      assert_match(/no backups/, error.message)
    end

    def test_requires_bucket_drill_key_and_account
      store = FakeStore.new(history("2026-06-13T0200Z.sql.age"))
      assert_raises(Error) { drill(store, env.except("PROD_BACKUP_BUCKET")).run }
      assert_raises(Error) { drill(store, env.except("PROD_BACKUP_DRILL_KEY")).run }
    end

    def test_rejects_an_unsafe_product_name
      vars = env("PROD_BACKUP_NAME" => "afinados;DROP")
      error = assert_raises(Error) { drill(FakeStore.new(history("x.sql.age")), vars).run }
      assert_match(/not a valid postgres identifier/, error.message)
    end
  end
end
