# frozen_string_literal: true

require "base64"
require "securerandom"

module EiseronAutomation
  module Preview
    class Deploy
      HEALTHCHECK_DEADLINE_SECONDS = 90
      HEALTHCHECK_INTERVAL_SECONDS = 3

      DEFAULT_SLEEPER = ->(s) { sleep(s) }
      DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      def initialize(env: ENV, io: $stdout, ssh: nil, registry: nil, runner: Runner.new,
                     sleeper: DEFAULT_SLEEPER, clock: DEFAULT_CLOCK)
        @env = env
        @io = io
        @ssh = ssh
        @registry = registry
        @runner = runner
        @sleeper = sleeper
        @clock = clock
        @app_password = SecureRandom.hex(32)
        @admin_password = SecureRandom.hex(32)
      end

      def run
        @io.puts "[deploy] project=#{project} ref=#{ref} kind=#{kind}"
        write_docker_auth
        pull_image
        stop_previous
        ensure_shared_roles
        recreate_per_mr_role_and_db
        run_migrations
        bring_up_compose
        await_healthcheck
        release_registry_tag
      end

      private

      def write_docker_auth
        auth = Base64.strict_encode64("#{require_env('PREVIEW_IMAGE_PULL_USER')}:#{require_env('PREVIEW_IMAGE_PULL_TOKEN')}")
        ssh.bash <<~BASH
          set -euo pipefail
          mkdir -p /root/.docker
          chmod 700 /root/.docker
          cat >/root/.docker/config.json <<'JSON'
          {"auths":{"registry.gitlab.com":{"auth":"#{auth}"}}}
          JSON
          chmod 600 /root/.docker/config.json
        BASH
      end

      def pull_image
        ssh.run("docker pull #{image}")
      end

      def stop_previous
        ssh.run("docker compose -p #{project} -f ~/previews/#{project}/compose.yml down --remove-orphans 2>/dev/null || true")
      end

      def ensure_shared_roles
        ssh.bash <<~BASH
          set -euo pipefail
          docker exec -i #{db_container} psql -U #{shared_user} -d postgres -v ON_ERROR_STOP=1 <<'SQL'
          DO $$
          BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{shared_admin_role}') THEN
              CREATE ROLE #{shared_admin_role} NOLOGIN BYPASSRLS;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{shared_app_role}') THEN
              CREATE ROLE #{shared_app_role} NOLOGIN;
            END IF;
            IF NOT EXISTS (
              SELECT 1 FROM pg_auth_members am
              JOIN pg_roles r1 ON am.member = r1.oid
              JOIN pg_roles r2 ON am.roleid = r2.oid
              WHERE r1.rolname = '#{shared_admin_role}' AND r2.rolname = '#{shared_app_role}'
            ) THEN
              GRANT #{shared_app_role} TO #{shared_admin_role};
            END IF;
          END
          $$;
          SQL
        BASH
      end

      def recreate_per_mr_role_and_db
        ssh.bash <<~BASH
          set -euo pipefail
          for i in $(seq 1 15); do
            if docker exec #{db_container} pg_isready -U #{shared_user} >/dev/null 2>&1; then
              break
            fi
            echo "[deploy] waiting for #{db_container} (attempt $i/15)..."
            sleep 4
          done
          docker exec #{db_container} pg_isready -U #{shared_user} || { echo "[deploy] #{db_container} not ready after 60s"; exit 1; }
          docker exec #{db_container} psql -U #{shared_user} -d postgres -c 'DROP DATABASE IF EXISTS "#{db_name}" WITH (FORCE);'
          docker exec #{db_container} psql -U #{shared_user} -d postgres -c 'DROP ROLE IF EXISTS "#{app_role}";'
          docker exec #{db_container} psql -U #{shared_user} -d postgres -c 'DROP ROLE IF EXISTS "#{admin_role}";'
          docker exec -i #{db_container} psql -U #{shared_user} -d postgres <<'SQL'
          CREATE ROLE "#{app_role}"   LOGIN PASSWORD '#{@app_password}';
          CREATE ROLE "#{admin_role}" LOGIN BYPASSRLS PASSWORD '#{@admin_password}';
          GRANT #{shared_app_role}   TO "#{app_role}";
          GRANT #{shared_admin_role} TO "#{admin_role}";
          CREATE DATABASE "#{db_name}" OWNER "#{admin_role}";
          REVOKE ALL ON DATABASE "#{db_name}" FROM PUBLIC;
          GRANT CONNECT ON DATABASE "#{db_name}" TO "#{app_role}", "#{admin_role}";
          SQL
          docker exec -i #{db_container} psql -U #{shared_user} -d "#{db_name}" -v ON_ERROR_STOP=1 <<'SQL'
          GRANT USAGE ON SCHEMA public TO "#{app_role}";
          ALTER DEFAULT PRIVILEGES FOR ROLE "#{admin_role}" IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "#{app_role}";
          ALTER DEFAULT PRIVILEGES FOR ROLE "#{admin_role}" IN SCHEMA public
            GRANT USAGE, SELECT ON SEQUENCES TO "#{app_role}";
          SQL
        BASH
      end

      def run_migrations
        ssh.bash <<~BASH
          set -euo pipefail
          docker run --rm \\
              --network #{db_network} \\
              -e DB_HOST=#{db_container} \\
              -e DB_USER='#{admin_role}' \\
              -e DB_PASS='#{@admin_password}' \\
              -e DB_NAME='#{db_name}' \\
              -e DATABASE_URL='#{db_url_scheme}://#{admin_role}:#{@admin_password}@#{db_container}/#{db_name}' \\
              -e MIX_ENV=#{mix_env} \\
              -e SECRET_KEY_BASE='#{secret_key_base}' \\
              "#{image}" \\
              #{migrate_command}
        BASH
      end

      def bring_up_compose
        compose_yml = File.read(compose_template_path)
        ssh.bash <<~BASH
          set -euo pipefail
          #{compose_env_exports}
          mkdir -p ~/previews/#{project}
          cat >~/previews/#{project}/compose.yml <<'COMPOSE_EOF'
          #{compose_yml}
          COMPOSE_EOF
          docker compose -p "#{project}" -f ~/previews/#{project}/compose.yml up -d
        BASH
      end

      def compose_env_exports
        {
          "PREVIEW_REF" => ref,
          "PREVIEW_SHA" => require_env("PREVIEW_SHA"),
          "PREVIEW_MR_IID" => @env.fetch("PREVIEW_MR_IID", ""),
          "PREVIEW_KIND" => kind,
          "PREVIEW_IMAGE_REPO" => require_env("PREVIEW_IMAGE_REPO"),
          "PREVIEW_DOMAIN_BASE" => require_env("PREVIEW_DOMAIN_BASE"),
          "MR_PG_DB" => db_name,
          "MR_PG_APP_USER" => app_role,
          "MR_PG_APP_PASSWORD" => @app_password,
          "PREVIEW_SECRET_KEY_BASE" => secret_key_base
        }.map { |k, v| "export #{k}=#{shell_quote(v)}" }.join("\n")
      end

      def shell_quote(value)
        "'#{value.to_s.gsub("'", %q('"'"'))}'"
      end

      def await_healthcheck
        @io.puts "[deploy] waiting for #{health_url} (HTTP 200)"
        deadline = @clock.call + HEALTHCHECK_DEADLINE_SECONDS
        while @clock.call < deadline
          return @io.puts "[deploy] healthcheck ok" if healthy?

          @sleeper.call(HEALTHCHECK_INTERVAL_SECONDS)
        end
        dump_diagnostics
        raise Error, "healthcheck timed out after #{HEALTHCHECK_DEADLINE_SECONDS}s waiting for #{health_url}"
      end

      def dump_diagnostics
        diagnostics.dump
      rescue Error => e
        @io.puts "[deploy] diagnostics unavailable: #{e.message}"
      end

      def diagnostics
        Diagnostics.new(
          io: @io, ssh: ssh, project: project, container: container,
          host: "#{ref}-#{require_env('PREVIEW_DOMAIN_BASE')}",
          health_path: health_path, port: 4000
        )
      end

      def container
        "#{project}-#{service}-1"
      end

      def healthy?
        output = @runner.capture(
          "curl", "-sS", "-o", File::NULL, "-w", "%{http_code}", # rubocop:disable Style/FormatStringToken
          "-H", "CF-Access-Client-Id: #{require_env('PREVIEW_HEALTHCHECK_TOKEN_ID')}",
          "-H", "CF-Access-Client-Secret: #{require_env('PREVIEW_HEALTHCHECK_TOKEN_SECRET')}",
          health_url
        )
        output.strip == "200"
      rescue Error
        false
      end

      def release_registry_tag
        if ssh_runs?("docker image inspect #{image} >/dev/null 2>&1")
          registry.delete_preview_tag(ref)
        else
          @io.puts "[deploy] WARN: image #{image} not present on host; keeping registry tag for next pull"
        end
      end

      def ssh_runs?(remote_cmd)
        ssh.run(remote_cmd)
        true
      rescue Error
        false
      end

      def ssh
        @ssh ||= SshSession.new(env: @env, runner: @runner)
      end

      def registry
        @registry ||= Registry.new(env: @env, io: @io)
      end

      def project = Names.project(kind, ref)
      def db_name = Names.db(app, ref)
      def app_role = Names.app_role(app, ref)
      def admin_role = Names.admin_role(app, ref)
      def shared_app_role = Names.shared_app_role(app)
      def shared_admin_role = Names.shared_admin_role(app)
      def image = "#{require_env('PREVIEW_IMAGE_REPO')}:#{ref}"
      def health_url = "https://#{ref}-#{require_env('PREVIEW_DOMAIN_BASE')}#{health_path}"
      def app = @env.fetch("EISERON_PREVIEW_APP_NAME") { require_env("PROD_SLUG") }
      def ref = require_env("PREVIEW_REF")
      def kind = require_in("PREVIEW_KIND", %w[mr main])
      def shared_user = require_env("SHARED_PG_USER")
      def secret_key_base = require_env("PREVIEW_SECRET_KEY_BASE")
      def mix_env = @env.fetch("EISERON_PREVIEW_MIX_ENV", "preview")
      def db_container = @env.fetch("EISERON_PREVIEW_DB_CONTAINER", "shared-pg")
      def db_network = @env.fetch("EISERON_PREVIEW_DB_NETWORK", "postgres")
      def db_url_scheme = @env.fetch("EISERON_PREVIEW_DB_URL_SCHEME", "ecto")
      def health_path = @env.fetch("EISERON_PREVIEW_HEALTH_PATH", "/healthz")
      def service = @env.fetch("EISERON_PREVIEW_SERVICE", app)

      def migrate_command
        @env.fetch("EISERON_PREVIEW_MIGRATE_COMMAND") { default_migrate_command }
      end

      def default_migrate_command
        release_module = @env["PROD_RELEASE_MODULE"].to_s
        return "mix ecto.migrate" if release_module.empty?

        "mix run --no-start -e '#{release_module}.Release.setup'"
      end

      def compose_template_path = require_env("EISERON_PREVIEW_COMPOSE_TEMPLATE")

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
end
