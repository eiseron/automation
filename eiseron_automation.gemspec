# frozen_string_literal: true

require_relative "lib/eiseron_automation/version"

Gem::Specification.new do |spec|
  spec.name = "eiseron_automation"
  spec.version = EiseronAutomation::VERSION
  spec.authors = ["Eiseron"]
  spec.email = ["guilherme@eiseron.com"]

  spec.summary = "Reusable Ruby automation toolkit for Eiseron CI and ops"
  spec.description = "Shared automations (starting with release tagging) used across Eiseron CI and ops pipelines."
  spec.homepage = "https://gitlab.com/eiseron/stack/automation"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "VERSION", "README.md", "LICENSE"]
  spec.bindir = "bin"
  spec.executables = ["eiseron"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "mime-types", "~> 3.0"

  spec.add_development_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.87"
end
