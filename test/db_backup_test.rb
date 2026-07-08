# frozen_string_literal: true

require "test_helper"
require "aws-sdk-s3"

module Aws
  module S3
    module Errors
      class ObjectLockedByBucketPolicy < StandardError; end unless const_defined?(:ObjectLockedByBucketPolicy)
    end
  end
end

module EiseronAutomation
  class DbBackupTest < Minitest::Test
    class FakeStore
      attr_reader :uploaded, :deleted, :texts_written

      def initialize(keys = [], history_text: nil, locked_keys: [])
        @keys = keys
        @uploaded = []
        @deleted = []
        @history_text = history_text
        @texts_written = []
        @locked_keys = locked_keys
      end

      def list(_bucket, _prefix)
        @keys
      end

      def upload(_bucket, key, src)
        @uploaded << { key: key, body: File.read(src) }
      end

      def delete(_bucket, key)
        raise Aws::S3::Errors::ObjectLockedByBucketPolicy, "locked" if @locked_keys.include?(key)

        @deleted << key
      end

      def read_text(_bucket, _key)
        @history_text
      end

      def write_text(_bucket, key, text)
        @texts_written << { key: key, text: text }
        @history_text = text
      end
    end

    class FakeRunner
      attr_reader :pipelines

      def initialize
        @pipelines = []
      end

      def pipeline(env, *commands)
        commands.each do |cmd|
          out = cmd[cmd.index("--output") + 1] if cmd.include?("--output")
          File.write(out, "cipher") if out
        end
        @pipelines << { stages: commands, env: env }
      end

      def stage(prog)
        @pipelines.flat_map { |pipe| pipe[:stages] }.find { |cmd| cmd.first == prog }
      end
    end

    def setup
      @dir = Dir.mktmpdir
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def env(over = {})
      {
        "PROD_BACKUP_BUCKET" => "afinados-backups",
        "PROD_BACKUP_NAME" => "afinados",
        "PROD_BACKUP_AGE_RECIPIENTS" => "age1dr, age1drill",
        "PROD_BACKUP_DIR" => @dir,
        "PGPASSWORD" => "s3cr3t"
      }.merge(over)
    end

    def backup(store, vars, now: Time.utc(2026, 6, 13, 3, 0, 0))
      DB::Backup.new(env: vars, io: StringIO.new, runner: (@runner = FakeRunner.new), store: store, now: now)
    end

    def test_dumps_the_product_database_over_the_network_with_the_password
      backup(FakeStore.new, env).run
      dump = @runner.stage("pg_dump")
      assert_includes dump, "-d"
      assert_includes dump, "afinados_prod"
      assert_includes dump, "afinados-db"
      assert_equal "s3cr3t", @runner.pipelines.fetch(0)[:env]["PGPASSWORD"]
    end

    def test_pipes_the_dump_straight_into_age_with_no_plaintext_file
      backup(FakeStore.new, env).run
      stages = @runner.pipelines.fetch(0)[:stages].map(&:first)
      assert_equal %w[pg_dump age], stages
      assert_empty Dir.glob(File.join(@dir, "*.sql"))
    end

    def test_encrypts_to_every_age_recipient
      backup(FakeStore.new, env).run
      cmd = @runner.stage("age")
      recipients = cmd.each_index.select { |i| cmd[i] == "-r" }.map { |i| cmd[i + 1] }
      assert_equal %w[age1dr age1drill], recipients
    end

    def test_uploads_a_timestamped_object_under_the_product_prefix
      store = FakeStore.new
      backup(store, env).run
      assert_equal "afinados/2026-06-13T030000Z.sql.age", store.uploaded.fetch(0)[:key]
    end

    def test_removes_local_artifacts_after_upload
      backup(FakeStore.new, env).run
      assert_empty Dir.glob(File.join(@dir, "*.sql*"))
    end

    def test_prunes_remote_objects_older_than_the_retention_window
      old = "afinados/2026-05-01T030000Z.sql.age"
      recent = "afinados/2026-06-12T030000Z.sql.age"
      store = FakeStore.new([old, recent], history_text: "#{old}\n#{recent}\n")
      backup(store, env).run
      assert_includes store.deleted, old
      refute_includes store.deleted, recent
    end

    def test_honours_a_custom_retention_window
      old = "afinados/2026-06-10T030000Z.sql.age"
      store = FakeStore.new([old], history_text: "#{old}\n")
      backup(store, env("PROD_BACKUP_RETENTION_DAYS" => "2")).run
      assert_includes store.deleted, old
    end

    def test_requires_at_least_one_recipient
      error = assert_raises(Error) { backup(FakeStore.new, env("PROD_BACKUP_AGE_RECIPIENTS" => " , ")).run }
      assert_match(/no recipients/, error.message)
    end

    def test_requires_the_bucket
      assert_raises(Error) { backup(FakeStore.new, env.except("PROD_BACKUP_BUCKET")).run }
    end

    def test_rejects_an_unsafe_product_name
      vars = env("PROD_BACKUP_NAME" => "afinados;DROP")
      error = assert_raises(Error) { backup(FakeStore.new, vars).run }
      assert_match(/not a valid postgres identifier/, error.message)
    end

    def test_appends_new_key_to_history
      store = FakeStore.new(history_text: "afinados/2026-06-12T030000Z.sql.age\n")
      backup(store, env).run
      history_write = store.texts_written.find { |w| w[:key] == "afinados/history" }
      assert history_write
      keys = history_write[:text].lines.map { |line| line.strip.split("\t").first }
      assert_includes keys, "afinados/2026-06-12T030000Z.sql.age"
      assert_includes keys, "afinados/2026-06-13T030000Z.sql.age"
    end

    def test_creates_history_when_none_exists
      store = FakeStore.new
      backup(store, env).run
      history_write = store.texts_written.find { |w| w[:key] == "afinados/history" }
      assert history_write
      sha256 = Digest::SHA256.hexdigest("cipher")
      assert_equal "afinados/2026-06-13T030000Z.sql.age\t#{sha256}\n", history_write[:text]
    end

    def test_records_the_sha256_of_the_uploaded_object_in_history
      store = FakeStore.new
      backup(store, env).run
      history_write = store.texts_written.find { |w| w[:key] == "afinados/history" }
      key, sha256 = history_write[:text].lines.last.strip.split("\t")
      assert_equal "afinados/2026-06-13T030000Z.sql.age", key
      assert_equal Digest::SHA256.hexdigest("cipher"), sha256
    end

    def test_removes_pruned_keys_from_history
      old = "afinados/2026-05-01T030000Z.sql.age"
      recent = "afinados/2026-06-12T030000Z.sql.age"
      store = FakeStore.new([old, recent], history_text: "#{old}\n#{recent}\n")
      backup(store, env).run
      last_write = store.texts_written.last
      lines = last_write[:text].lines.map(&:strip)
      refute_includes lines, old
      assert_includes lines, recent
    end

    def test_skips_locked_expired_keys_and_completes_backup
      old = "afinados/2026-05-01T030000Z.sql.age"
      store = FakeStore.new([old], history_text: "#{old}\n", locked_keys: [old])
      io = StringIO.new
      DB::Backup.new(env: env, io: io, runner: FakeRunner.new, store: store, now: Time.utc(2026, 6, 13, 3, 0, 0)).run
      refute_includes store.deleted, old
      assert_match(/bucket policy prevents deletes/, io.string)
    end
  end
end
