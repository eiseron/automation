# frozen_string_literal: true

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
        slug = tenant_slug
        password = require_env("PROD_TENANT_PASSWORD")
        db = "#{slug}_prod"

        @runner.run_stdin(provision_sql(slug, db, password), @env.to_h, *psql_over_ssh)
        @io.puts "Tenant #{slug} ready (role #{slug}, database #{db})."
      end

      private

      def provision_sql(slug, db, password)
        literal = "'#{password.gsub("'", "''")}'"
        <<~SQL
          SET standard_conforming_strings = on;
          SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', '#{slug}', #{literal})
          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{slug}')\\gexec
          SELECT format('CREATE DATABASE %I OWNER %I', '#{db}', '#{slug}')
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '#{db}')\\gexec
        SQL
      end

      def psql_over_ssh
        host = require_env("PROD_HOST")
        user = @env.fetch("DEPLOY_SSH_USER", "deploy")
        container = @env.fetch("PG_CONTAINER", "platform-db")
        admin = @env.fetch("PG_ADMIN_USER", "eiseron")
        ["ssh", "#{user}@#{host}", "docker", "exec", "-i", container,
         "psql", "-U", admin, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-f", "-"]
      end

      def tenant_slug
        slug = require_env("PROD_TENANT_SLUG")
        raise Error, "PROD_TENANT_SLUG '#{slug}' is not a valid postgres identifier" unless slug.match?(SLUG)

        slug
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
