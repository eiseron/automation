# frozen_string_literal: true

require "json"
require "fileutils"

module EiseronAutomation
  module Observability
    class Config
      def initialize(env)
        @env = env
      end

      def path
        @env["EISERON_OBS_CONFIG"] || File.join(Dir.home, ".config", "eiseron", "obs.json")
      end

      def load
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      def update(values)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{JSON.pretty_generate(load.merge(values))}\n")
        File.chmod(0o600, path)
      end

      def merged_env
        load.merge(@env)
      end
    end
  end
end
