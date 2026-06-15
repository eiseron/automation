# frozen_string_literal: true

module EiseronAutomation
  module Prod
    class Restore
      def initialize(env: ENV, io: $stdout, runner: Runner.new)
        @env = env
        @io = io
        @runner = runner
      end

      def run
        @io.puts "Restoring #{backup_object} into #{accessory} on #{host} (drill key over stdin)"
        @runner.run_stdin(drill_key, @env.to_h, *exec_command)
      end

      private

      def exec_command
        ["ssh", "#{ssh_user}@#{host}", "docker", "exec", "-i",
         "-e", "PROD_RESTORE_KEY=#{backup_object}",
         "-e", "PROD_RESTORE_CONFIRM=#{confirm_database}",
         accessory, "eiseron", "db", "restore"]
      end

      def drill_key = require_env("PROD_BACKUP_DRILL_KEY")
      def backup_object = require_env("PROD_RESTORE_KEY")
      def confirm_database = require_env("PROD_RESTORE_CONFIRM")
      def accessory = "#{require_env('APP_SERVICE')}-backup"
      def host = require_env("PROD_HOST")
      def ssh_user = @env.fetch("DEPLOY_SSH_USER", "deploy")

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
