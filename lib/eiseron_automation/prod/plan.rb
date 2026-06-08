# frozen_string_literal: true

module EiseronAutomation
  module Prod
    module Plan
      module_function

      RELEASE = /\Av(\d+)\.(\d+)\.(\d+)\z/

      def parse(tag)
        match = RELEASE.match(tag.to_s.strip)
        match&.captures&.map(&:to_i)
      end

      def latest?(tag, tags)
        current = parse(tag)
        raise Error, "PROD_TAG '#{tag}' is not a release tag (vMAJOR.MINOR.PATCH)" unless current

        tags.filter_map { |candidate| parse(candidate) }.all? { |version| (version <=> current) <= 0 }
      end
    end
  end
end
