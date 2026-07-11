# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class CLITest < Minitest::Test
    def run_cli(argv, env: {})
      err = StringIO.new
      code = CLI.new(argv, env: env, io: StringIO.new, err: err).run
      [code, err.string]
    end

    def test_unknown_command_exits_nonzero_with_reason
      code, err = run_cli(%w[bogus cmd])
      assert_equal 1, code
      assert_match(/unknown command 'bogus cmd'/, err)
    end

    def test_release_tag_aborts_without_token_before_any_api_call
      code, err = run_cli(%w[release tag], env: {})
      assert_equal 1, code
      assert_match(/RELEASE_TOKEN is empty/, err)
    end

    def test_release_tag_uses_release_token_then_needs_ci_api_url
      code, err = run_cli(%w[release tag], env: { "RELEASE_TOKEN" => "a-token" })
      assert_equal 1, code
      assert_match(/CI_API_V4_URL is empty/, err)
    end

    def test_prod_deploy_is_registered_and_aborts_without_prod_tag
      code, err = run_cli(%w[prod deploy], env: {})
      assert_equal 1, code
      assert_match(/PROD_TAG is empty/, err)
    end

    def test_prod_tenant_is_registered_and_aborts_without_slug
      code, err = run_cli(%w[prod tenant], env: {})
      assert_equal 1, code
      assert_match(/PROD_TENANT_SLUG is empty/, err)
    end

    def test_prod_setup_is_registered_and_aborts_without_prod_tag
      code, err = run_cli(%w[prod setup], env: {})
      assert_equal 1, code
      assert_match(/PROD_TAG is empty/, err)
    end

    def test_prod_backup_is_registered_and_aborts_without_tenant_slug
      code, err = run_cli(%w[prod backup], env: {})
      assert_equal 1, code
      assert_match(/PROD_TENANT_SLUG is empty/, err)
    end

    def test_prod_restore_is_registered_and_aborts_without_a_backup_object
      code, err = run_cli(%w[prod restore], env: {})
      assert_equal 1, code
      assert_match(/PROD_RESTORE_KEY is empty/, err)
    end

    def test_db_restore_is_registered_and_refuses_without_confirmation
      code, err = run_cli(%w[db restore], env: {})
      assert_equal 1, code
      assert_match(/PROD_RESTORE_CONFIRM=app_prod/, err)
    end

    def test_db_backup_schedule_is_registered_and_aborts_without_cron
      code, err = run_cli(%w[db backup schedule], env: {})
      assert_equal 1, code
      assert_match(/BACKUP_CRON is empty/, err)
    end

    def test_db_backup_one_shot_stays_a_distinct_command
      code, err = run_cli(%w[db backup], env: {})
      assert_equal 1, code
      assert_match(/PROD_BACKUP_AGE_RECIPIENTS|empty/, err)
    end

    def test_a_mistyped_subcommand_does_not_silently_fall_back_to_backup
      code, err = run_cli(%w[db backup typo], env: {})
      assert_equal 1, code
      assert_match(/unknown command 'db backup typo'/, err)
    end

    def test_db_backup_verify_is_registered_and_aborts_without_a_bucket
      code, err = run_cli(%w[db backup verify], env: {})
      assert_equal 1, code
      assert_match(/PROD_BACKUP_BUCKET is empty/, err)
    end

    def test_notify_ci_failure_is_registered_and_aborts_without_project_path
      code, err = run_cli(%w[notify ci-failure], env: {})
      assert_equal 1, code
      assert_match(/CI_PROJECT_PATH is empty/, err)
    end

    def test_db_backup_healthcheck_is_registered_and_fails_without_a_heartbeat
      code, err = run_cli(%w[db backup healthcheck], env: { "BACKUP_HEARTBEAT_FILE" => "/nonexistent/hb" })
      assert_equal 1, code
      assert_match(/heartbeat/, err)
    end

    def test_prod_upload_is_registered_and_skips_without_creds
      code, = run_cli(%w[prod upload], env: {})
      assert_equal 0, code
    end

    def test_prod_trigger_is_registered_and_skips_without_config
      code, = run_cli(%w[prod trigger], env: {})
      assert_equal 0, code
    end

    def obs_query_for(env)
      CLI.new(%w[obs streams], env: env, io: StringIO.new, err: StringIO.new).send(:obs_query)
    end

    def test_obs_query_routes_to_clickhouse_when_backend_is_set
      assert_instance_of Observability::ClickHouseQuery,
                         obs_query_for({ "OBSERVABILITY_BACKEND" => "clickhouse" })
    end

    def test_obs_query_defaults_to_the_openobserve_backend
      assert_instance_of Observability::Query, obs_query_for({})
    end

    def test_obs_retention_is_registered_and_aborts_without_clickhouse_url
      code, err = run_cli(%w[obs retention], env: {})
      assert_equal 1, code
      assert_match(/missing env CLICKHOUSE_URL/, err)
    end

    def test_obs_login_is_registered_and_aborts_without_credentials
      code, err = run_cli(%w[obs login], env: {})
      assert_equal 1, code
      assert_match(/usage: obs login/, err)
    end
  end
end
