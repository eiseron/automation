# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class GitSourceTest < Minitest::Test
      OUTPUT = <<~LS
        1111111\trefs/tags/v0.1.0
        aaaaaaa\trefs/tags/v0.16.0
        bbbbbbb\trefs/tags/v0.16.0^{}
        ccccccc\trefs/tags/not-semver
      LS

      def test_lightweight_tag_uses_direct_sha
        record = GitSource.parse(OUTPUT).find { |entry| entry[:ref] == "v0.1.0" }
        assert_equal "1111111", record[:sha]
      end

      def test_annotated_tag_uses_peeled_commit_sha
        record = GitSource.parse(OUTPUT).find { |entry| entry[:ref] == "v0.16.0" }
        assert_equal "bbbbbbb", record[:sha]
      end

      def test_non_semver_tags_are_dropped
        refs = GitSource.parse(OUTPUT).map { |entry| entry[:ref] }
        refute_includes refs, "not-semver"
      end

      def test_finalize_carries_full_repo_url
        entry = { type: "gem", source: "gitlab.com/eiseron/stack/automation" }
        record = GitSource.new.finalize(entry, { ref: "v0.17.0", sha: "75ec173" })
        assert_equal "https://gitlab.com/eiseron/stack/automation.git", record[:repo]
        assert_equal "75ec173", record[:sha]
      end
    end
  end
end
