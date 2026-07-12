# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdRestoreTest < Minitest::Test
    class FakeRunner
      attr_reader :stdin_input, :stdin_cmd, :captures

      def initialize(primary: "platform-db-1")
        @captures = []
        @primary = primary
      end

      def run_stdin(input, _env, *cmd)
        @stdin_input = input
        @stdin_cmd = cmd
      end

      def capture(*cmd)
        @captures << cmd
        @primary
      end
    end

    def env(over = {})
      {
        "PROD_BACKUP_DRILL_KEY" => "AGE-SECRET-KEY-1DRILL",
        "APP_SERVICE" => "app",
        "PROD_RESTORE_KEY" => "app/2026-06-13T0200Z.sql.age",
        "PROD_RESTORE_CONFIRM" => "app_prod"
      }.merge(over)
    end

    def restore(vars, runner: FakeRunner.new)
      @runner = runner
      Prod::Restore.new(env: vars, io: StringIO.new, runner: @runner)
    end

    def test_pipes_the_drill_key_over_stdin_not_argv
      restore(env).run
      assert_equal "AGE-SECRET-KEY-1DRILL", @runner.stdin_input
      refute(@runner.stdin_cmd.any? { |arg| arg.include?("AGE-SECRET-KEY-1DRILL") },
             "the drill key must never appear in argv (visible in ps/kubectl audit)")
    end

    def test_execs_db_restore_via_kubectl_on_the_primary_pod
      restore(env).run
      cmd = @runner.stdin_cmd
      assert_equal %w[kubectl exec -i -n platform platform-db-1 --], cmd.first(7)
      assert_equal %w[app-backup eiseron db restore], cmd.last(4)
    end

    def test_primary_pod_is_resolved_by_the_cnpg_primary_role_label
      restore(env).run
      assert_includes @runner.captures.fetch(0), "cnpg.io/cluster=platform-db,cnpg.io/instanceRole=primary"
    end

    def test_no_primary_pod_raises_rather_than_targeting_a_replica
      r = restore(env, runner: FakeRunner.new(primary: ""))
      error = assert_raises(Error) { r.run }
      assert_match(/no primary pod found/, error.message)
    end

    def test_passes_the_non_secret_restore_params_as_exec_env
      restore(env).run
      assert_includes @runner.stdin_cmd, "PROD_RESTORE_KEY=app/2026-06-13T0200Z.sql.age"
      assert_includes @runner.stdin_cmd, "PROD_RESTORE_CONFIRM=app_prod"
    end

    def test_namespace_override_places_the_exec_in_that_namespace
      restore(env("PG_NAMESPACE" => "db")).run
      assert_equal(%w[kubectl exec -i -n db platform-db-1 --], @runner.stdin_cmd.first(7))
    end

    def test_cluster_override_selects_that_cnpg_primary
      restore(env("PG_CLUSTER" => "main-db")).run
      assert_includes @runner.captures.fetch(0), "cnpg.io/cluster=main-db,cnpg.io/instanceRole=primary"
    end

    def test_aborts_without_the_drill_key
      r = restore(env.except("PROD_BACKUP_DRILL_KEY"))
      assert_raises(Error) { r.run }
    end
  end
end
