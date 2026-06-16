# frozen_string_literal: true

require "json"

module EiseronAutomation
  module CI
    class RegistrySource
      SEMVER = /\Av?\d+\.\d+\.\d+\z/

      def initialize(runner: CommandRunner.new)
        @runner = runner
      end

      def candidates(entry)
        ref = Naming.image_ref(entry[:source])
        tags(ref).map { |tag| { version: tag.sub(/\Av/, ""), tag: tag } }
      end

      def finalize(entry, candidate)
        ref = Naming.image_ref(entry[:source])
        digest = @runner.capture("crane", "digest", "#{ref}:#{candidate[:tag]}").strip
        { tag: candidate[:tag], digest: digest, image: "#{ref}@#{digest}" }
      end

      def label(image, key)
        config = JSON.parse(@runner.capture("crane", "config", image))
        (config.dig("config", "Labels") || {})[key]
      end

      def tags(ref)
        @runner.capture("crane", "ls", ref).to_s.split("\n").map(&:strip).grep(SEMVER)
      end
    end
  end
end
