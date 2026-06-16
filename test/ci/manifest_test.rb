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
    end
  end
end
