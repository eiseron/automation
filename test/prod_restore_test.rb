# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdRestoreTest < Minitest::Test
    class FakeRunner
      attr_reader :stdin_input, :stdin_cmd

      def run_stdin(input, _env, *cmd)
        @stdin_input = input
        @stdin_cmd = cmd
      end
    end

    def env(over = {})
      {
        "PROD_BACKUP_DRILL_KEY" => "AGE-SECRET-KEY-1DRILL",
        "APP_SERVICE" => "app",
        "PROD_HOST" => "10.0.0.1",
        "PROD_RESTORE_KEY" => "app/2026-06-13T0200Z.sql.age",
        "PROD_RESTORE_CONFIRM" => "app_prod"
      }.merge(over)
    end

    def restore(vars)
      @runner = FakeRunner.new
      Prod::Restore.new(env: vars, io: StringIO.new, runner: @runner)
    end

    def test_pipes_the_drill_key_over_stdin_not_argv
      restore(env).run
      assert_equal "AGE-SECRET-KEY-1DRILL", @runner.stdin_input
      refute_includes @runner.stdin_cmd, "AGE-SECRET-KEY-1DRILL"
      refute(@runner.stdin_cmd.any? { |arg| arg.include?("AGE-SECRET-KEY-1DRILL") },
             "the drill key must never appear in argv (visible in ps/docker inspect)")
    end

    def test_execs_db_restore_in_the_running_backup_accessory
      restore(env).run
      cmd = @runner.stdin_cmd
      assert_equal %w[ssh deploy@10.0.0.1 docker exec -i], cmd.first(5)
      assert_equal %w[app-backup eiseron db restore], cmd.last(4)
    end

    def test_passes_the_non_secret_restore_params_as_exec_env
      restore(env).run
      assert_includes @runner.stdin_cmd, "PROD_RESTORE_KEY=app/2026-06-13T0200Z.sql.age"
      assert_includes @runner.stdin_cmd, "PROD_RESTORE_CONFIRM=app_prod"
    end

    def test_aborts_without_the_drill_key
      r = restore(env.except("PROD_BACKUP_DRILL_KEY"))
      assert_raises(Error) { r.run }
    end
  end
end
