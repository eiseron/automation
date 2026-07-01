# frozen_string_literal: true

module EiseronAutomation
  class PreviewDispatch
    ACTIONS = %w[deploy stop sweep].freeze

    def initialize(env: ENV, io: $stdout, runner: Runner.new, handlers: nil)
      @env = env
      @io = io
      @runner = runner
      @handlers = handlers
    end

    def run
      action = require_in("PREVIEW_ACTION", ACTIONS)
      kind = @env.fetch("PREVIEW_KIND", "")
      @io.puts "preview action=#{action} kind=#{kind}"
      return Preview::Pages.new(env: @env, io: @io, runner: @runner).run if kind == "pages"

      handlers.fetch(action).call
    end

    private

    def handlers
      @handlers ||= {
        "deploy" => -> { Preview::Deploy.new(env: @env, io: @io, runner: @runner).run },
        "stop" => -> { Preview::Stop.new(env: @env, io: @io, runner: @runner).run },
        "sweep" => -> { Preview::Sweep.new(env: @env, io: @io, runner: @runner).run }
      }
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
