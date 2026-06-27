# frozen_string_literal: true

require "cgi"

module EiseronAutomation
  class PreviewTrigger
    KINDS = %w[mr main].freeze
    ACTIONS = %w[deploy stop].freeze

    def initialize(env: ENV, io: $stdout, client: nil)
      @env = env
      @io = io
      @client = client
    end

    def run
      action = require_in("PREVIEW_TRIGGER_ACTION", ACTIONS)
      kind = require_in("PREVIEW_TRIGGER_KIND", KINDS)
      ref = require_env("PREVIEW_TRIGGER_REF")
      result = client.trigger_pipeline(
        trigger_token: require_env("PREVIEW_DEPLOYER_TRIGGER_TOKEN"),
        ref: deployer_ref,
        variables: variables(action: action, kind: kind, ref: ref)
      )
      @io.puts "Downstream pipeline: #{result['web_url']}"
    end

    private

    def variables(action:, kind:, ref:)
      base = {
        "PREVIEW_ACTION" => action,
        "PREVIEW_KIND" => kind,
        "PREVIEW_REF" => ref,
        "PREVIEW_IMAGE_REPO" => "#{require_env('CI_REGISTRY_IMAGE')}/preview",
        "PREVIEW_SHA" => require_env("CI_COMMIT_SHA")
      }
      iid = mr_iid(kind)
      iid.empty? ? base : base.merge("PREVIEW_MR_IID" => iid)
    end

    def mr_iid(kind)
      iid = @env.fetch("PREVIEW_TRIGGER_MR_IID", "")
      return iid unless kind == "mr" && iid.empty?

      raise Error, "PREVIEW_TRIGGER_MR_IID is required when PREVIEW_TRIGGER_KIND=mr"
    end

    def deployer_ref
      @env.fetch("PREVIEW_DEPLOYER_REF", "main")
    end

    def client
      @client ||= GitlabClient.new(
        api_url: require_env("CI_API_V4_URL"),
        project_id: CGI.escape(require_env("PREVIEW_DEPLOYER_PROJECT")),
        token: ""
      )
    end

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end

    def require_in(name, allowed)
      value = require_env(name)
      return value if allowed.include?(value)

      raise Error, "#{name}='#{value}' is not one of: #{allowed.join(', ')}"
    end
  end
end
