# frozen_string_literal: true

require "json"
require "fileutils"

module EiseronAutomation
  class Docs
    TAG = /\Av(\d+)\.(\d+)\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/
    VERSION_DIR = /\Av\d/

    def initialize(env: ENV, io: $stdout)
      @env = env
      @io = io
    end

    def self.version_from_tag(raw)
      match = TAG.match(raw.to_s.strip)
      raise Error, "'#{raw.to_s.strip}' is not a vMAJOR.MINOR.PATCH tag" unless match

      "v#{match[1]}.#{match[2]}"
    end

    def self.merge_versions(existing, version)
      (Array(existing) + [version]).uniq.sort_by do |entry|
        entry.delete_prefix("v").split(".").map(&:to_i)
      end
    end

    def publish
      version = self.class.version_from_tag(require_env("CI_COMMIT_TAG"))
      site = clone_site
      locale_map.each { |locale, dest| sync_locale(locale, dest, site, version) }
      write_versions(site, version)
      commit_and_push(site)
    end

    private

    def clone_site
      dir = "/tmp/eiseron-docs-site"
      url = "https://oauth2:#{require_env('GITLAB_TOKEN')}@" \
            "#{@env.fetch('CI_SERVER_HOST', 'gitlab.com')}/#{require_env('DOCS_SITE_REPO')}.git"
      FileUtils.rm_rf(dir)
      run("git", "clone", "--depth", "1", url, dir)
      dir
    end

    def sync_locale(locale, dest, site, version)
      source = File.join(require_env("CI_PROJECT_DIR"), source_dir, locale)
      raise Error, "missing docs: #{source}" unless Dir.exist?(source)

      dest_dir = File.join(site, dest)
      refresh_latest(source, dest_dir)
      freeze_snapshot(source, File.join(dest_dir, version))
      @io.puts "Synced #{locale} -> #{dest} (#{version})"
    end

    def refresh_latest(source, dest_dir)
      FileUtils.mkdir_p(dest_dir)
      Dir.children(dest_dir)
         .grep_v(VERSION_DIR)
         .each { |entry| FileUtils.rm_rf(File.join(dest_dir, entry)) }
      copy_into(source, dest_dir)
    end

    def freeze_snapshot(source, dir)
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(dir)
      copy_into(source, dir)
    end

    def write_versions(site, version)
      path = File.join(site, @env.fetch("DOCS_VERSIONS_FILE", "versions.json"))
      existing = File.exist?(path) ? JSON.parse(File.read(path)) : []
      File.write(path, "#{JSON.generate(self.class.merge_versions(existing, version))}\n")
    end

    def commit_and_push(site)
      run("git", "-C", site, "add", "-A")
      return @io.puts("No doc changes to publish.") if clean?(site)

      identity(site)
      run("git", "-C", site, "commit", "-m", "chore: freeze docs for #{require_env('CI_COMMIT_TAG')}")
      run("git", "-C", site, "push", "origin", "HEAD:#{@env.fetch('DOCS_SITE_BRANCH', 'main')}")
      @io.puts "Published docs to #{require_env('DOCS_SITE_REPO')}."
    end

    def identity(site)
      run("git", "-C", site, "config", "user.email", @env.fetch("DOCS_GIT_EMAIL", "ci@eiseron.com"))
      run("git", "-C", site, "config", "user.name", @env.fetch("DOCS_GIT_NAME", "Eiseron CI"))
    end

    def clean?(site)
      system("git", "-C", site, "diff", "--cached", "--quiet")
    end

    def copy_into(source, dest)
      entries = Dir.glob(File.join(source, "*"))
      FileUtils.cp_r(entries, dest) unless entries.empty?
    end

    def locale_map
      parsed = JSON.parse(require_env("DOCS_LOCALE_MAP"))
      raise Error, "DOCS_LOCALE_MAP must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    end

    def source_dir
      @env.fetch("DOCS_SOURCE_DIR", "docs")
    end

    def run(*cmd)
      raise Error, "command failed: #{cmd.join(' ')}" unless system(*cmd)
    end

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end
  end
end
