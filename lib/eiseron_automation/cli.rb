# frozen_string_literal: true

module EiseronAutomation
  class CLI
    COMMANDS = {
      "release tag" => :release_tag,
      "preview deploy" => :preview_deploy,
      "preview stop" => :preview_stop,
      "preview sweep" => :preview_sweep,
      "docs publish" => :docs_publish,
      "go lint" => :go_lint,
      "tofu lint" => :tofu_lint,
      "prod deploy" => :prod_deploy,
      "prod setup" => :prod_setup,
      "prod backup" => :prod_backup,
      "prod tenant" => :prod_tenant,
      "prod upload" => :prod_upload,
      "prod trigger" => :prod_trigger,
      "db backup" => :db_backup,
      "db backup schedule" => :db_backup_schedule,
      "db backup healthcheck" => :db_backup_healthcheck,
      "db restore-drill" => :db_restore_drill
    }.freeze

    def initialize(argv, env: ENV, io: $stdout, err: $stderr)
      @argv = argv
      @env = env
      @io = io
      @err = err
    end

    def run
      dispatch
      0
    rescue Error => e
      @err.puts "FATAL: #{e.message}"
      1
    end

    private

    def dispatch
      handler = COMMANDS[@argv.join(" ")]
      raise Error, unknown_command unless handler

      send(handler)
    end

    def unknown_command
      "unknown command '#{@argv.join(' ')}'. Available: #{COMMANDS.keys.join(', ')}"
    end

    def release_tag
      token = require_env("RELEASE_TOKEN")
      client = GitlabClient.new(
        api_url: require_env("CI_API_V4_URL"),
        project_id: require_env("CI_PROJECT_ID"),
        token: token
      )
      release = Release.new(client: client, commit_sha: require_env("CI_COMMIT_SHA"), io: @io)
      release.tag_from_file(@env.fetch("VERSION_FILE", "VERSION"))
    end

    def preview_deploy = Preview.new(env: @env, io: @io).deploy
    def preview_stop = Preview.new(env: @env, io: @io).stop
    def preview_sweep = Preview.new(env: @env, io: @io).sweep
    def docs_publish = Docs.new(env: @env, io: @io).publish
    def go_lint = GoLint.new(io: @io).run
    def tofu_lint = TofuLint.new(io: @io).run
    def prod_deploy = Prod::Deploy.new(env: @env, io: @io).deploy
    def prod_setup = Prod::Deploy.new(env: @env, io: @io).setup
    def prod_backup = Prod::Deploy.new(env: @env, io: @io).backup
    def prod_tenant = Prod::Tenant.new(env: @env, io: @io).create
    def prod_upload = Prod::Upload.new(env: @env, io: @io).run
    def prod_trigger = Prod::Trigger.new(env: @env, io: @io).run
    def db_backup = DB::Backup.new(env: @env, io: @io).run
    def db_backup_schedule = DB::Schedule.new(env: @env, io: @io).run
    def db_backup_healthcheck = DB::Healthcheck.new(env: @env, io: @io).run
    def db_restore_drill = DB::RestoreDrill.new(env: @env, io: @io).run

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end
  end
end
