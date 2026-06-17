# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class GemRouterTest < Minitest::Test
      class FakeSource
        attr_reader :calls

        def initialize(label)
          @label = label
          @calls = []
        end

        def candidates(entry)
          @calls << [:candidates, entry[:source]]
          [{ label: @label }]
        end

        def finalize(entry, candidate)
          @calls << [:finalize, entry[:source]]
          { label: @label, candidate: candidate }
        end
      end

      def setup
        @git = FakeSource.new(:git)
        @rubygems = FakeSource.new(:rubygems)
        @router = GemRouter.new(git: @git, rubygems: @rubygems)
      end

      def test_path_source_routes_to_git
        @router.candidates({ type: "gem", source: "gitlab.com/eiseron/stack/automation" })
        assert_equal [[:candidates, "gitlab.com/eiseron/stack/automation"]], @git.calls
        assert_empty @rubygems.calls
      end

      def test_plain_source_routes_to_rubygems
        @router.candidates({ type: "gem", source: "specific_install" })
        assert_equal [[:candidates, "specific_install"]], @rubygems.calls
        assert_empty @git.calls
      end

      def test_finalize_also_routes_by_source_format
        @router.finalize({ type: "gem", source: "aws-sdk-s3" }, { version: "1.0.0" })
        assert_equal [[:finalize, "aws-sdk-s3"]], @rubygems.calls
        assert_empty @git.calls
      end

      def test_rubygems_source_query_is_static
        assert GemRouter.rubygems_source?({ source: "specific_install" })
        refute GemRouter.rubygems_source?({ source: "gitlab.com/x/y" })
      end
    end
  end
end
