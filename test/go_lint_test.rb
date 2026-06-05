# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class FakeGoRunner
    attr_reader :commands

    def initialize(gofmt_output: "")
      @gofmt_output = gofmt_output
      @commands = []
    end

    def run(*cmd)
      @commands << cmd
    end

    def capture(*cmd)
      @commands << cmd
      @gofmt_output
    end
  end

  class GoLintCommentTest < Minitest::Test
    def test_detects_line_comment
      assert GoLint.comment?("// a comment")
      assert GoLint.comment?("\tx := 1 // trailing")
    end

    def test_allows_go_directives
      refute GoLint.comment?("//go:build integration")
      refute GoLint.comment?("//go:embed VERSION")
    end

    def test_ignores_double_slash_inside_literals
      refute GoLint.comment?('url := "https://example.com"')
      refute GoLint.comment?("re := regexp.MustCompile(`a//b`)")
      refute GoLint.comment?("r := 'x'")
    end

    def test_detects_block_comment
      assert GoLint.comment?("x := 1 /* nope */")
    end

    def test_ignores_pure_code
      refute GoLint.comment?("a := b / c")
      refute GoLint.comment?("func F() {}")
    end

    def test_scan_reports_line_numbers
      assert_equal [2], GoLint.scan("package x\n// bad\nfunc F() {}\n")
    end
  end

  class GoLintSkipTest < Minitest::Test
    def test_skips_cache_vendor_git
      assert GoLint.skip?(".cache/go-mod/dep/d.go")
      assert GoLint.skip?("vendor/x/y.go")
      refute GoLint.skip?("internal/model/entry.go")
    end
  end

  class GoLintFilesystemTest < Minitest::Test
    def test_check_comments_excludes_cache_and_reports_project_files
      Dir.mktmpdir do |dir|
        write(dir, ".cache/go-mod/dep/d.go", "package dep\n// dep comment\n")
        write(dir, "internal/clean.go", "package x\nfunc X() {}\n")
        GoLint.new(root: dir, runner: FakeGoRunner.new, io: StringIO.new).check_comments

        write(dir, "internal/bad.go", "package x\n// nope\nfunc Y() {}\n")
        error = assert_raises(Error) do
          GoLint.new(root: dir, runner: FakeGoRunner.new, io: StringIO.new).check_comments
        end
        assert_match(%r{internal/bad\.go:2}, error.message)
        refute_match(%r{dep/d\.go}, error.message)
      end
    end

    def test_check_gofmt_ignores_cache_paths
      ok = FakeGoRunner.new(gofmt_output: ".cache/go-mod/dep/d.go\n")
      GoLint.new(root: ".", runner: ok, io: StringIO.new).check_gofmt

      mixed = FakeGoRunner.new(gofmt_output: "internal/x.go\n.cache/dep.go\n")
      error = assert_raises(Error) do
        GoLint.new(root: ".", runner: mixed, io: StringIO.new).check_gofmt
      end
      assert_match(%r{internal/x\.go}, error.message)
      refute_match(/dep\.go/, error.message)
    end

    def test_run_invokes_vet_and_golangci
      Dir.mktmpdir do |dir|
        runner = FakeGoRunner.new
        GoLint.new(root: dir, runner: runner, io: StringIO.new).run
        assert_includes runner.commands, %w[go vet ./...]
        assert_includes runner.commands, ["golangci-lint", "run", "./..."]
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
