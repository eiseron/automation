# frozen_string_literal: true

require "cgi"
require "net/http"
require "socket"
require "timeout"

module EiseronAutomation
  module Preview
    class Registry
      def initialize(env:, io:, client: nil)
        @env = env
        @io = io
        @client = client
      end

      def delete_preview_tag(ref)
        repo_id = client.find_registry_repository("/preview")
        return @io.puts "[gitlab] no /preview registry repo yet; skipping tags for #{ref}" unless repo_id

        delete_one(repo_id, ref)
        client.list_registry_tags(repo_id).grep(/\A#{Regexp.escape(ref)}-sha-/).each do |tag|
          delete_one(repo_id, tag)
        end
      rescue Error, IOError, SystemCallError, SocketError, Timeout::Error, Net::HTTPError => e
        @io.puts "[gitlab] preview-tag cleanup partial (#{e.class}: #{e.message}); leaving rest for retry"
      end

      def mr_state(iid)
        client.merge_request_state(iid)
      end

      private

      def delete_one(repo_id, tag)
        client.delete_registry_tag(repo_id, tag)
        @io.puts "[gitlab] deleted tag #{tag}"
      end

      def client
        @client ||= GitlabClient.new(
          api_url: require_env("CI_API_V4_URL"),
          project_id: CGI.escape(require_env("PREVIEW_PROJECT_PATH")),
          token: require_env("GITLAB_API_TOKEN")
        )
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
