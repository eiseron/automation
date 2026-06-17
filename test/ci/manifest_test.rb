# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class ManifestTest < Minitest::Test
      def test_groups_map_to_types_with_full_path_source
        entries = Manifest.parse("gems" => { "gitlab.com/eiseron/stack/automation" => "~> 0.17" })
        assert_equal(
          { type: "gem", name: "gitlab.com/eiseron/stack/automation",
            source: "gitlab.com/eiseron/stack/automation", constraint: "~> 0.17" },
          entries.first
        )
      end

      def test_map_form_carries_source_and_version
        spec = { "source" => "gitlab.com/eiseron/stack/provisioning", "version" => "= 0.15.0" }
        entries = Manifest.parse("repos" => { "provisioning-preview" => spec })
        assert_equal "gitlab.com/eiseron/stack/provisioning", entries.first[:source]
        assert_equal "= 0.15.0", entries.first[:constraint]
      end

      def test_image_group_maps_to_image_type
        entries = Manifest.parse(
          "images" => { "registry.gitlab.com/eiseron/stack/public-image-bases/iac" => "~> 0.1" }
        )
        assert_equal "image", entries.first[:type]
      end

      def test_plain_gem_name_under_gems_routes_to_rubygems
        entry = Manifest.parse("gems" => { "specific_install" => "*" }).first
        assert_equal "gem", entry[:type]
        assert GemRouter.rubygems_source?(entry)
      end

      def test_path_gem_name_under_gems_routes_to_git
        entry = Manifest.parse("gems" => { "gitlab.com/eiseron/stack/automation" => "~> 0.17" }).first
        assert_equal "gem", entry[:type]
        refute GemRouter.rubygems_source?(entry)
      end

      def test_gems_group_can_mix_rubygems_and_git_in_one_block
        entries = Manifest.parse(
          "gems" => {
            "specific_install" => "*",
            "aws-sdk-s3" => "~> 1.215",
            "gitlab.com/eiseron/stack/automation" => "~> 0.17"
          }
        )
        by_name = entries.to_h { |entry| [entry[:name], entry] }
        assert GemRouter.rubygems_source?(by_name["specific_install"])
        assert GemRouter.rubygems_source?(by_name["aws-sdk-s3"])
        refute GemRouter.rubygems_source?(by_name["gitlab.com/eiseron/stack/automation"])
      end
    end
  end
end
