# frozen_string_literal: true

require "test_helper"

class GemspecDependenciesTest < Minitest::Test
  def test_base64_is_a_declared_runtime_dependency
    spec = Gem::Specification.load(File.expand_path("../eiseron_automation.gemspec", __dir__))
    runtime = spec.dependencies.select { |dependency| dependency.type == :runtime }.map(&:name)

    assert_includes runtime, "base64"
  end
end
