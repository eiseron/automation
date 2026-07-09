# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdTest < Minitest::Test
    class FakeRunner
      attr_reader :runs, :stdins

      def initialize
        @runs = []
        @stdins = []
      end

      def run(env, *cmd)
        @runs << { env: env, cmd: cmd }
      end

      def run_stdin(input, _env, *cmd)
        @stdins << { sql: input, cmd: cmd }
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
        "PROD_HOST" => "10.0.0.1",
        "APP_SERVICE" => "app",
        "APP_IMAGE" => "registry.example.com/acme/app/prod",
        "APP_RELEASE_MODULE" => "App",
        "SECRET_KEY_BASE" => "kb"
      }
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

    def test_deploy_updates_the_service_start_first_then_migrates_and_seeds
      runner = FakeRunner.new
      client = FakeClient.new(%w[v1.3.0 v1.4.0])
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: client).deploy

      image = "registry.example.com/acme/app/prod:v1.4.0"
      commands = runner.runs.map { |run| run[:cmd] }
      assert_equal [
        ["docker", "service", "update", "--image", image, "--update-order", "start-first", "--with-registry-auth",
         "app"],
        ["docker", "run", "--rm", "--network", "internal", "-e", "DATABASE_URL", "-e", "SECRET_KEY_BASE", "-e",
         "PHX_SERVER=false", image, "bin/app", "eval", "App.Release.migrate"],
        ["docker", "run", "--rm", "--network", "internal", "-e", "DATABASE_URL", "-e", "SECRET_KEY_BASE", "-e",
         "PHX_SERVER=false", image, "bin/app", "eval", "App.Release.seed"]
      ], commands
    end

    def test_deploy_targets_the_prod_host_over_ssh
      runner = FakeRunner.new
      client = FakeClient.new(%w[v1.3.0 v1.4.0])
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: client).deploy

      assert_equal "ssh://deploy@10.0.0.1", runner.runs.fetch(0)[:env].fetch("DOCKER_HOST")
    end

    def test_deploy_runs_migrations_with_the_assembled_database_url
      runner = FakeRunner.new
      client = FakeClient.new(%w[v1.3.0 v1.4.0])
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: client).deploy

      migrate = runner.runs.fetch(1)
      assert_equal "ecto://app:s3cr3t@platform-db/app_prod", migrate[:env].fetch("DATABASE_URL")
    end

    def test_deploy_ensures_the_db_password_only_once
      runner = FakeRunner.new
      client = FakeClient.new(%w[v1.3.0 v1.4.0])
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: client).deploy

      assert_equal 1, runner.stdins.length
    end

    def test_deploy_ensures_the_db_password_and_injects_the_database_url
      runner = FakeRunner.new
      client = FakeClient.new(%w[v1.3.0 v1.4.0])
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: client).deploy

      assert_match(/ALTER ROLE %I PASSWORD %L', 'app', 's3cr3t'/, runner.stdins.fetch(0)[:sql])
      assert_equal "ecto://app:s3cr3t@platform-db/app_prod", runner.runs.fetch(0)[:env].fetch("DATABASE_URL")
    end

    def test_deploy_never_exports_database_url_to_the_ci_environment
      refute base_env.key?("DATABASE_URL")
    end

    def test_deploy_refuses_a_non_latest_tag
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "v1.3.0")
      client = FakeClient.new(%w[v1.3.0 v1.4.0])
      prod = Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: client)

      error = assert_raises(Error) { prod.deploy }
      assert_match(/not the latest release/, error.message)
      assert_empty runner.runs
    end

    def test_deploy_allows_an_old_tag_with_the_override
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "v1.3.0", "PROD_DEPLOY_ALLOW_OLD" => "true", "CI_PIPELINE_SOURCE" => "web")
      Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new(%w[v1.3.0 v1.4.0])).deploy

      image = "registry.example.com/acme/app/prod:v1.3.0"
      first = runner.runs.fetch(0)[:cmd]
      assert_equal ["docker", "service", "update", "--image", image, "--update-order", "start-first",
                    "--with-registry-auth", "app"], first
    end

    def test_deploy_raises_when_prod_tag_is_missing
      env = base_env.except("PROD_TAG")
      prod = Prod::Deploy.new(env: env, io: StringIO.new, runner: FakeRunner.new, client: FakeClient.new([]))
      assert_raises(Error) { prod.deploy }
    end

    def test_backup_execs_the_one_shot_in_the_backup_accessory
      runner = FakeRunner.new
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: FakeClient.new([])).backup

      commands = runner.runs.map { |run| run[:cmd] }
      assert_equal [["kamal", "accessory", "exec", "backup", "--version=latest", "eiseron", "db", "backup"]], commands
    end

    def test_backup_passes_a_version_so_kamal_does_not_need_a_git_repo
      runner = FakeRunner.new
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: FakeClient.new([])).backup

      assert_includes runner.runs.fetch(0)[:cmd], "--version=latest"
    end

    def test_backup_injects_the_database_url_for_the_manifest_render
      runner = FakeRunner.new
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: FakeClient.new([])).backup

      assert_equal "ecto://app:s3cr3t@platform-db/app_prod", runner.runs.fetch(0)[:env].fetch("DATABASE_URL")
    end

    def test_backup_does_not_rotate_the_tenant_password
      runner = FakeRunner.new
      Prod::Deploy.new(env: base_env, io: StringIO.new, runner: runner, client: FakeClient.new([])).backup

      assert_empty runner.stdins
    end

    def web_env(overrides = {})
      base_env.merge("CI_PIPELINE_SOURCE" => "web").merge(overrides)
    end

    def test_setup_runs_kamal_setup_with_version_and_skip_push
      runner = FakeRunner.new
      Prod::Deploy.new(env: web_env, io: StringIO.new, runner: runner, client: FakeClient.new([])).setup

      commands = runner.runs.map { |run| run[:cmd] }
      assert_equal [["kamal", "setup", "--version=v1.4.0", "--skip-push"]], commands
    end

    def test_setup_also_ensures_the_db_password
      runner = FakeRunner.new
      Prod::Deploy.new(env: web_env, io: StringIO.new, runner: runner, client: FakeClient.new([])).setup

      assert_match(/ALTER ROLE %I PASSWORD %L', 'app'/, runner.stdins.fetch(0)[:sql])
      assert runner.runs.fetch(0)[:env].key?("DATABASE_URL")
    end

    def test_setup_does_not_apply_the_latest_release_guard
      runner = FakeRunner.new
      env = web_env("PROD_TAG" => "v1.3.0")
      Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new(%w[v1.3.0 v1.4.0])).setup

      commands = runner.runs.map { |run| run[:cmd] }
      assert_equal [["kamal", "setup", "--version=v1.3.0", "--skip-push"]], commands
    end

    def test_setup_refuses_outside_a_web_pipeline
      runner = FakeRunner.new
      env = base_env.merge("CI_PIPELINE_SOURCE" => "trigger")
      prod = Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new([]))

      error = assert_raises(Error) { prod.setup }
      assert_match(/manual web pipeline/, error.message)
      assert_empty runner.runs
    end

    def test_setup_validates_tag_format
      runner = FakeRunner.new
      env = web_env("PROD_TAG" => "nightly")
      prod = Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new([]))

      error = assert_raises(Error) { prod.setup }
      assert_match(/not a release tag/, error.message)
      assert_empty runner.runs
    end

    def test_deploy_ignores_override_outside_a_web_pipeline
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "v1.3.0", "PROD_DEPLOY_ALLOW_OLD" => "true", "CI_PIPELINE_SOURCE" => "trigger")
      prod = Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new(%w[v1.3.0 v1.4.0]))

      error = assert_raises(Error) { prod.deploy }
      assert_match(/not the latest release/, error.message)
      assert_empty runner.runs
    end

    def test_deploy_validates_tag_format_even_with_override
      runner = FakeRunner.new
      env = base_env.merge("PROD_TAG" => "nightly", "PROD_DEPLOY_ALLOW_OLD" => "true", "CI_PIPELINE_SOURCE" => "web")
      prod = Prod::Deploy.new(env: env, io: StringIO.new, runner: runner, client: FakeClient.new([]))

      error = assert_raises(Error) { prod.deploy }
      assert_match(/not a release tag/, error.message)
      assert_empty runner.runs
    end
  end
end
