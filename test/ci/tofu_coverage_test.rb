# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class TofuCoverageTest < Minitest::Test
      def write(dir, rel, content = "")
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def run_coverage(dir, args: [])
        io = StringIO.new
        TofuCoverage.new(root: dir, io: io, args: args).run
        io.string
      end

      def test_reports_percentage_of_modules_with_tests
        Dir.mktmpdir do |dir|
          write(dir, "modules/product/main.tf")
          write(dir, "modules/product/product.tftest.hcl")
          write(dir, "modules/gitlab_runner/main.tf")
          write(dir, "modules/gitlab_runner/gitlab_runner.tftest.hcl")
          write(dir, "modules/prod_host/main.tf")

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 66.7% (2/3 modules)"
        end
      end

      def test_zero_modules_with_tests_reports_zero_percent
        Dir.mktmpdir do |dir|
          write(dir, "modules/prod_host/main.tf")

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 0.0% (0/1 modules)"
        end
      end

      def test_all_modules_tested_reports_full_percent
        Dir.mktmpdir do |dir|
          write(dir, "modules/product/product.tftest.hcl")

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 100.0% (1/1 modules)"
        end
      end

      def test_no_modules_dir_treats_repo_root_as_single_module
        Dir.mktmpdir do |dir|
          write(dir, "main.tf")
          write(dir, "root.tftest.hcl")

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 100.0% (1/1 modules)"
        end
      end

      def test_no_modules_dir_and_no_tests_reports_zero_percent
        Dir.mktmpdir do |dir|
          write(dir, "main.tf")

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 0.0% (0/1 modules)"
        end
      end

      def test_empty_modules_dir_reports_zero_percent_without_error
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "modules"))

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 0.0% (0/0 modules)"
        end
      end

      def test_custom_modules_dir_from_args
        Dir.mktmpdir do |dir|
          write(dir, "submodules/product/product.tftest.hcl")

          output = run_coverage(dir, args: ["--modules-dir", "submodules"])
          assert_includes output, "[TOTAL] 100.0% (1/1 modules)"
        end
      end

      def test_modules_dir_flag_without_value_raises
        Dir.mktmpdir do |dir|
          error = assert_raises(Error) { run_coverage(dir, args: ["--modules-dir"]) }
          assert_match(/--modules-dir requires a value/, error.message)
        end
      end

      def test_modules_dir_flag_followed_by_another_flag_raises
        Dir.mktmpdir do |dir|
          error = assert_raises(Error) { run_coverage(dir, args: ["--modules-dir", "--other"]) }
          assert_match(/--modules-dir requires a value/, error.message)
        end
      end

      def test_nested_test_file_counts_as_tested
        Dir.mktmpdir do |dir|
          write(dir, "modules/product/examples/validate/product.tftest.hcl")

          output = run_coverage(dir)
          assert_includes output, "[TOTAL] 100.0% (1/1 modules)"
        end
      end
    end
  end
end
