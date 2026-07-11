# frozen_string_literal: true

module EiseronAutomation
  module Observability
    class Login
      def initialize(env:, io:, args: [])
        @env = env
        @io = io
        @args = args
      end

      def run
        client_id = require_option("--client-id")
        client_secret = require_secret
        Config.new(@env).update(
          "CF_ACCESS_CLIENT_ID" => client_id,
          "CF_ACCESS_CLIENT_SECRET" => client_secret
        )
        @io.puts("logged in: CF Access service token stored for #{client_id}")
      end

      private

      def require_option(flag)
        index = @args.index(flag)
        value = index && @args[index + 1]
        value or raise Error, usage
      end

      def require_secret
        @env["CF_ACCESS_CLIENT_SECRET"] or raise Error, usage
      end

      def usage
        "usage: obs login --client-id <id> (secret read from CF_ACCESS_CLIENT_SECRET, never a CLI flag)"
      end
    end
  end
end
