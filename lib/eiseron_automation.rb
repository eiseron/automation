# frozen_string_literal: true

require_relative "eiseron_automation/version"
require_relative "eiseron_automation/gitlab_client"
require_relative "eiseron_automation/release"
require_relative "eiseron_automation/preview"
require_relative "eiseron_automation/cli"

# Reusable Ruby automation toolkit shared across Eiseron CI and ops.
module EiseronAutomation
  class Error < StandardError; end
end
