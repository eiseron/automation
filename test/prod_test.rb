# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdTest < Minitest::Test
    class FakeRunner
      attr_reader :runs, :stdins, :captures

      def initialize(primary: "platform-db-1")
        @runs = []
        @stdins = []
        @captures = []
        @primary = primary
      end

      def run(env, *cmd)
        @runs << { env: env, cmd: cmd }
      end

      def run_stdin(input, _env, *cmd)
        @stdins << { sql: input, cmd: cmd }
      end

      def capture(*cmd)
        @captures << cmd
        @primary
      end
    end

    FakeClient = Struct.new(:tags) do
      def release_tags
        tags
      end
    end

    def base_env
      {
        "PROD_TAG" => "v1.4.0",
        "PROD_PROJECT" => "acme/app",
        "PROD_DEPLOY_READ_TOKEN" => "tok",
        "CI_API_V4_URL" => "https://gitlab.com/api/v4",
        "PROD_TENANT_SLUG" => "app",
        "PROD_TENANT_PASSWORD" => "s3cr3t",
        "PROD_IMAGE" => "registry.example.test/acme/app/prod",
        "PROD_MIGRATE_CMD" => "bin/app eval App.Release.migrate"
      }
    end

    def deploy(env: base_env, runner: FakeRunner.new, client: FakeClient.new(%w[v1.3.0 v1.4.0]))
      Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: client)
    end

    def test_latest_is_true_when_tag_is_the_highest_release
      assert Prod::Plan.latest?("v1.4.0", %w[v1.2.0 v1.3.5 v1.4.0])
    end

    def test_latest_is_false_when_a_higher_release_exists
      refute Prod::Plan.latest?("v1.3.0", %w[v1.2.0 v1.3.0 v1.4.0])
    end

    def test_latest_compares_numerically_not_lexically
      assert Prod::Plan.latest?("v1.10.0", %w[v1.9.0 v1.10.0])
    end

    def test_latest_ignores_non_release_tags
      assert Prod::Plan.latest?("v2.0.0", %w[v2.0.0 latest v2.0.0-rc1 nightly])
    end

    def test_latest_raises_on_a_non_release_tag
      error = assert_raises(Error) { Prod::Plan.latest?("nightly", %w[v1.0.0]) }
      assert_match(/not a release tag/, error.message)
    end

    def test_deploy_sets_the_deployment_image_to_the_tag
      runner = FakeRunner.new
      deploy(runner: runner).deploy
      assert_equal(["kubectl", "set", "image", "deployment/app",
                    "app=registry.example.test/acme/app/prod:v1.4.0", "-n", "app"], runner.runs.fetch(0)[:cmd])
    end

    def test_deploy_waits_for_the_rollout_to_complete
      runner = FakeRunner.new
      deploy(runner: runner).deploy
      assert_equal(["kubectl", "rollout", "status", "deployment/app", "-n", "app", "--timeout=300s"],
                   runner.runs.fetch(1)[:cmd])
    end

    def test_deploy_runs_migrations_after_the_rollout
      runner = FakeRunner.new
      deploy(runner: runner).deploy
      assert_equal(["kubectl", "exec", "-n", "app", "deployment/app", "--", "bin/app", "eval", "App.Release.migrate"],
                   runner.runs.fetch(2)[:cmd])
    end

    def test_deploy_ensures_the_tenant_password_against_the_managed_secret
      runner = FakeRunner.new
      deploy(runner: runner).deploy
      assert_match(/ALTER ROLE %I PASSWORD %L', 'app', 's3cr3t'/, runner.stdins.fetch(0)[:sql])
    end

    def test_deploy_ensures_the_password_exactly_once
      runner = FakeRunner.new
      deploy(runner: runner).deploy
      assert_equal 1, runner.stdins.length
    end

    def test_deploy_targets_the_cnpg_primary_for_the_password_change
      runner = FakeRunner.new
      deploy(runner: runner).deploy
      assert_includes runner.captures.fetch(0), "cnpg.io/cluster=platform-db,cnpg.io/instanceRole=primary"
    end

    def test_deploy_never_exports_database_url_to_the_ci_environment
      refute base_env.key?("DATABASE_URL")
    end

    def test_deploy_refuses_a_non_latest_tag
      runner = FakeRunner.new
      error = assert_raises(Error) { deploy(env: base_env.merge("PROD_TAG" => "v1.3.0"), runner: runner).deploy }
      assert_match(/not the latest release/, error.message)
    end

    def test_deploy_touches_nothing_when_it_refuses
      runner = FakeRunner.new
      assert_raises(Error) { deploy(env: base_env.merge("PROD_TAG" => "v1.3.0"), runner: runner).deploy }
      assert_empty runner.runs
    end

    def test_deploy_allows_an_old_tag_with_the_override
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "v1.3.0", "PROD_DEPLOY_ALLOW_OLD" => "true", "CI_PIPELINE_SOURCE" => "web")
      deploy(env: env, runner: runner).deploy
      assert_equal "app=registry.example.test/acme/app/prod:v1.3.0", runner.runs.fetch(0)[:cmd].fetch(4)
    end

    def test_deploy_ignores_the_override_outside_a_web_pipeline
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "v1.3.0", "PROD_DEPLOY_ALLOW_OLD" => "true", "CI_PIPELINE_SOURCE" => "trigger")
      error = assert_raises(Error) { deploy(env: env, runner: runner).deploy }
      assert_match(/not the latest release/, error.message)
    end

    def test_deploy_validates_tag_format_even_with_override
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "nightly", "PROD_DEPLOY_ALLOW_OLD" => "true", "CI_PIPELINE_SOURCE" => "web")
      error = assert_raises(Error) { deploy(env: env, runner: runner).deploy }
      assert_match(/not a release tag/, error.message)
    end

    def test_deploy_raises_when_prod_tag_is_missing
      assert_raises(Error) { deploy(env: base_env.except("PROD_TAG")).deploy }
    end

    def test_deploy_raises_when_the_image_is_missing
      error = assert_raises(Error) { deploy(env: base_env.except("PROD_IMAGE")).deploy }
      assert_match(/PROD_IMAGE is empty/, error.message)
    end

    def test_deploy_raises_when_the_migrate_command_is_missing
      error = assert_raises(Error) { deploy(env: base_env.except("PROD_MIGRATE_CMD")).deploy }
      assert_match(/PROD_MIGRATE_CMD is empty/, error.message)
    end

    def test_deploy_honours_the_app_and_namespace_overrides
      runner = FakeRunner.new
      deploy(env: base_env.merge("PROD_APP" => "web", "PROD_NAMESPACE" => "other"), runner: runner).deploy
      assert_equal(["kubectl", "set", "image", "deployment/web",
                    "web=registry.example.test/acme/app/prod:v1.4.0", "-n", "other"], runner.runs.fetch(0)[:cmd])
    end

    def test_backup_creates_an_on_demand_cnpg_backup_resource
      runner = FakeRunner.new
      deploy(runner: runner).backup
      assert_equal ["kubectl", "create", "-n", "platform", "-f", "-"], runner.stdins.fetch(0)[:cmd]
    end

    def test_backup_manifest_is_a_cnpg_backup
      runner = FakeRunner.new
      deploy(runner: runner).backup
      assert_match(/kind: Backup/, runner.stdins.fetch(0)[:sql])
    end

    def test_backup_targets_the_platform_cluster
      runner = FakeRunner.new
      deploy(runner: runner).backup
      assert_match(/name: platform-db/, runner.stdins.fetch(0)[:sql])
    end

    def test_backup_does_not_rotate_the_tenant_password
      runner = FakeRunner.new
      deploy(runner: runner).backup
      assert_empty runner.captures
    end

    def web_env(overrides = {})
      base_env.merge("CI_PIPELINE_SOURCE" => "web").merge(overrides)
    end

    def test_setup_rolls_out_the_image
      runner = FakeRunner.new
      deploy(env: web_env, runner: runner).setup
      assert_equal(["kubectl", "set", "image", "deployment/app",
                    "app=registry.example.test/acme/app/prod:v1.4.0", "-n", "app"], runner.runs.fetch(0)[:cmd])
    end

    def test_setup_runs_migrations
      runner = FakeRunner.new
      deploy(env: web_env, runner: runner).setup
      assert_equal(["kubectl", "exec", "-n", "app", "deployment/app", "--", "bin/app", "eval", "App.Release.migrate"],
                   runner.runs.fetch(2)[:cmd])
    end

    def test_setup_also_ensures_the_db_password
      runner = FakeRunner.new
      deploy(env: web_env, runner: runner).setup
      assert_match(/ALTER ROLE %I PASSWORD %L', 'app'/, runner.stdins.fetch(0)[:sql])
    end

    def test_setup_does_not_apply_the_latest_release_guard
      runner = FakeRunner.new
      deploy(env: web_env("PROD_TAG" => "v1.3.0"), runner: runner).setup
      assert_equal "app=registry.example.test/acme/app/prod:v1.3.0", runner.runs.fetch(0)[:cmd].fetch(4)
    end

    def test_setup_refuses_outside_a_web_pipeline
      runner = FakeRunner.new
      error = assert_raises(Error) do
        deploy(env: base_env.merge("CI_PIPELINE_SOURCE" => "trigger"), runner: runner).setup
      end
      assert_match(/manual web pipeline/, error.message)
    end

    def test_setup_touches_nothing_outside_a_web_pipeline
      runner = FakeRunner.new
      assert_raises(Error) { deploy(env: base_env.merge("CI_PIPELINE_SOURCE" => "trigger"), runner: runner).setup }
      assert_empty runner.runs
    end

    def test_setup_validates_tag_format
      runner = FakeRunner.new
      error = assert_raises(Error) { deploy(env: web_env("PROD_TAG" => "nightly"), runner: runner).setup }
      assert_match(/not a release tag/, error.message)
    end
  end
end
