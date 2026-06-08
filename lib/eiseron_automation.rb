# frozen_string_literal: true

require_relative "eiseron_automation/version"
require_relative "eiseron_automation/gitlab_client"
require_relative "eiseron_automation/release"
require_relative "eiseron_automation/preview"
require_relative "eiseron_automation/docs"
require_relative "eiseron_automation/go_lint"
require_relative "eiseron_automation/tofu_lint"
require_relative "eiseron_automation/prod/plan"
require_relative "eiseron_automation/prod/runner"
require_relative "eiseron_automation/prod/deploy"
require_relative "eiseron_automation/prod/upload"
require_relative "eiseron_automation/prod/trigger"
require_relative "eiseron_automation/cli"

module EiseronAutomation
  class Error < StandardError; end
end
