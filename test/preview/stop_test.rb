# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class StopTest < Minitest::Test
      class FakeTeardown
        attr_reader :calls

        def initialize
          @calls = []
        end

        def run(project:, ref:)
          @calls << { project: project, ref: ref }
        end
      end

      def test_invokes_teardown_with_mr_project_and_ref
        teardown = FakeTeardown.new
        Stop.new(env: { "PREVIEW_REF" => "feat-foo" }, io: StringIO.new, teardown: teardown).run
        assert_equal [{ project: "mr-feat-foo", ref: "feat-foo" }], teardown.calls
      end

      def test_requires_preview_ref
        err = assert_raises(Error) { Stop.new(env: {}, io: StringIO.new, teardown: FakeTeardown.new).run }
        assert_match(/PREVIEW_REF/, err.message)
      end
    end
  end
end
