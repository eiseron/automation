# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module CI
    class ConstraintTest < Minitest::Test
      def candidates(*versions)
        versions.map { |raw| { version: raw.sub(/\Av/, ""), ref: raw } }
      end

      def test_pessimistic_stays_within_patch_range
        best = Constraint.best("~> 0.1.0", candidates("v0.1.0", "v0.1.21", "v0.2.0"))
        assert_equal "v0.1.21", best[:ref]
      end

      def test_pessimistic_minor_allows_next_minor
        best = Constraint.best("~> 0.1", candidates("v0.1.21", "v0.2.0"))
        assert_equal "v0.2.0", best[:ref]
      end

      def test_exact_pin_selects_that_version
        best = Constraint.best("= 0.50.0", candidates("v0.49.0", "v0.50.0", "v0.51.0"))
        assert_equal "v0.50.0", best[:ref]
      end

      def test_gte_selects_highest
        best = Constraint.best(">= 0.16.0", candidates("v0.15.1", "v0.16.0", "v0.17.0"))
        assert_equal "v0.17.0", best[:ref]
      end

      def test_star_selects_highest
        best = Constraint.best("*", candidates("v0.1.0", "v0.9.0"))
        assert_equal "v0.9.0", best[:ref]
      end

      def test_raises_when_nothing_satisfies
        error = assert_raises(Error) { Constraint.best("= 9.9.9", candidates("v0.1.0")) }
        assert_match(/no version satisfies/, error.message)
      end

      def test_satisfies_is_true_within_range
        assert Constraint.satisfies?("~> 0.1.0", "v0.1.5")
      end

      def test_satisfies_is_false_outside_range
        refute Constraint.satisfies?("~> 0.1.0", "0.2.0")
      end
    end
  end
end
