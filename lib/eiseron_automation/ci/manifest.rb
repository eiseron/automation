# frozen_string_literal: true

require "yaml"

module EiseronAutomation
  module CI
    class Manifest
      GROUPS = { "gems" => "gem", "repos" => "repo", "images" => "image" }.freeze

      def self.load(path)
        raise Error, "manifest not found: #{path}" unless File.exist?(path)

        parse(YAML.safe_load_file(path) || {})
      end

      def self.parse(data)
        GROUPS.flat_map do |group, type|
          (data[group] || {}).map { |name, spec| entry(type, name.to_s, spec) }
        end
      end

      def self.entry(type, name, spec)
        return string_entry(type, name, spec) if spec.is_a?(String)

        {
          type: type,
          name: name,
          source: (spec["source"] || name).to_s,
          constraint: (spec["version"] || spec["constraint"]).to_s
        }
      end

      def self.string_entry(type, name, spec)
        { type: type, name: name, source: name, constraint: spec }
      end
    end
  end
end
