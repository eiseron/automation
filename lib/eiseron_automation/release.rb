# frozen_string_literal: true

module EiseronAutomation
  # Resolves a version from a file and creates the matching git tag through the
  # GitLab API, lifting and restoring tag protection around the create so a
  # "no one" protection can be satisfied only by this automated path. A tag
  # therefore always maps to a reviewed change that bumped the version file.
  class Release
    SEMVER = /\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/

    def initialize(client:, commit_sha:, io: $stdout)
      @client = client
      @commit_sha = commit_sha
      @io = io
    end

    # Pure: returns the validated bare version or raises with a specific reason.
    def self.validate_version(raw)
      version = raw.to_s.strip
      raise Error, "VERSION file is empty" if version.empty?

      no_v_prefix(version)
      semver(version)
      version
    end

    def self.no_v_prefix(version)
      return unless version.start_with?("v")

      raise Error, "version must not include the 'v' prefix (got '#{version}')"
    end

    def self.semver(version)
      return if version.match?(SEMVER)

      raise Error, "'#{version}' is not semver MAJOR.MINOR.PATCH"
    end

    def tag_from_file(path)
      tag = "v#{self.class.validate_version(File.read(path))}"
      return skip(tag) if @client.tag_exists?(tag)

      create_with_protection_lifted(tag)
      tag
    end

    private

    def skip(tag)
      @io.puts "Tag #{tag} already exists — nothing to do (idempotent re-run)."
      tag
    end

    def create_with_protection_lifted(tag)
      @io.puts "Lifting tag protection..."
      @client.delete_tag_protection
      @io.puts "Creating #{tag} at #{@commit_sha}..."
      @client.create_tag(tag, @commit_sha)
      @io.puts "Created #{tag}."
    ensure
      @client.protect_tags_no_one
      @io.puts "Restored tag protection (create: no one)."
    end
  end
end
