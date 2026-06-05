# frozen_string_literal: true

module EiseronAutomation
  class CLI
    COMMANDS = {
      "release tag" => :release_tag,
      "preview deploy" => :preview_deploy,
      "preview stop" => :preview_stop,
      "preview sweep" => :preview_sweep,
      "docs publish" => :docs_publish,
      "go lint" => :go_lint
    }.freeze

    def initialize(argv, env: ENV, io: $stdout, err: $stderr)
      @argv = argv
      @env = env
      @io = io
      @err = err
    end

    def run
      dispatch([@argv[0], @argv[1]].join(" "))
      0
    rescue Error => e
      @err.puts "FATAL: #{e.message}"
      1
    end

    private

    def dispatch(key)
      handler = COMMANDS[key]
      raise Error, "unknown command '#{key.strip}'. Available: #{COMMANDS.keys.join(', ')}" unless handler

      send(handler)
    end

    def release_tag
      token = require_env("EISERON_STACK_TOKEN")
      client = GitlabClient.new(
        api_url: require_env("CI_API_V4_URL"),
        project_id: require_env("CI_PROJECT_ID"),
        token: token
      )
      release = Release.new(client: client, commit_sha: require_env("CI_COMMIT_SHA"), io: @io)
      release.tag_from_file(@env.fetch("VERSION_FILE", "VERSION"))
    end

    def preview_deploy
      Preview.new(env: @env, io: @io).deploy
    end

    def preview_stop
      Preview.new(env: @env, io: @io).stop
    end

    def preview_sweep
      Preview.new(env: @env, io: @io).sweep
    end

    def docs_publish
      Docs.new(env: @env, io: @io).publish
    end

    def go_lint
      GoLint.new(io: @io).run
    end

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end
  end
end
