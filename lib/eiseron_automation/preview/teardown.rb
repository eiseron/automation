# frozen_string_literal: true

module EiseronAutomation
  module Preview
    class Teardown
      def initialize(env:, io:, ssh:, registry:)
        @env = env
        @io = io
        @ssh = ssh
        @registry = registry
      end

      def run(project:, ref:)
        @io.puts "[teardown] project=#{project} ref=#{ref}"
        compose_down(project)
        drop_db_and_roles(ref)
        @registry.delete_preview_tag(ref)
      end

      private

      def compose_down(project)
        @ssh.run(
          "docker compose -p #{project} -f ~/previews/#{project}/compose.yml " \
          "down -v --remove-orphans --rmi all 2>/dev/null || true"
        )
      end

      def drop_db_and_roles(ref)
        db = Names.db(app, ref)
        app_role = Names.app_role(app, ref)
        admin_role = Names.admin_role(app, ref)
        @ssh.bash <<~BASH
          set -euo pipefail
          docker exec #{db_container} psql -U #{shared_user} -d postgres -c 'DROP DATABASE IF EXISTS "#{db}" WITH (FORCE);'
          docker exec #{db_container} psql -U #{shared_user} -d postgres -c 'DROP ROLE IF EXISTS "#{app_role}";'
          docker exec #{db_container} psql -U #{shared_user} -d postgres -c 'DROP ROLE IF EXISTS "#{admin_role}";'
        BASH
      end

      def app
        require_env("EISERON_PREVIEW_APP_NAME")
      end

      def shared_user
        require_env("SHARED_PG_USER")
      end

      def db_container
        @env.fetch("EISERON_PREVIEW_DB_CONTAINER", "shared-pg")
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
