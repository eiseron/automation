# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class NamingTest < Minitest::Test
      def test_image_var_base_uses_name_basename
        path = "registry.gitlab.com/eiseron/stack/public-image-bases/gem-runtime"
        assert_equal "GEM_RUNTIME", Naming.var_base({ type: "image", name: path, source: path })
      end

      def test_image_var_base_uses_explicit_name_distinct_from_source
        entry = { type: "image", name: "postgres-drill", source: "postgres" }
        assert_equal "POSTGRES_DRILL", Naming.var_base(entry)
      end

      def test_gem_var_base_uses_full_path_basename
        path = "gitlab.com/eiseron/stack/automation"
        assert_equal "AUTOMATION", Naming.var_base({ type: "gem", name: path, source: path })
      end

      def test_gem_var_base_normalizes_dashes_to_underscores_for_rubygems_style_name
        entry = { type: "gem", name: "aws-sdk-s3", source: "aws-sdk-s3" }
        assert_equal "AWS_SDK_S3", Naming.var_base(entry)
      end

      def test_git_url_from_full_path
        assert_equal "https://gitlab.com/eiseron/stack/automation.git",
                     Naming.git_url("gitlab.com/eiseron/stack/automation")
      end

      def test_git_url_treats_non_url_source_as_host_path
        assert_equal "https://host.example/group/repo.git", Naming.git_url("host.example/group/repo")
      end

      def test_git_url_passthrough_for_explicit_url
        url = "https://example.com/x.git"
        assert_equal url, Naming.git_url(url)
      end

      def test_image_ref_passthrough_for_registry_host
        ref = "registry.gitlab.com/eiseron/stack/public-image-bases/iac"
        assert_equal ref, Naming.image_ref(ref)
      end

      def test_image_ref_defaults_official_to_docker_io_library
        assert_equal "docker.io/library/ruby", Naming.image_ref("ruby")
      end

      def test_image_ref_defaults_namespaced_to_docker_io
        assert_equal "docker.io/user/img", Naming.image_ref("user/img")
      end
    end
  end
end
