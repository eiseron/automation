# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class DbVerifyTest < Minitest::Test
    class FakeStore
      def initialize(stamps)
        @stamps = stamps
      end

      def list(_bucket, prefix)
        @stamps.map { |stamp| "#{prefix}/#{stamp}Z.sql.age" }
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

    def verify(store, vars = env, at: now)
      DB::Verify.new(env: vars, io: StringIO.new, store: store, now: at)
    end

    def test_passes_when_the_latest_backup_is_within_the_threshold
      store = FakeStore.new(%w[2026-06-15T040000 2026-06-14T040000])
      verify(store).run
    end

    def test_raises_when_the_latest_backup_is_older_than_the_threshold
      store = FakeStore.new(%w[2026-06-13T040000])
      error = assert_raises(Error) { verify(store).run }
      assert_match(/backup stale/, error.message)
      assert_match(/threshold 30h/, error.message)
    end

    def test_raises_when_the_bucket_has_no_backups
      error = assert_raises(Error) { verify(FakeStore.new([])).run }
      assert_match(/no backups/, error.message)
    end

    def test_picks_the_newest_object_when_choosing_freshness
      store = FakeStore.new(%w[2026-06-10T040000 2026-06-15T040000 2026-06-12T040000])
      verify(store).run
    end

    def test_ignores_non_backup_objects
      store = FakeStore.new(%w[9999-zzz-not-a-backup 2026-06-15T040000])
      def store.list(_bucket, prefix)
        [
          "#{prefix}/9999-zzz-not-a-backup.txt",
          "#{prefix}/2026-06-15T040000Z.sql.age"
        ]
      end
      verify(store).run
    end

    def test_honors_a_custom_threshold_from_the_environment
      store = FakeStore.new(%w[2026-06-14T040000])
      assert_raises(Error) { verify(store, env("PROD_BACKUP_STALE_HOURS" => "20")).run }
      verify(store, env("PROD_BACKUP_STALE_HOURS" => "48")).run
    end

    def test_raises_when_the_newest_object_has_an_unparseable_name
      store = FakeStore.new([])
      def store.list(_bucket, prefix)
        ["#{prefix}/zzz-mangled.sql.age"]
      end
      error = assert_raises(Error) { verify(store).run }
      assert_match(/does not match the expected/, error.message)
    end

    def test_reports_freshness_in_hours_on_success
      io = StringIO.new
      store = FakeStore.new(%w[2026-06-15T040000])
      DB::Verify.new(env: env, io: io, store: store, now: now).run
      assert_match(/Backup fresh.*7\.0h old.*threshold 30h/, io.string)
    end

    def test_parses_stamps_as_utc_regardless_of_local_timezone
      store = FakeStore.new(%w[2026-06-15T040000])
      original_tz = ENV.fetch("TZ", nil)
      ENV["TZ"] = "America/Sao_Paulo"
      begin
        io = StringIO.new
        DB::Verify.new(env: env, io: io, store: store, now: now).run
        assert_match(/7\.0h old/, io.string)
      ensure
        ENV["TZ"] = original_tz
      end
    end
  end
end
