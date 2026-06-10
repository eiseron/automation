# frozen_string_literal: true

require "erb"

module EiseronAutomation
  module Prod
    class Tenant
      SLUG = /\A[a-z][a-z0-9_]{0,62}\z/

      def initialize(env: ENV, io: $stdout, runner: Runner.new)
        @env = env
        @io = io
        @runner = runner
      end

      def create
        @runner.run_stdin(create_sql, @env.to_h, *psql_over_ssh)
        @io.puts "Tenant #{slug} ready (role #{slug}, database #{database})."
      end

      def ensure_password
        @runner.run_stdin(alter_sql, @env.to_h, *psql_over_ssh)
        @io.puts "Ensured #{slug} role password matches the managed secret."
      end

      def database_url
        scheme = @env.fetch("DB_URL_SCHEME", "ecto")
        host = @env.fetch("PG_CONTAINER", "platform-db")
        "#{scheme}://#{slug}:#{ERB::Util.url_encode(password)}@#{host}/#{database}"
      end

      private

      def create_sql
        <<~SQL
          SET standard_conforming_strings = on;
          SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', '#{slug}', #{literal})
          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{slug}')\\gexec
          SELECT format('CREATE DATABASE %I OWNER %I', '#{database}', '#{slug}')
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '#{database}')\\gexec
        SQL
      end

      def alter_sql
        <<~SQL
          SET standard_conforming_strings = on;
          SELECT format('ALTER ROLE %I PASSWORD %L', '#{slug}', #{literal})\\gexec
        SQL
      end

      def literal
        "'#{password.gsub("'", "''")}'"
      end

      def password
        require_env("PROD_TENANT_PASSWORD")
      end

      def database
        "#{slug}_prod"
      end

      def psql_over_ssh
        host = require_env("PROD_HOST")
        user = @env.fetch("DEPLOY_SSH_USER", "deploy")
        container = @env.fetch("PG_CONTAINER", "platform-db")
        admin = @env.fetch("PG_ADMIN_USER", "eiseron")
        ["ssh", "#{user}@#{host}", "docker", "exec", "-i", container,
         "psql", "-U", admin, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-f", "-"]
      end

      def slug
        value = require_env("PROD_TENANT_SLUG")
        raise Error, "PROD_TENANT_SLUG '#{value}' is not a valid postgres identifier" unless value.match?(SLUG)

        value
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
