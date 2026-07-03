# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class DeployTest < Minitest::Test
      class FakeSsh
        attr_reader :runs, :scripts

        def initialize(image_present: true)
          @runs = []
          @scripts = []
          @image_present = image_present
        end

        def run(cmd)
          @runs << cmd
          raise Error, "image missing" if cmd.start_with?("docker image inspect") && !@image_present
        end

        def bash(script) = @scripts << script
        def capture(_) = ""
      end

      class FakeRegistry
        attr_reader :deleted

        def initialize
          @deleted = []
        end

        def delete_preview_tag(ref) = @deleted << ref
      end

      class FakeRunner
        def initialize(curl_status: "200")
          @curl_status = curl_status
        end

        def capture(*) = @curl_status
      end

      def base_env
        {
          "EISERON_PREVIEW_APP_NAME" => "afinados",
          "EISERON_PREVIEW_COMPOSE_TEMPLATE" => "/tmp/__deploy_test_compose__.yml",
          "PREVIEW_REF" => "feat-foo",
          "PREVIEW_SHA" => "abc123",
          "PREVIEW_MR_IID" => "9",
          "PREVIEW_KIND" => "mr",
          "PREVIEW_IMAGE_REPO" => "registry.gitlab.com/eiseron/afinados/afinados-ops/preview",
          "PREVIEW_DOMAIN_BASE" => "preview.afinados.io",
          "PREVIEW_IMAGE_PULL_USER" => "puller",
          "PREVIEW_IMAGE_PULL_TOKEN" => "tok",
          "PREVIEW_SECRET_KEY_BASE" => "kbase",
          "PREVIEW_HEALTHCHECK_TOKEN_ID" => "cf-id",
          "PREVIEW_HEALTHCHECK_TOKEN_SECRET" => "cf-secret",
          "SHARED_PG_USER" => "postgres"
        }
      end

      def with_compose_template(content)
        path = base_env["EISERON_PREVIEW_COMPOSE_TEMPLATE"]
        File.write(path, content)
        yield path
      ensure
        FileUtils.rm_f(path)
      end

      def deploy(env: base_env, ssh: FakeSsh.new, registry: FakeRegistry.new, runner: FakeRunner.new)
        sleeper = ->(_) {}
        clock_calls = -1
        clock = lambda {
          clock_calls += 1
          clock_calls.to_f
        }
        Deploy.new(env: env, io: StringIO.new, ssh: ssh, registry: registry, runner: runner,
                   sleeper: sleeper, clock: clock).run
        [ssh, registry]
      end

      def test_full_sequence_on_mr_kind_uses_mr_prefixed_project
        ssh = FakeSsh.new
        with_compose_template("services:\n  afinados: {image: x}\n") do
          deploy(ssh: ssh)
        end
        compose_script = ssh.scripts.find { |s| s.include?("up -d") }
        refute_nil compose_script
        assert_includes compose_script, "docker compose -p \"mr-feat-foo\""
      end

      def test_main_kind_uses_main_project
        ssh = FakeSsh.new
        env = base_env.merge("PREVIEW_KIND" => "main", "PREVIEW_REF" => "main", "PREVIEW_MR_IID" => "")
        with_compose_template("x:\n") do
          deploy(env: env, ssh: ssh)
        end
        compose_script = ssh.scripts.find { |s| s.include?("up -d") }
        assert_includes compose_script, "docker compose -p \"main\""
      end

      def test_per_mr_role_sql_uses_app_and_ref
        ssh = FakeSsh.new
        with_compose_template("x:\n") { deploy(ssh: ssh) }
        roles_script = ssh.scripts.find { |s| s.include?("CREATE ROLE") && s.include?("CREATE DATABASE") }
        refute_nil roles_script
        assert_includes roles_script, 'CREATE ROLE "afinados_feat-foo_app"'
        assert_includes roles_script, 'CREATE ROLE "afinados_feat-foo_admin"'
        assert_includes roles_script, 'CREATE DATABASE "afinados_feat-foo"'
        assert_includes roles_script, "GRANT afinados_app   TO"
        assert_includes roles_script, "GRANT afinados_admin TO"
      end

      def test_shared_roles_sql_idempotent
        ssh = FakeSsh.new
        with_compose_template("x:\n") { deploy(ssh: ssh) }
        shared_script = ssh.scripts.find { |s| s.include?("NOLOGIN BYPASSRLS") }
        refute_nil shared_script
        assert_includes shared_script, "IF NOT EXISTS"
        assert_includes shared_script, "CREATE ROLE afinados_admin NOLOGIN BYPASSRLS"
        assert_includes shared_script, "CREATE ROLE afinados_app NOLOGIN"
      end

      def test_per_mr_grants_app_role_table_privileges_in_target_db
        ssh = FakeSsh.new
        with_compose_template("x:\n") { deploy(ssh: ssh) }
        roles_script = ssh.scripts.find { |s| s.include?("CREATE ROLE") && s.include?("CREATE DATABASE") }
        refute_nil roles_script
        assert_includes roles_script, 'psql -U postgres -d "afinados_feat-foo"'
        assert_includes roles_script, 'GRANT USAGE ON SCHEMA public TO "afinados_feat-foo_app"'
        assert_includes roles_script,
                        'ALTER DEFAULT PRIVILEGES FOR ROLE "afinados_feat-foo_admin" IN SCHEMA public'
        assert_includes roles_script,
                        'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "afinados_feat-foo_app"'
        assert_includes roles_script, 'GRANT USAGE, SELECT ON SEQUENCES TO "afinados_feat-foo_app"'
      end

      def test_migrate_runs_with_admin_role_and_mix_env_preview
        ssh = FakeSsh.new
        with_compose_template("x:\n") { deploy(ssh: ssh) }
        migrate_script = ssh.scripts.find { |s| s.include?("mix ecto.migrate") }
        refute_nil migrate_script
        assert_includes migrate_script, "DB_USER='afinados_feat-foo_admin'"
        assert_includes migrate_script, "MIX_ENV=preview"
      end

      def test_compose_yml_is_embedded_into_bash_heredoc
        ssh = FakeSsh.new
        with_compose_template("services:\n  afinados:\n    image: foo\n") do
          deploy(ssh: ssh)
        end
        up_script = ssh.scripts.find { |s| s.include?("up -d") }
        assert_includes up_script, "services:\n  afinados:\n    image: foo"
        assert_includes up_script, "export PREVIEW_REF='feat-foo'"
        assert_includes up_script, "export MR_PG_APP_USER='afinados_feat-foo_app'"
      end

      def test_releases_registry_tag_when_image_present
        ssh = FakeSsh.new(image_present: true)
        registry = FakeRegistry.new
        with_compose_template("x:\n") { deploy(ssh: ssh, registry: registry) }
        assert_equal ["feat-foo"], registry.deleted
      end

      def test_does_not_release_tag_when_image_missing
        ssh = FakeSsh.new(image_present: false)
        registry = FakeRegistry.new
        with_compose_template("x:\n") { deploy(ssh: ssh, registry: registry) }
        assert_empty registry.deleted
      end

      def test_healthcheck_timeout_raises_with_health_url
        ssh = FakeSsh.new
        runner = FakeRunner.new(curl_status: "503")
        err = nil
        with_compose_template("x:\n") do
          err = assert_raises(Error) { deploy(ssh: ssh, runner: runner) }
        end
        assert_match(/healthcheck timed out/, err.message)
        assert_match(%r{https://feat-foo-preview\.afinados\.io/healthz}, err.message)
      end

      def test_healthcheck_timeout_dumps_host_diagnostics_before_raising
        ssh = FakeSsh.new
        runner = FakeRunner.new(curl_status: "503")
        with_compose_template("x:\n") do
          assert_raises(Error) { deploy(ssh: ssh, runner: runner) }
        end
        probes = ssh.runs.join("\n")
        assert_includes probes, "docker compose -p mr-feat-foo ps -a"
        assert_includes probes, "docker inspect mr-feat-foo-afinados-1 --format '{{json .Config.Labels}}'"
        assert_includes probes, "-H 'Host: feat-foo-preview.afinados.io' http://localhost/healthz"
      end

      def test_rejects_kind_outside_mr_main
        ssh = FakeSsh.new
        err = with_compose_template("x:\n") do
          assert_raises(Error) { deploy(env: base_env.merge("PREVIEW_KIND" => "branch"), ssh: ssh) }
        end
        assert_match(/PREVIEW_KIND='branch'/, err.message)
      end

      def test_requires_compose_template_path
        env = base_env.except("EISERON_PREVIEW_COMPOSE_TEMPLATE")
        err = assert_raises(Error) { deploy(env: env) }
        assert_match(/EISERON_PREVIEW_COMPOSE_TEMPLATE/, err.message)
      end

      def test_health_path_can_be_overridden
        ssh = FakeSsh.new
        runner = FakeRunner.new(curl_status: "503")
        env = base_env.merge("EISERON_PREVIEW_HEALTH_PATH" => "/ready")
        err = with_compose_template("x:\n") do
          assert_raises(Error) { deploy(env: env, ssh: ssh, runner: runner) }
        end
        assert_match(%r{/ready}, err.message)
      end
    end
  end
end
