# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class DocsVersionTest < Minitest::Test
    def test_derives_minor_version_from_tag
      assert_equal "v1.2", Docs.version_from_tag("v1.2.3")
    end

    def test_strips_surrounding_whitespace
      assert_equal "v0.4", Docs.version_from_tag("  v0.4.0\n")
    end

    def test_accepts_prerelease_suffix
      assert_equal "v1.0", Docs.version_from_tag("v1.0.0-rc1")
    end

    def test_rejects_tag_without_v_prefix
      error = assert_raises(Error) { Docs.version_from_tag("0.1.0") }
      assert_match(/vMAJOR\.MINOR\.PATCH/, error.message)
    end

    def test_rejects_non_semver_tag
      error = assert_raises(Error) { Docs.version_from_tag("v1.2") }
      assert_match(/vMAJOR\.MINOR\.PATCH/, error.message)
    end
  end

  class DocsMergeVersionsTest < Minitest::Test
    def test_appends_new_version
      assert_equal ["v0.1", "v0.2"], Docs.merge_versions(["v0.1"], "v0.2")
    end

    def test_dedupes_existing_version
      assert_equal ["v0.2"], Docs.merge_versions(["v0.2"], "v0.2")
    end

    def test_sorts_numerically_not_lexically
      assert_equal ["v0.2", "v0.10"], Docs.merge_versions(["v0.10", "v0.2"], "v0.2")
    end

    def test_handles_empty_existing
      assert_equal ["v0.1"], Docs.merge_versions([], "v0.1")
    end
  end
end
