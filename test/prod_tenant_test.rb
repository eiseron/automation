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
      { "PROD_TENANT_SLUG" => "afinados", "PROD_TENANT_PASSWORD" => "s3cr3t", "PROD_HOST" => "10.0.0.1" }.merge(over)
    end

    def create_tenant(runner, vars)
      Prod::Tenant.new(env: vars, io: StringIO.new, runner: runner).create
    end

    def test_provisions_role_and_database_over_ssh_via_stdin
      runner = FakeRunner.new
      create_tenant(runner, env)
      call = runner.calls.fetch(0)
      assert_includes call[:cmd], "ssh"
      assert_includes call[:cmd], "deploy@10.0.0.1"
      assert_includes call[:cmd], "platform-db"
      assert_match(/format\('CREATE ROLE %I LOGIN PASSWORD %L', 'afinados', 's3cr3t'\)/, call[:sql])
      assert_match(/format\('CREATE DATABASE %I OWNER %I', 'afinados_prod', 'afinados'\)/, call[:sql])
      assert_match(/pg_roles WHERE rolname = 'afinados'/, call[:sql])
    end

    def test_password_with_quote_backslash_and_dollar_tag_is_a_sql_literal
      runner = FakeRunner.new
      create_tenant(runner, env("PROD_TENANT_PASSWORD" => "pa\\tss'w$do$rd"))
      sql = runner.calls.fetch(0)[:sql]
      assert_includes sql, "LOGIN PASSWORD %L', 'afinados', 'pa\\tss''w$do$rd')"
      refute_includes sql, "DO $do$"
      refute_includes sql, "\\set"
      refute(runner.calls.fetch(0)[:cmd].any? { |a| a.include?("pa") })
    end

    def test_rejects_invalid_slug
      runner = FakeRunner.new
      error = assert_raises(Error) { create_tenant(runner, env("PROD_TENANT_SLUG" => "afinados;DROP")) }
      assert_match(/not a valid postgres identifier/, error.message)
      assert_empty runner.calls
    end

    def test_requires_slug_password_and_host
      assert_raises(Error) { create_tenant(FakeRunner.new, env.except("PROD_TENANT_SLUG")) }
      assert_raises(Error) { create_tenant(FakeRunner.new, env.except("PROD_TENANT_PASSWORD")) }
      assert_raises(Error) { create_tenant(FakeRunner.new, env.except("PROD_HOST")) }
    end
  end
end
