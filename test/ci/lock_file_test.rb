# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class LockFileTest < Minitest::Test
      def setup
        @dir = Dir.mktmpdir
        @path = File.join(@dir, "lock.yml")
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def test_render_then_parse_roundtrips
        vars = { "STACK_AUTOMATION_REF" => "v0.17.0", "STACK_GEM_RUNTIME_TAG" => "v0.1.22" }
        File.write(@path, LockFile.render(vars))
        assert_equal vars, LockFile.parse(@path)
      end

      def test_parse_missing_file_is_empty
        assert_equal({}, LockFile.parse(File.join(@dir, "absent.yml")))
      end
    end
  end
end
