# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class TeardownTest < Minitest::Test
      class FakeSsh
        attr_reader :commands, :scripts

        def initialize
          @commands = []
          @scripts = []
        end

        def run(cmd) = @commands << cmd
        def bash(script) = @scripts << script
      end

      class FakeRegistry
        attr_reader :deleted

        def initialize
          @deleted = []
        end

        def delete_preview_tag(ref) = @deleted << ref
      end

      def base_env(extra = {})
        {
          "EISERON_PREVIEW_APP_NAME" => "app",
          "SHARED_PG_USER" => "postgres"
        }.merge(extra)
      end

      def test_runs_compose_down_drops_db_and_roles_and_deletes_tag
        ssh = FakeSsh.new
        registry = FakeRegistry.new
        Teardown.new(env: base_env, io: StringIO.new, ssh: ssh, registry: registry)
                .run(project: "mr-feat-foo", ref: "feat-foo")

        assert_includes ssh.commands.first, "docker compose -p mr-feat-foo"
        assert_includes ssh.commands.first, " down "
        assert_includes ssh.commands.first, " -v "
        assert_includes ssh.commands.first, "--remove-orphans"
        assert_includes ssh.commands.first, "--rmi all"

        script = ssh.scripts.fetch(0)
        assert_includes script, 'DROP DATABASE IF EXISTS "app_feat-foo" WITH (FORCE);'
        assert_includes script, 'DROP ROLE IF EXISTS "app_feat-foo_app";'
        assert_includes script, 'DROP ROLE IF EXISTS "app_feat-foo_admin";'

        assert_equal ["feat-foo"], registry.deleted
      end

      def test_db_container_overrides_via_env
        ssh = FakeSsh.new
        Teardown.new(env: base_env("EISERON_PREVIEW_DB_CONTAINER" => "custom-pg"),
                     io: StringIO.new, ssh: ssh, registry: FakeRegistry.new)
                .run(project: "mr-feat-foo", ref: "feat-foo")
        assert_includes ssh.scripts.fetch(0), "docker exec custom-pg"
      end

      def test_requires_app_name
        err = assert_raises(Error) do
          Teardown.new(env: base_env.except("EISERON_PREVIEW_APP_NAME"),
                       io: StringIO.new, ssh: FakeSsh.new, registry: FakeRegistry.new)
                  .run(project: "mr-x", ref: "x")
        end
        assert_match(/EISERON_PREVIEW_APP_NAME/, err.message)
      end
    end
  end
end
