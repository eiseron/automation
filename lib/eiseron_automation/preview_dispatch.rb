# frozen_string_literal: true

module EiseronAutomation
  class PreviewDispatch
    ACTIONS = %w[deploy stop sweep].freeze

    def initialize(env: ENV, io: $stdout, runner: Runner.new)
      @env = env
      @io = io
      @runner = runner
    end

    def run
      action = require_in("PREVIEW_ACTION", ACTIONS)
      cmd = command_for(action)
      @io.puts "preview action=#{action} → #{cmd.join(' ')}"
      @runner.run(@env.to_h, *cmd)
    end

    private

    def command_for(action)
      script = "#{deployer_path}/#{action}.sh"
      case action
      when "deploy" then [script, require_env("PREVIEW_REF"), require_env("PREVIEW_SHA"), mr_iid]
      when "stop"   then [script, require_env("PREVIEW_REF")]
      when "sweep"  then [script]
      end
    end

    def mr_iid
      @env.fetch("PREVIEW_MR_IID", "")
    end

    def deployer_path
      @env.fetch("PREVIEW_DEPLOYER_PATH", "deployer")
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
