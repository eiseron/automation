# frozen_string_literal: true

module EiseronAutomation
  module CI
    class Naming
      DEFAULT_REGISTRY = "docker.io"

      def self.var_base(entry)
        reference = entry[:type] == "image" ? entry[:source] : entry[:name]
        basename(reference).upcase.gsub(/[^A-Z0-9]+/, "_")
      end

      def self.basename(reference)
        reference.split("/").last.split(":").first
      end

      def self.git_url(source)
        return source if source.include?("://") || source.include?("@")

        "https://#{source}.git"
      end

      def self.image_ref(source)
        return source if registry?(source)
        return "#{DEFAULT_REGISTRY}/#{source}" if source.include?("/")

        "#{DEFAULT_REGISTRY}/library/#{source}"
      end

      def self.registry?(source)
        return false unless source.include?("/")

        head = source.split("/").first
        head.include?(".") || head.include?(":") || head == "localhost"
      end
    end
  end
end
