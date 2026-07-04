# frozen_string_literal: true

module EiseronAutomation
  class CLI
    COMMANDS = {
      "release tag" => :release_tag,
      "preview trigger" => :preview_trigger,
      "preview pages-trigger" => :preview_pages_trigger,
      "preview dispatch" => :preview_dispatch,
      "preview deploy" => :preview_deploy,
      "preview stop" => :preview_stop,
      "preview sweep" => :preview_sweep,
      "docs publish" => :docs_publish,
      "go lint" => :go_lint,
      "tofu lint" => :tofu_lint,
      "prod deploy" => :prod_deploy,
      "prod setup" => :prod_setup,
      "prod backup" => :prod_backup,
      "prod restore" => :prod_restore,
      "prod tenant" => :prod_tenant,
      "prod upload" => :prod_upload,
      "prod trigger" => :prod_trigger,
      "db backup" => :db_backup,
      "db restore" => :db_restore,
      "db backup schedule" => :db_backup_schedule,
      "db backup healthcheck" => :db_backup_healthcheck,
      "db backup verify" => :db_backup_verify,
      "db restore-drill" => :db_restore_drill,
      "ci init" => :ci_init,
      "ci install" => :ci_install,
      "ci update" => :ci_update,
      "ci check" => :ci_check,
      "ci coverage-gate" => :ci_coverage_gate,
      "observability deploy" => :observability_deploy,
      "notify ci-failure" => :notify_ci_failure,
      "cf import-otp-idp" => :cf_import_otp_idp
    }.freeze

    ARG_COMMANDS = ["ci update", "ci coverage-gate"].freeze

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
      raise Error, unknown_command unless command_name

      @args = @argv.drop(command_name.split.length)
      send(COMMANDS[command_name])
    end

    def command_name
      @command_name ||= resolve_command
    end

    def resolve_command
      joined = @argv.join(" ")
      return joined if COMMANDS.key?(joined)

      ARG_COMMANDS.select { |key| joined.start_with?("#{key} ") }.max_by(&:length)
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

    def preview_trigger = PreviewTrigger.new(env: @env, io: @io).run
    def preview_pages_trigger = PreviewPagesTrigger.new(env: @env, io: @io).run
    def preview_dispatch = PreviewDispatch.new(env: @env, io: @io).run
    def preview_deploy = Preview::Deploy.new(env: @env, io: @io).run
    def preview_stop = Preview::Stop.new(env: @env, io: @io).run
    def preview_sweep = Preview::Sweep.new(env: @env, io: @io).run
    def docs_publish = Docs.new(env: @env, io: @io).publish
    def go_lint = GoLint.new(io: @io).run
    def tofu_lint = TofuLint.new(io: @io).run
    def prod_deploy = Prod::Deploy.new(env: @env, io: @io).deploy
    def prod_setup = Prod::Deploy.new(env: @env, io: @io).setup
    def prod_backup = Prod::Deploy.new(env: @env, io: @io).backup
    def prod_restore = Prod::Restore.new(env: @env, io: @io).run
    def prod_tenant = Prod::Tenant.new(env: @env, io: @io).create
    def prod_upload = Prod::Upload.new(env: @env, io: @io).run
    def prod_trigger = Prod::Trigger.new(env: @env, io: @io).run
    def db_backup = DB::Backup.new(env: @env, io: @io).run
    def db_restore = DB::Restore.new(env: @env, io: @io).run
    def db_backup_schedule = DB::Schedule.new(env: @env, io: @io).run
    def db_backup_healthcheck = DB::Healthcheck.new(env: @env, io: @io).run
    def db_backup_verify = DB::Verify.new(env: @env, io: @io).run
    def db_restore_drill = DB::RestoreDrill.new(env: @env, io: @io).run

    def ci_init = CI::Lock.build(env: @env, io: @io).init
    def ci_install = CI::Lock.build(env: @env, io: @io).install
    def ci_update = CI::Lock.build(env: @env, io: @io).update(@args)
    def ci_check = CI::Lock.build(env: @env, io: @io).check
    def ci_coverage_gate = CI::CoverageGate.new(env: @env, io: @io, err: @err, args: @args).run

    def observability_deploy = Observability::Deploy.new(env: @env, io: @io).deploy
    def notify_ci_failure = Notify::CIFailure.new(env: @env, io: @io, err: @err).run

    def cf_import_otp_idp
      cf_client = CloudflareClient.new(token: require_env("TF_VAR_cloudflare_api_token"))
      OtpIdp.new(cf_client: cf_client, account_id: require_env("TF_VAR_cloudflare_account_id"), io: @io).import
    end

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end
  end
end
