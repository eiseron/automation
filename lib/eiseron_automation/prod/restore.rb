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
        @io.puts "Restoring #{backup_object} into #{accessory} on #{primary_pod} (drill key over stdin)"
        @runner.run_stdin(drill_key, @env.to_h, *exec_command)
      end

      private

      def exec_command
        ["kubectl", "exec", "-i", "-n", pg_namespace, primary_pod, "--",
         "env", "PROD_RESTORE_KEY=#{backup_object}", "PROD_RESTORE_CONFIRM=#{confirm_database}",
         accessory, "eiseron", "db", "restore"]
      end

      def primary_pod
        @primary_pod ||= begin
          pod = @runner.capture(
            "kubectl", "get", "pods", "-n", pg_namespace,
            "-l", "cnpg.io/cluster=#{pg_cluster},cnpg.io/instanceRole=primary",
            "-o", "jsonpath={.items[0].metadata.name}"
          ).strip
          raise Error, "no primary pod found for CloudNativePG cluster #{pg_cluster}" if pod.empty?

          pod
        end
      end

      def drill_key = require_env("PROD_BACKUP_DRILL_KEY")
      def backup_object = require_env("PROD_RESTORE_KEY")
      def confirm_database = require_env("PROD_RESTORE_CONFIRM")
      def accessory = "#{require_env('APP_SERVICE')}-backup"
      def pg_cluster = @env.fetch("PG_CLUSTER", "platform-db")
      def pg_namespace = @env.fetch("PG_NAMESPACE", "platform")

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
