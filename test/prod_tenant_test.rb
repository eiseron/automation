# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdTenantTest < Minitest::Test
    class FakeRunner
      attr_reader :calls

      def initialize
        @calls = []
      end

      def run_stdin(input, _env, *cmd)
        @calls << { sql: input, cmd: cmd }
      end
    end

    def env(over = {})
      { "PROD_TENANT_SLUG" => "app", "PROD_TENANT_PASSWORD" => "s3cr3t", "PROD_HOST" => "10.0.0.1" }.merge(over)
    end

    def tenant(runner, vars)
      Prod::Tenant.new(env: vars, io: StringIO.new, runner: runner)
    end

    def test_create_provisions_role_and_database_over_ssh_via_stdin
      runner = FakeRunner.new
      tenant(runner, env).create
      call = runner.calls.fetch(0)
      assert_includes call[:cmd], "ssh"
      assert_includes call[:cmd], "deploy@10.0.0.1"
      assert_includes call[:cmd], "platform-db"
      assert_match(/format\('CREATE ROLE %I LOGIN PASSWORD %L', 'app', 's3cr3t'\)/, call[:sql])
      assert_match(/format\('CREATE DATABASE %I OWNER %I', 'app_prod', 'app'\)/, call[:sql])
      assert_match(/pg_roles WHERE rolname = 'app'/, call[:sql])
    end

    def test_ensure_password_alters_the_role_to_the_managed_secret
      runner = FakeRunner.new
      tenant(runner, env).ensure_password
      sql = runner.calls.fetch(0)[:sql]
      assert_match(/format\('ALTER ROLE %I PASSWORD %L', 'app', 's3cr3t'\)/, sql)
      refute_match(/CREATE (ROLE|DATABASE)/, sql)
    end

    def test_password_with_quote_backslash_and_dollar_tag_stays_a_sql_literal
      runner = FakeRunner.new
      tenant(runner, env("PROD_TENANT_PASSWORD" => "pa\\tss'w$do$rd")).ensure_password
      sql = runner.calls.fetch(0)[:sql]
      assert_includes sql, "ALTER ROLE %I PASSWORD %L', 'app', 'pa\\tss''w$do$rd')"
      refute_includes sql, "DO $do$"
      refute(runner.calls.fetch(0)[:cmd].any? { |arg| arg.include?("pa") })
    end

    def test_database_url_carries_the_managed_password_against_the_platform_db
      url = tenant(FakeRunner.new, env).database_url
      assert_equal "ecto://app:s3cr3t@platform-db/app_prod", url
    end

    def test_database_url_percent_encodes_a_password_with_url_metacharacters
      url = tenant(FakeRunner.new, env("PROD_TENANT_PASSWORD" => "p@ss:w/rd")).database_url
      assert_equal "ecto://app:p%40ss%3Aw%2Frd@platform-db/app_prod", url
    end

    def test_database_url_percent_encodes_space_and_plus_so_userinfo_is_unambiguous
      url = tenant(FakeRunner.new, env("PROD_TENANT_PASSWORD" => "a b+c")).database_url
      assert_equal "ecto://app:a%20b%2Bc@platform-db/app_prod", url
    end

    def test_database_url_honours_scheme_and_container_overrides
      url = tenant(FakeRunner.new, env("DB_URL_SCHEME" => "postgres", "PG_CONTAINER" => "pg")).database_url
      assert_equal "postgres://app:s3cr3t@pg/app_prod", url
    end

    def test_database_url_carries_the_tenant_role_not_the_admin
      url = tenant(FakeRunner.new, env("PG_ADMIN_USER" => "eiseron")).database_url
      refute_includes url, "eiseron"
    end

    def test_rejects_invalid_slug
      runner = FakeRunner.new
      error = assert_raises(Error) { tenant(runner, env("PROD_TENANT_SLUG" => "app;DROP")).create }
      assert_match(/not a valid postgres identifier/, error.message)
      assert_empty runner.calls
    end

    def test_create_requires_slug_password_and_host
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_SLUG")).create }
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_PASSWORD")).create }
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_HOST")).create }
    end

    def test_ensure_password_requires_slug_password_and_host
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_SLUG")).ensure_password }
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_TENANT_PASSWORD")).ensure_password }
      assert_raises(Error) { tenant(FakeRunner.new, env.except("PROD_HOST")).ensure_password }
    end
  end
end
