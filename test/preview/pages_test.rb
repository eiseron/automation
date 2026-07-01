# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "tmpdir"
require "zlib"

module EiseronAutomation
  module Preview
    class PagesTest < Minitest::Test
      class FakeRunner
        attr_reader :calls

        def initialize
          @calls = []
        end

        def run(env, *cmd)
          @calls << [env, cmd]
        end
      end

      class FakeCloudflare
        attr_reader :deleted

        def initialize(deployments)
          @deployments = deployments
          @deleted = []
        end

        def deployments(_account, _project) = @deployments

        def delete_deployment(_account, _project, id) = @deleted << id
      end

      def base_env
        {
          "PREVIEW_ACTION" => "deploy",
          "PREVIEW_KIND" => "pages",
          "PREVIEW_MR_IID" => "12",
          "PREVIEW_SHA" => "abc123def",
          "PREVIEW_SITE_PROJECT" => "eiseron/afinados/afinados-site",
          "PREVIEW_PAGES_PROJECT" => "afinados-site",
          "CLOUDFLARE_API_TOKEN" => "cf-tok",
          "CLOUDFLARE_ACCOUNT_ID" => "acct-1",
          "CI_JOB_TOKEN" => "job-tok",
          "CI_API_V4_URL" => "https://gitlab.com/api/v4"
        }
      end

      def write_tarball(entries)
        buffer = StringIO.new
        Gem::Package::TarWriter.new(buffer) do |tar|
          entries.each do |kind, name, payload|
            if kind == :symlink
              tar.add_symlink(name, payload, 0o777)
            else
              tar.add_file(name, 0o644) { |io| io.write(payload) }
            end
          end
        end
        File.binwrite("preview-dist.tgz", Zlib.gzip(buffer.string))
      end

      def run_deploy(env: base_env, entries: [[:file, "index.html", "<h1>ok</h1>"]])
        runner = FakeRunner.new
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_tarball(entries)
            Pages.new(env: env, io: StringIO.new, runner: runner,
                      downloader: ->(*) {}, cloudflare: FakeCloudflare.new([])).run
          end
        end
        runner
      end

      def test_deploy_downloads_sealed_dist_from_the_pinned_site_project
        downloads = []
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_tarball([[:file, "index.html", "x"]])
            downloader = ->(url, path, token) { downloads << [url, path, token] }
            Pages.new(env: base_env, io: StringIO.new, runner: FakeRunner.new,
                      downloader: downloader, cloudflare: FakeCloudflare.new([])).run
          end
        end

        url, _path, token = downloads.fetch(0)
        assert_equal "job-tok", token
        assert_includes url, "/projects/eiseron%2Fafinados%2Fafinados-site/packages/generic/site-preview/"
        assert_includes url, "/abc123def/preview-dist.tgz"
      end

      def test_deploy_never_runs_the_site_build
        cmds = run_deploy.calls.map { |_env, cmd| cmd }
        refute cmds.any? { |c| c.join(" ").match?(/npm|yarn|install|run build/) }, "deployer must never build"
        assert cmds.any? { |c| c.first == "tar" && c.include?("-xzf") }, "sealed dist is extracted, not rebuilt"
      end

      def test_deploy_rejects_symlink_entries_before_extracting
        error = assert_raises(Error) do
          run_deploy(entries: [[:symlink, "evil", "/etc/passwd"], [:file, "index.html", "x"]])
        end
        assert_match(/unsafe tar entry \(link\)/, error.message)
      end

      def test_deploy_rejects_path_traversal_entries
        assert_raises(Error) { run_deploy(entries: [[:file, "../escape.txt", "x"]]) }
      end

      def test_deploy_pins_project_and_branch_from_trusted_sources
        env, cmd = run_deploy.calls.find { |_e, c| c.include?("deploy") && c.first == "npx" }
        assert_includes cmd, "--project-name=afinados-site"
        assert_includes cmd, "--branch=mr12"
        assert_equal "cf-tok", env["CLOUDFLARE_API_TOKEN"]
      end

      def test_rejects_non_numeric_mr_iid
        assert_raises(Error) { run_deploy(env: base_env.merge("PREVIEW_MR_IID" => "12; rm -rf /")) }
      end

      def test_stop_deletes_only_this_branch_deployments
        deployments = [
          { "id" => "keep", "deployment_trigger" => { "metadata" => { "branch" => "mr99" } } },
          { "id" => "drop", "deployment_trigger" => { "metadata" => { "branch" => "mr12" } } }
        ]
        fake = FakeCloudflare.new(deployments)
        Pages.new(env: base_env.merge("PREVIEW_ACTION" => "stop"), io: StringIO.new,
                  runner: FakeRunner.new, downloader: ->(*) {}, cloudflare: fake).run

        assert_equal ["drop"], fake.deleted
      end
    end
  end
end
