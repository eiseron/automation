# frozen_string_literal: true

require "digest"

module EiseronAutomation
  module Preview
    module Names
      PG_IDENTIFIER_LIMIT = 63
      HASH_LENGTH = 8

      module_function

      def project(kind, ref)
        kind == "main" ? "main" : "mr-#{ref}"
      end

      def db(app, ref) = "#{app}_#{compact(app, ref)}"
      def app_role(app, ref) = "#{app}_#{compact(app, ref)}_app"
      def admin_role(app, ref) = "#{app}_#{compact(app, ref)}_admin"
      def shared_app_role(app) = "#{app}_app"
      def shared_admin_role(app) = "#{app}_admin"

      def compact(app, ref)
        budget = PG_IDENTIFIER_LIMIT - app.length - 1 - "_admin".length
        return ref if ref.length <= budget

        prefix = ref[0, budget - HASH_LENGTH - 1]
        "#{prefix}_#{Digest::SHA1.hexdigest(ref)[0, HASH_LENGTH]}"
      end
    end
  end
end
