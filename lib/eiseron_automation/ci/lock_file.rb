# frozen_string_literal: true

require "yaml"

module EiseronAutomation
  module CI
    class LockFile
      def self.render(vars)
        YAML.dump("variables" => vars)
      end

      def self.parse(path)
        return {} unless File.exist?(path)

        (YAML.safe_load_file(path) || {})["variables"] || {}
      end
    end
  end
end
