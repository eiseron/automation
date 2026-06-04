# frozen_string_literal: true

require "English"
require "cgi"
require "json"

module EiseronAutomation
  module PreviewPlan
    module_function

    def deploy_name(app, iid, suffix)
      "#{app}-mr-#{iid}#{suffix}"
    end

    def database_name(tenant, iid)
      "#{tenant}_mr#{iid}"
    end

    def database_url(dsn:, tenant:, password:, database:)
      scheme, authority = dsn.split("://", 2)
      "#{scheme}://#{tenant}:#{CGI.escape(password)}@#{authority}/#{database}"
    end

    def app_env(database_url, extra_json)
      extra = extra_json.to_s.empty? ? {} : JSON.parse(extra_json)
      JSON.generate({ "DATABASE_URL" => database_url }.merge(extra))
    end

    def deployed_iids(names, app, suffix)
      matcher = /\A#{Regexp.escape(app)}-mr-(\d+)#{Regexp.escape(suffix)}\z/
      names.filter_map { |name| matcher.match(name.strip)&.captures&.first }
    end

    def stale_iids(deployed, open)
      deployed - open
    end
  end

  class PreviewRunner
    def run(env, *cmd)
      system(env, *cmd) || raise(Error, "command failed: #{cmd.join(' ')}")
    end

    def capture(*cmd)
      output = IO.popen(cmd, &:read)
      raise(Error, "command failed: #{cmd.join(' ')}") unless $CHILD_STATUS.success?

      output
    end
  end

  class Preview
    PLAYBOOK = "eiseron.provisioning.preview_app"

    def initialize(env: ENV, io: $stdout, runner: PreviewRunner.new, client: nil)
      @env = env
      @io = io
      @runner = runner
      @client = client
    end

    def deploy
      vars = deploy_vars(require_env("PREVIEW_MR_IID"))
      @io.puts "Deploying #{vars['PREVIEW_APP_NAME']} -> #{vars['PREVIEW_APP_HOST']}"
      run_playbook(vars)
    end

    def stop
      teardown(require_env("PREVIEW_MR_IID"))
    end

    def sweep
      names = @runner.capture(*ssh_command("docker ps -a --format '{{.Names}}'")).split("\n")
      stale = PreviewPlan.stale_iids(PreviewPlan.deployed_iids(names, app, suffix), client.open_merge_request_iids)
      @io.puts(stale.empty? ? "No stale previews to sweep." : "Sweeping: #{stale.join(', ')}")
      stale.each { |iid| teardown(iid) }
    end

    private

    def teardown(iid)
      name = PreviewPlan.deploy_name(app, iid, suffix)
      database = PreviewPlan.database_name(tenant, iid)
      @io.puts "Tearing down #{name} (MR !#{iid})"
      run_playbook(app_vars(state: "absent", name: name, database: database))
    end

    def deploy_vars(iid)
      name = PreviewPlan.deploy_name(app, iid, suffix)
      database = PreviewPlan.database_name(tenant, iid)
      app_vars(state: "present", name: name, database: database).merge(runtime_vars(name, database))
    end

    def runtime_vars(name, database)
      {
        "PREVIEW_APP_HOST" => "#{name}.#{zone}",
        "PREVIEW_APP_IMAGE" => require_env("PREVIEW_APP_IMAGE"),
        "PREVIEW_APP_PORT" => app_port,
        "PREVIEW_APP_ENV" => PreviewPlan.app_env(database_url(database), @env["PREVIEW_APP_EXTRA_ENV"])
      }
    end

    def database_url(database)
      PreviewPlan.database_url(
        dsn: "#{db_scheme}://#{db_host}:#{db_port}",
        tenant: tenant, password: tenant_password, database: database
      )
    end

    def app_vars(state:, name:, database:)
      {
        "PREVIEW_APP_STATE" => state,
        "PREVIEW_APP_NAME" => name,
        "PREVIEW_APP_DB_NAME" => database,
        "PREVIEW_TENANT_NAME" => tenant
      }
    end

    def run_playbook(vars)
      @runner.run(@env.to_h.merge(vars), "ansible-playbook", "-i", "#{host_ip},", PLAYBOOK)
    end

    def ssh_command(remote)
      [
        "ssh", "-i", require_env("ANSIBLE_PRIVATE_KEY_FILE"),
        "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
        "-o", "BatchMode=yes", "deploy@#{host_ip}", remote
      ]
    end

    def client
      @client ||= GitlabClient.new(
        api_url: require_env("CI_API_V4_URL"),
        project_id: CGI.escape(require_env("EISERON_PREVIEW_SCAN_PROJECT")),
        token: require_env("PREVIEW_SWEEP_TOKEN")
      )
    end

    def app = require_env("EISERON_PREVIEW_APP")
    def suffix = @env.fetch("EISERON_PREVIEW_SUFFIX", "")
    def zone = require_env("EISERON_PREVIEW_ZONE")
    def app_port = @env.fetch("EISERON_PREVIEW_PORT", "4000")
    def db_scheme = @env.fetch("EISERON_PREVIEW_DB_SCHEME", "postgresql")
    def db_host = @env.fetch("EISERON_PREVIEW_DB_HOST", "shared-pg")
    def db_port = @env.fetch("EISERON_PREVIEW_DB_PORT", "5432")
    def host_ip = require_env("PREVIEW_HOST_IP")
    def tenant = require_env("PREVIEW_TENANT_NAME")
    def tenant_password = require_env("PREVIEW_TENANT_PASSWORD")

    def require_env(name)
      value = @env[name].to_s
      raise Error, "#{name} is empty" if value.empty?

      value
    end
  end
end
