# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class FakeGitSource
      def initialize(map)
        @map = map
      end

      def candidates(entry)
        @map.fetch(entry[:source])
      end

      def finalize(entry, candidate)
        { repo: Naming.git_url(entry[:source]), ref: candidate[:ref], sha: candidate[:sha] }
      end
    end

    class FakeRegistrySource
      def initialize(tags:, digest:, labels: {})
        @tags = tags
        @digest = digest
        @labels = labels
      end

      def candidates(entry)
        @tags.fetch(entry[:source]).map { |tag| { version: tag.sub(/\Av/, ""), tag: tag } }
      end

      def finalize(entry, candidate)
        { tag: candidate[:tag], digest: @digest, image: "#{entry[:source]}@#{@digest}" }
      end

      def label(image, _key)
        @labels[image]
      end
    end

    class LockTest < Minitest::Test
      AUTOMATION = "gitlab.com/eiseron/stack/automation"
      GEM_RUNTIME = "registry.gitlab.com/eiseron/stack/public-image-bases/gem-runtime"

      def setup
        @dir = Dir.mktmpdir
        @manifest = File.join(@dir, "manifest.yml")
        @lock = File.join(@dir, "lock.yml")
        write_manifest("~> 0.16.0")
      end

      def teardown
        FileUtils.remove_entry(@dir)
      end

      def write_manifest(automation_constraint)
        File.write(@manifest, <<~YAML)
          gems:
            #{AUTOMATION}: "#{automation_constraint}"
          images:
            #{GEM_RUNTIME}: "~> 0.1"
        YAML
      end

      def git_source
        FakeGitSource.new(
          AUTOMATION => [
            { version: "0.16.0", ref: "v0.16.0", sha: "134ee8b" },
            { version: "0.17.0", ref: "v0.17.0", sha: "75ec173" }
          ]
        )
      end

      def registry_source(label: "134ee8b")
        FakeRegistrySource.new(
          tags: { GEM_RUNTIME => ["v0.1.21", "v0.1.22"] },
          digest: "sha256:dead",
          labels: { "#{GEM_RUNTIME}@sha256:dead" => label }
        )
      end

      def build(registry: registry_source)
        Lock.new(
          manifest_path: @manifest, lock_path: @lock,
          sources: { "gem" => git_source, "repo" => git_source, "image" => registry },
          io: StringIO.new
        )
      end

      def install_vars
        build.install
        LockFile.parse(@lock)
      end

      def test_init_scaffolds_manifest_when_absent
        fresh = File.join(@dir, "new-manifest.yml")
        Lock.new(manifest_path: fresh, lock_path: @lock, sources: {}, io: StringIO.new).init
        assert_equal({ "gems" => {}, "repos" => {}, "images" => {} }, YAML.safe_load_file(fresh))
      end

      def test_init_does_not_clobber_existing_manifest
        before = File.read(@manifest)
        Lock.new(manifest_path: @manifest, lock_path: @lock, sources: {}, io: StringIO.new).init
        assert_equal before, File.read(@manifest)
      end

      def test_install_creates_lock_when_absent
        refute File.exist?(@lock)
        install_vars
        assert File.exist?(@lock)
      end

      def test_install_pins_gem_to_full_repo_ref_and_commit_sha
        vars = install_vars
        assert_equal "https://gitlab.com/eiseron/stack/automation.git", vars["STACK_AUTOMATION_REPO"]
        assert_equal "v0.16.0", vars["STACK_AUTOMATION_REF"]
        assert_equal "134ee8b", vars["STACK_AUTOMATION_SHA"]
      end

      def test_install_pins_image_to_full_digest_reference
        vars = install_vars
        assert_equal "#{GEM_RUNTIME}@sha256:dead", vars["STACK_GEM_RUNTIME_IMAGE"]
        assert_equal "v0.1.22", vars["STACK_GEM_RUNTIME_TAG"]
      end

      def test_check_passes_when_label_matches_locked_automation_sha
        build.install
        build.check
      end

      def test_check_fails_when_gem_runtime_label_diverges
        build.install
        diverging = build(registry: registry_source(label: "75ec173"))
        error = assert_raises(Error) { diverging.check }
        assert_match(/gem-runtime bakes automation_ref/, error.message)
      end

      def test_check_fails_when_locked_version_violates_manifest
        build.install
        write_manifest("= 0.99.0")
        error = assert_raises(Error) { build.check }
        assert_match(/does not satisfy/, error.message)
      end

      def test_check_fails_when_lock_missing_a_variable
        build.install
        vars = LockFile.parse(@lock)
        vars.delete("STACK_AUTOMATION_SHA")
        File.write(@lock, LockFile.render(vars))
        error = assert_raises(Error) { build.check }
        assert_match(/STACK_AUTOMATION_SHA is missing/, error.message)
      end

      def test_check_fails_when_lock_absent
        error = assert_raises(Error) { build.check }
        assert_match(/lock.yml is missing/, error.message)
      end

      def test_update_reresolves_named_dependency
        build.install
        write_manifest("~> 0.17.0")
        build.update([AUTOMATION])
        assert_equal "v0.17.0", LockFile.parse(@lock)["STACK_AUTOMATION_REF"]
      end

      def test_install_keeps_satisfying_pin_without_refetch
        build.install
        exploding = FakeGitSource.new({})
        lock = Lock.new(
          manifest_path: @manifest, lock_path: @lock,
          sources: { "gem" => exploding, "repo" => exploding, "image" => registry_source }, io: StringIO.new
        )
        lock.install
        assert_equal "v0.16.0", LockFile.parse(@lock)["STACK_AUTOMATION_REF"]
      end
    end
  end
end
