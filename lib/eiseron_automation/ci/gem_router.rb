# frozen_string_literal: true

module EiseronAutomation
  module CI
    class GemRouter
      def initialize(git:, rubygems:)
        @git = git
        @rubygems = rubygems
      end

      def candidates(entry)
        source_for(entry).candidates(entry)
      end

      def finalize(entry, candidate)
        source_for(entry).finalize(entry, candidate)
      end

      def self.rubygems_source?(entry)
        !entry[:source].include?("/")
      end

      private

      def source_for(entry)
        self.class.rubygems_source?(entry) ? @rubygems : @git
      end
    end
  end
end
