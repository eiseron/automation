# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class TofuLintCommentTest < Minitest::Test
    def test_detects_comment_forms
      assert TofuLint.comment?("# a comment")
      assert TofuLint.comment?("  a = 1 // inline")
      assert TofuLint.comment?("  b = 2#tight")
      assert TofuLint.comment?("/* block */")
    end

    def test_ignores_markers_inside_strings
      refute TofuLint.comment?('url = "https://example.com#frag"')
      refute TofuLint.comment?('color = "#fff"')
      refute TofuLint.comment?('path = "a//b"')
    end

    def test_ignores_pure_code
      refute TofuLint.comment?("a = b")
      refute TofuLint.comment?('resource "x" "y" {')
    end

    def test_scan_reports_line_numbers
      assert_equal [2], TofuLint.scan("a = 1\n# bad\nb = 2\n")
    end

    def test_scan_skips_heredoc_bodies
      tf = <<~TF
        user_data = <<-EOT
          #!/bin/sh
          echo hi  # shell content
          curl https://a//b
        EOT
        policy = <<"JSON"
        {"u": "x//y", "n": "#1"}
        JSON
      TF
      assert_empty TofuLint.scan(tf)
    end

    def test_scan_flags_comment_after_heredoc_closes
      tf = "x = <<-EOT\n  body\nEOT\n# real comment\n"
      assert_equal [4], TofuLint.scan(tf)
    end

    def test_string_containing_heredoc_marker_does_not_open_heredoc
      tf = "a = \"<<EOT\"\n# real comment\n"
      assert_equal [2], TofuLint.scan(tf)
    end
  end

  class TofuLintSkipTest < Minitest::Test
    def test_skips_terraform_and_git
      assert TofuLint.skip?(".terraform/modules/x/main.tf")
      assert TofuLint.skip?(".git/x.tf")
      refute TofuLint.skip?("modules/preview_host/main.tf")
    end
  end

  class TofuLintFilesystemTest < Minitest::Test
    def test_run_excludes_dot_terraform_and_reports_project_files
      Dir.mktmpdir do |dir|
        write(dir, ".terraform/modules/dep/main.tf", "# vendored comment\n")
        write(dir, "main.tf", "resource \"x\" \"y\" {}\n")
        TofuLint.new(root: dir, io: StringIO.new).run

        write(dir, "pipeline.tf", "# nope\nresource \"a\" \"b\" {}\n")
        error = assert_raises(Error) do
          TofuLint.new(root: dir, io: StringIO.new).run
        end
        assert_match(/pipeline\.tf:1/, error.message)
        refute_match(%r{dep/main\.tf}, error.message)
      end
    end

    private

    def write(dir, rel, content)
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end
end
