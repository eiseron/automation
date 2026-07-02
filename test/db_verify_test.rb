# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class DbVerifyTest < Minitest::Test
    class FakeStore
      attr_reader :head_checks

      def initialize(history_text, existing_keys: nil)
        @history_text = history_text
        @existing_keys = existing_keys
        @head_checks = []
      end

      def read_text(_bucket, _key)
        @history_text
      end

      def exists?(_bucket, key)
        @head_checks << key
        return @existing_keys.include?(key) if @existing_keys

        true
      end
    end

    def env(over = {})
      {
        "PROD_BACKUP_BUCKET" => "afinados-backups",
        "PROD_BACKUP_NAME" => "afinados",
        "CLOUDFLARE_ACCOUNT_ID" => "acct"
      }.merge(over)
    end

    def now
      Time.utc(2026, 6, 15, 11, 0, 0)
    end

    def history(*stamps)
      "#{stamps.map { |s| "afinados/#{s}Z.sql.age\tsha-#{s}" }.join("\n")}\n"
    end

    def verify(store, vars = env, at: now)
      DB::Verify.new(env: vars, io: (@io = StringIO.new), store: store, now: at)
    end

    def test_passes_when_the_latest_backup_is_within_the_threshold
      store = FakeStore.new(history("2026-06-15T040000", "2026-06-14T040000"))
      verify(store).run
    end

    def test_raises_when_the_latest_backup_is_older_than_the_threshold
      store = FakeStore.new(history("2026-06-13T040000"))
      error = assert_raises(Error) { verify(store).run }
      assert_match(/backup stale/, error.message)
      assert_match(/threshold 30h/, error.message)
    end

    def test_raises_when_no_history_file_exists
      error = assert_raises(Error) { verify(FakeStore.new(nil)).run }
      assert_match(/no history/, error.message)
    end

    def test_raises_when_history_has_no_backups
      error = assert_raises(Error) { verify(FakeStore.new("")).run }
      assert_match(/no backups/, error.message)
    end

    def test_picks_the_newest_object_when_choosing_freshness
      store = FakeStore.new(history("2026-06-10T040000", "2026-06-15T040000", "2026-06-12T040000"))
      verify(store).run
    end

    def test_ignores_non_backup_entries_in_history
      text = "afinados/9999-zzz-not-a-backup.txt\nafinados/2026-06-15T040000Z.sql.age\tsha-latest\n"
      store = FakeStore.new(text)
      verify(store).run
    end

    def test_honors_a_custom_threshold_from_the_environment
      store = FakeStore.new(history("2026-06-14T040000"))
      assert_raises(Error) { verify(store, env("PROD_BACKUP_STALE_HOURS" => "20")).run }
      verify(store, env("PROD_BACKUP_STALE_HOURS" => "48")).run
    end

    def test_accepts_history_lines_that_carry_a_sha256
      store = FakeStore.new("afinados/2026-06-15T040000Z.sql.age\tabc123\n")
      verify(store).run
      assert_equal ["afinados/2026-06-15T040000Z.sql.age"], store.head_checks
    end

    def test_raises_when_the_newest_object_has_an_unparseable_name
      text = "afinados/zzz-mangled.sql.age\n"
      error = assert_raises(Error) { verify(FakeStore.new(text)).run }
      assert_match(/does not match the expected/, error.message)
    end

    def test_reports_freshness_in_hours_on_success
      store = FakeStore.new(history("2026-06-15T040000"))
      verify(store).run
      assert_match(/Backup fresh.*7\.0h old.*threshold 30h/, @io.string)
    end

    def test_warns_about_missing_backups
      keys = ["afinados/2026-06-15T040000Z.sql.age"]
      store = FakeStore.new(
        history("2026-06-15T040000", "2026-06-14T040000"),
        existing_keys: keys
      )
      verify(store).run
      assert_match(/WARNING: missing backup.*2026-06-14/, @io.string)
    end

    def test_raises_when_latest_backup_object_is_missing
      store = FakeStore.new(
        history("2026-06-15T040000"),
        existing_keys: []
      )
      error = assert_raises(Error) { verify(store).run }
      assert_match(/latest backup missing/, error.message)
    end

    def test_warns_when_an_older_backup_has_no_integrity_hash
      text = "afinados/2026-06-14T040000Z.sql.age\n" \
             "afinados/2026-06-15T040000Z.sql.age\tsha-latest\n"
      verify(FakeStore.new(text)).run
      assert_match(/WARNING: backup without integrity hash.*2026-06-14/, @io.string)
    end

    def test_raises_when_the_latest_backup_has_no_integrity_hash
      text = "afinados/2026-06-14T040000Z.sql.age\tsha-old\n" \
             "afinados/2026-06-15T040000Z.sql.age\n"
      error = assert_raises(Error) { verify(FakeStore.new(text)).run }
      assert_match(/latest backup has no integrity hash/, error.message)
    end

    def test_checks_existence_of_all_history_entries
      store = FakeStore.new(history("2026-06-15T040000", "2026-06-14T040000"))
      verify(store).run
      assert_equal 2, store.head_checks.length
    end

    def test_parses_stamps_as_utc_regardless_of_local_timezone
      store = FakeStore.new(history("2026-06-15T040000"))
      original_tz = ENV.fetch("TZ", nil)
      ENV["TZ"] = "America/Sao_Paulo"
      begin
        verify(store).run
        assert_match(/7\.0h old/, @io.string)
      ensure
        ENV["TZ"] = original_tz
      end
    end
  end
end
