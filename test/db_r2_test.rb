# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "tempfile"
require "aws-sdk-s3"

module EiseronAutomation
  class DbR2Test < Minitest::Test
    Body = Struct.new(:content) do
      def read = content
    end

    Response = Struct.new(:body)
    Listing = Struct.new(:contents)

    class StubClient
      def initialize(error: nil, body: nil)
        @error = error
        @body = body
      end

      def get_object(**)
        raise @error if @error

        Response.new(Body.new(@body))
      end

      def list_objects_v2(**)
        raise @error if @error

        Listing.new([])
      end

      def head_object(**)
        raise @error if @error

        Response.new(nil)
      end

      def put_object(**)
        raise @error if @error

        Response.new(nil)
      end

      def delete_object(**)
        raise @error if @error

        Response.new(nil)
      end
    end

    def r2(error: nil, body: nil, env: { "AWS_ACCESS_KEY_ID" => "abcdef0123", "AWS_SECRET_ACCESS_KEY" => "shh" })
      DB::R2.new(account_id: "acct", client: StubClient.new(error: error, body: body), env: env)
    end

    def access_denied
      Aws::S3::Errors::AccessDenied.new(nil, "Access Denied")
    end

    def test_read_text_returns_the_object_body
      assert_equal "hello", r2(body: "hello").read_text("b", "k")
    end

    def test_read_text_returns_nil_when_the_key_is_missing
      assert_nil r2(error: Aws::S3::Errors::NoSuchKey.new(nil, "missing")).read_text("b", "k")
    end

    def test_exists_returns_false_when_the_object_is_absent
      refute r2(error: Aws::S3::Errors::NotFound.new(nil, "nope")).exists?("b", "k")
    end

    def test_read_text_diagnostic_names_the_get_object_operation_and_location
      error = assert_raises(Error) do
        r2(error: access_denied).read_text("afinados-backups", "afinados/history")
      end
      assert_match(%r{R2 GetObject s3://afinados-backups/afinados/history failed: AccessDenied}, error.message)
    end

    def test_list_diagnostic_names_the_list_objects_operation
      error = assert_raises(Error) { r2(error: access_denied).list("afinados-backups", "afinados") }
      assert_match(%r{R2 ListObjectsV2 s3://afinados-backups/afinados/}, error.message)
    end

    def test_exists_diagnostic_names_the_head_object_operation
      error = assert_raises(Error) { r2(error: access_denied).exists?("afinados-backups", "afinados/history") }
      assert_match(%r{R2 HeadObject s3://afinados-backups/afinados/history}, error.message)
    end

    def test_download_diagnostic_names_the_get_object_operation
      Dir.mktmpdir do |dir|
        error = assert_raises(Error) do
          r2(error: access_denied).download("afinados-backups", "afinados/x.sql.age", File.join(dir, "out"))
        end
        assert_match(%r{R2 GetObject s3://afinados-backups/afinados/x.sql.age}, error.message)
      end
    end

    def test_upload_diagnostic_names_the_put_object_operation
      Tempfile.create("backup") do |file|
        error = assert_raises(Error) do
          r2(error: access_denied).upload("afinados-backups", "afinados/x.sql.age", file.path)
        end
        assert_match(%r{R2 PutObject s3://afinados-backups/afinados/x.sql.age}, error.message)
      end
    end

    def test_write_text_diagnostic_names_the_put_object_operation
      error = assert_raises(Error) do
        r2(error: access_denied).write_text("afinados-backups", "afinados/history", "data")
      end
      assert_match(%r{R2 PutObject s3://afinados-backups/afinados/history}, error.message)
    end

    def test_delete_diagnostic_names_the_delete_object_operation
      error = assert_raises(Error) { r2(error: access_denied).delete("afinados-backups", "afinados/old.sql.age") }
      assert_match(%r{R2 DeleteObject s3://afinados-backups/afinados/old.sql.age}, error.message)
    end

    def test_diagnostic_reports_both_credentials_present
      error = assert_raises(Error) { r2(error: access_denied).read_text("b", "k") }
      assert_match(/AWS_ACCESS_KEY_ID present \(10 chars\)/, error.message)
      assert_match(/AWS_SECRET_ACCESS_KEY present/, error.message)
    end

    def test_diagnostic_flags_a_missing_access_key_id
      error = assert_raises(Error) do
        r2(error: access_denied, env: { "AWS_SECRET_ACCESS_KEY" => "shh" }).list("b", "p")
      end
      assert_match(/AWS_ACCESS_KEY_ID empty/, error.message)
    end

    def test_diagnostic_flags_a_missing_secret_access_key
      error = assert_raises(Error) do
        r2(error: access_denied, env: { "AWS_ACCESS_KEY_ID" => "abcdef0123" }).list("b", "p")
      end
      assert_match(/AWS_SECRET_ACCESS_KEY empty/, error.message)
    end
  end
end
