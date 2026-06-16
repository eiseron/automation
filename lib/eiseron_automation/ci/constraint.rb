# frozen_string_literal: true

require "rubygems"

module EiseronAutomation
  module CI
    class Constraint
      def self.best(constraint, candidates)
        requirement = requirement(constraint)
        match = candidates
                .select { |candidate| satisfied?(requirement, candidate[:version]) }
                .max_by { |candidate| version(candidate[:version]) }
        raise Error, "no version satisfies '#{constraint}'" unless match

        match
      end

      def self.satisfies?(constraint, value)
        satisfied?(requirement(constraint), value.to_s.sub(/\Av/, ""))
      end

      def self.satisfied?(requirement, raw)
        parsed = version(raw)
        return false unless parsed

        requirement.satisfied_by?(parsed)
      end

      def self.requirement(constraint)
        return Gem::Requirement.default if blank?(constraint) || constraint.strip == "*"

        Gem::Requirement.new(constraint.split(",").map(&:strip))
      end

      def self.version(raw)
        Gem::Version.new(raw.to_s.sub(/\Av/, ""))
      rescue ArgumentError
        nil
      end

      def self.blank?(value)
        value.nil? || value.to_s.strip.empty?
      end
    end
  end
end
