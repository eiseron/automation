# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdTenantTest < Minitest::Test
    class FakeRunner
      attr_reader :calls, :captures

      def initialize(primary: "platform-db-1")
        @calls = []
        @captures = []
        @primary = primary
      end

      def run_stdin(input, _env, *cmd)
        @calls << { sql: input, cmd: cmd }
      end

      def capture(*cmd)
        @captures << cmd
        @primary
      end
    end

    def env(over = {})
      { "PROD_TENANT_SLUG" => "app", "PROD_TENANT_PASSWORD" => "s3cr3t" }.merge(over)
    end

    def tenant(runner, vars)
      Prod::Tenant.new(env: vars, io: StringIO.new, runner: runner)
    end

    def test_create_execs_psql_on_the_cnpg_primary_pod
      runner = FakeRunner.new
      tenant(runner, env).create
      cmd = runner.calls.fetch(0)[:cmd]
      assert_equal(["kubectl", "exec", "-i", "-n", "platform", "platform-db-1", "--",
                    "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-f", "-"], cmd)
    end

    def test_create_provisions_role_and_database_via_stdin
      runner = FakeRunner.new
      tenant(runner, env).create
      sql = runner.calls.fetch(0)[:sql]
      assert_match(/format\('CREATE ROLE %I LOGIN PASSWORD %L', 'app', 's3cr3t'\)/, sql)
    end

    def test_create_provisions_the_database_owned_by_the_role
      runner = FakeRunner.new
      tenant(runner, env).create
      assert_match(/format\('CREATE DATABASE %I OWNER %I', 'app_prod', 'app'\)/, runner.calls.fetch(0)[:sql])
    end

    def test_primary_pod_is_resolved_by_the_cnpg_primary_role_label
      runner = FakeRunner.new
      tenant(runner, env).ensure_password
      selector = runner.captures.fetch(0)
      assert_includes selector, "cnpg.io/cluster=platform-db,cnpg.io/instanceRole=primary"
    end

    def test_no_primary_pod_raises_rather_than_targeting_a_replica
      runner = FakeRunner.new(primary: "")
      error = assert_raises(Error) { tenant(runner, env).ensure_password }
      assert_match(/no primary pod found/, error.message)
    end

    def test_ensure_password_alters_the_role_to_the_managed_secret
      runner = FakeRunner.new
      tenant(runner, env).ensure_password
      assert_match(/format\('ALTER ROLE %I PASSWORD %L', 'app', 's3cr3t'\)/, runner.calls.fetch(0)[:sql])
    end

    def test_ensure_password_does_not_create_roles_or_databases
      runner = FakeRunner.new
      tenant(runner, env).ensure_password
      refute_match(/CREATE (ROLE|DATABASE)/, runner.calls.fetch(0)[:sql])
    end

    def test_password_with_quote_backslash_and_dollar_tag_stays_a_sql_literal
      runner = FakeRunner.new
      tenant(runner, env("PROD_TENANT_PASSWORD" => "pa\\tss'w$do$rd")).ensure_password
      assert_includes runner.calls.fetch(0)[:sql], "ALTER ROLE %I PASSWORD %L', 'app', 'pa\\tss''w$do$rd')"
    end

    def test_password_never_reaches_the_command_arguments
      runner = FakeRunner.new
      tenant(runner, env("PROD_TENANT_PASSWORD" => "pa\\tss'w$do$rd")).ensure_password
      refute(runner.calls.fetch(0)[:cmd].any? { |arg| arg.include?("pa") })
    end

    def test_database_url_carries_the_managed_password_against_the_rw_service
      url = tenant(FakeRunner.new, env).database_url
      assert_equal "ecto://app:s3cr3t@platform-db-rw.platform/app_prod", url
    end

    def test_database_url_percent_encodes_a_password_with_url_metacharacters
      url = tenant(FakeRunner.new, env("PROD_TENANT_PASSWORD" => "p@ss:w/rd")).database_url
      assert_equal "ecto://app:p%40ss%3Aw%2Frd@platform-db-rw.platform/app_prod", url
    end

    def test_database_url_percent_encodes_space_and_plus_so_userinfo_is_unambiguous
      url = tenant(FakeRunner.new, env("PROD_TENANT_PASSWORD" => "a b+c")).database_url
      assert_equal "ecto://app:a%20b%2Bc@platform-db-rw.platform/app_prod", url
    end

    def test_database_url_honours_scheme_and_host_overrides
      url = tenant(FakeRunner.new, env("DB_URL_SCHEME" => "postgres", "PG_HOST" => "pg")).database_url
      assert_equal "postgres://app:s3cr3t@pg/app_prod", url
    end

    def test_database_url_carries_the_tenant_role_not_the_admin
      url = tenant(FakeRunner.new, env("PG_ADMIN_USER" => "eiseron")).database_url
      refute_includes url, "eiseron"
    end

    def test_psql_targets_the_admin_user_override
      runner = FakeRunner.new
      tenant(runner, env("PG_ADMIN_USER" => "eiseron")).ensure_password
      cmd = runner.calls.fetch(0)[:cmd]
      assert_equal "eiseron", cmd[cmd.index("-U") + 1]
    end

    def test_namespace_and_cluster_overrides_flow_to_the_exec
      runner = FakeRunner.new
      tenant(runner, env("PG_NAMESPACE" => "db", "PG_CLUSTER" => "main-db")).ensure_password
      assert_includes runner.calls.fetch(0)[:cmd], "db"
      assert_includes runner.captures.fetch(0), "cnpg.io/cluster=main-db,cnpg.io/instanceRole=primary"
    end

    def test_rejects_invalid_slug
      runner = FakeRunner.new
      error = assert_raises(Error) { tenant(runner, env("PROD_TENANT_SLUG" => "app;DROP")).create }
      assert_match(/not a valid postgres identifier/, error.message)
      assert_empty runner.calls
    end

    def test_create_requires_slug_and_password
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_SLUG")).create }
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_PASSWORD")).create }
    end

    def test_ensure_password_requires_slug_and_password
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_SLUG")).ensure_password }
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_PASSWORD")).ensure_password }
    end
  end
end
