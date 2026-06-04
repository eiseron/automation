# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class FakeClient
    attr_reader :calls

    def initialize(exists: false)
      @exists = exists
      @calls = []
    end

    def tag_exists?(tag)
      @calls << [:exists?, tag]
      @exists
    end

    def create_tag(tag, ref)
      @calls << [:create, tag, ref]
    end
  end

  class ReleaseValidateTest < Minitest::Test
    def test_accepts_plain_semver
      assert_equal "0.1.1", Release.validate_version("0.1.1")
    end

    def test_strips_surrounding_whitespace
      assert_equal "0.2.0", Release.validate_version("  0.2.0\n")
    end

    def test_accepts_prerelease_suffix
      assert_equal "1.0.0-rc1", Release.validate_version("1.0.0-rc1")
    end

    def test_rejects_v_prefix_with_specific_reason
      error = assert_raises(Error) { Release.validate_version("v0.1.1") }
      assert_match(/must not include the 'v' prefix/, error.message)
    end

    def test_rejects_empty_with_specific_reason
      error = assert_raises(Error) { Release.validate_version("   ") }
      assert_match(/empty/, error.message)
    end

    def test_rejects_two_component_as_non_semver
      error = assert_raises(Error) { Release.validate_version("1.2") }
      assert_match(/not semver/, error.message)
    end

    def test_rejects_non_numeric_as_non_semver
      error = assert_raises(Error) { Release.validate_version("abc") }
      assert_match(/not semver/, error.message)
    end
  end

  class ReleaseFlowTest < Minitest::Test
    def setup
      @dir = Dir.mktmpdir
      @path = File.join(@dir, "VERSION")
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def run_tag(content, exists: false)
      File.write(@path, content)
      client = FakeClient.new(exists: exists)
      tag = Release.new(client: client, commit_sha: "deadbeef", io: StringIO.new).tag_from_file(@path)
      [tag, client]
    end

    def test_creates_tag_when_absent
      tag, client = run_tag("0.1.1")
      assert_equal "v0.1.1", tag
      assert_equal([[:exists?, "v0.1.1"], [:create, "v0.1.1", "deadbeef"]], client.calls)
    end

    def test_idempotent_when_tag_already_exists
      _tag, client = run_tag("0.1.1", exists: true)
      refute_includes client.calls.map(&:first), :create
    end

    def test_create_failure_propagates
      File.write(@path, "0.1.1")
      client = FakeClient.new(exists: false)
      def client.create_tag(*)
        raise Error, "boom"
      end

      assert_raises(Error) do
        Release.new(client: client, commit_sha: "x", io: StringIO.new).tag_from_file(@path)
      end
    end
  end
end
