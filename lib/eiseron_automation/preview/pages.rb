# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "net/http"
require "uri"

module EiseronAutomation
  module Preview
    class Pages
      PACKAGE_NAME = "site-preview"
      TARBALL = "preview-dist.tgz"
      DEPLOY_DIR = "preview-dist"
      DEFAULT_WRANGLER = "4.106.0"

      def initialize(env: ENV, io: $stdout, runner: Runner.new, downloader: nil, cloudflare: nil)
        @env = env
        @io = io
        @runner = runner
        @downloader = downloader
        @cloudflare = cloudflare
      end

      def run
        case @env["PREVIEW_ACTION"]
        when "deploy" then deploy
        when "stop" then stop
        else raise Error, "PREVIEW_ACTION must be deploy or stop for pages previews"
        end
      end

      private

      def deploy
        fetch_sealed_dist
        @runner.run(
          cloudflare_env,
          "npx", "--yes", "wrangler@#{wrangler_version}", "pages", "deploy", DEPLOY_DIR,
          "--project-name=#{pages_project}", "--branch=#{branch}", "--commit-dirty=true"
        )
        @io.puts "Preview live at https://#{branch}.#{pages_project}.pages.dev"
      end

      def stop
        matching = cloudflare.deployments(account_id, pages_project).select do |deployment|
          deployment.dig("deployment_trigger", "metadata", "branch") == branch
        end
        if matching.empty?
          @io.puts "No preview deployments for #{branch}"
          return
        end
        matching.each do |deployment|
          cloudflare.delete_deployment(account_id, pages_project, deployment["id"])
          @io.puts "Deleted deployment #{deployment['id']}"
        end
      end

      def fetch_sealed_dist
        FileUtils.rm_rf(DEPLOY_DIR)
        FileUtils.mkdir_p(DEPLOY_DIR)
        downloader.call(package_url, TARBALL, require_env("CI_JOB_TOKEN"))
        SealedTarball.verify(TARBALL)
        @runner.run({}, "tar", "--no-same-owner", "-xzf", TARBALL, "-C", DEPLOY_DIR)
      end

      def package_url
        site = CGI.escape(require_env("PREVIEW_SITE_PROJECT"))
        "#{require_env('CI_API_V4_URL')}/projects/#{site}" \
          "/packages/generic/#{PACKAGE_NAME}/#{sha}/#{TARBALL}"
      end

      def downloader
        @downloader ||= method(:get_package)
      end

      def get_package(url, path, job_token)
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["JOB-TOKEN"] = job_token
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(request)
        end
        raise Error, "sealed dist download failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(path, response.body)
      end

      def cloudflare
        @cloudflare ||= CloudflareClient.new(token: require_env("CLOUDFLARE_API_TOKEN"))
      end

      def cloudflare_env
        {
          "CLOUDFLARE_API_TOKEN" => require_env("CLOUDFLARE_API_TOKEN"),
          "CLOUDFLARE_ACCOUNT_ID" => account_id
        }
      end

      def pages_project = require_env("PREVIEW_PAGES_PROJECT")
      def account_id = require_env("CLOUDFLARE_ACCOUNT_ID")
      def wrangler_version = @env.fetch("PREVIEW_WRANGLER_VERSION", DEFAULT_WRANGLER)
      def branch = "mr#{mr_iid}"

      def mr_iid
        iid = require_env("PREVIEW_MR_IID")
        raise Error, "PREVIEW_MR_IID must be numeric, got '#{iid}'" unless iid.match?(/\A\d+\z/)

        iid
      end

      def sha
        value = require_env("PREVIEW_SHA")
        raise Error, "PREVIEW_SHA must be a hex commit sha, got '#{value}'" unless value.match?(/\A[0-9a-f]{7,64}\z/)

        value
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
