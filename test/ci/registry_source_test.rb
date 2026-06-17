# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class RegistrySourceTest < Minitest::Test
      class FakeRunner
        def initialize(out)
          @out = out
        end

        def capture(*)
          @out
        end
      end

      def candidates_for(tags_output)
        source = RegistrySource.new(runner: FakeRunner.new(tags_output))
        source.candidates({ type: "image", source: "x" }).map { |c| c[:tag] }
      end

      def test_accepts_strict_semver_tags
        tags = candidates_for("v0.1.21\n0.1.22\n1.2.3\n")
        assert_equal %w[v0.1.21 0.1.22 1.2.3], tags
      end

      def test_accepts_two_part_versions
        tags = candidates_for("18\n3.3\n3.23\n")
        assert_equal %w[18 3.3 3.23], tags
      end

      def test_accepts_docker_hub_suffix_tags
        tags = candidates_for("3.3-alpine\n18-alpine\n16-alpine\n")
        assert_equal %w[3.3-alpine 18-alpine 16-alpine], tags
      end

      def test_accepts_compound_distro_suffixes
        tags = candidates_for("18-bookworm-slim\n3.3-alpine3.20\n")
        assert_equal %w[18-bookworm-slim 3.3-alpine3.20], tags
      end

      def test_rejects_floating_labels
        tags = candidates_for("latest\nnightly\nmaster\n18-alpine\n")
        assert_equal %w[18-alpine], tags
      end

      def test_rejects_letter_prefixed_garbage
        tags = candidates_for("alpha\nbeta\nrc1\n3.3-alpine\n")
        assert_equal %w[3.3-alpine], tags
      end
    end
  end
end
