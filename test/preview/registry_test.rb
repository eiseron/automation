# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class RegistryTest < Minitest::Test
      class FakeClient
        attr_reader :deleted

        def initialize(repo_id: 42, tags: [])
          @repo_id = repo_id
          @tags = tags
          @deleted = []
        end

        def find_registry_repository(_suffix)
          @repo_id
        end

        def list_registry_tags(_id)
          @tags
        end

        def delete_registry_tag(_id, name)
          @deleted << name
        end

        def merge_request_state(_iid)
          "opened"
        end
      end

      def test_delete_preview_tag_removes_ref_and_sha_stamped_tags
        client = FakeClient.new(tags: %w[feat-foo feat-foo-sha-abc feat-foo-sha-def other])
        Registry.new(env: {}, io: StringIO.new, client: client).delete_preview_tag("feat-foo")
        assert_equal %w[feat-foo feat-foo-sha-abc feat-foo-sha-def], client.deleted
      end

      def test_delete_preview_tag_skips_when_repo_missing
        client = FakeClient.new(repo_id: nil)
        io = StringIO.new
        Registry.new(env: {}, io: io, client: client).delete_preview_tag("feat-foo")
        assert_empty client.deleted
        assert_match(%r{no /preview registry repo}, io.string)
      end

      def test_mr_state_delegates_to_client
        client = FakeClient.new
        assert_equal "opened", Registry.new(env: {}, io: StringIO.new, client: client).mr_state("9")
      end

      def test_delete_preview_tag_swallows_partial_errors
        raising_client = Class.new(FakeClient) do
          def list_registry_tags(_id)
            raise Error, "rate limited"
          end
        end.new
        io = StringIO.new
        Registry.new(env: {}, io: io, client: raising_client).delete_preview_tag("feat-foo")
        assert_match(/cleanup partial/, io.string)
      end

      def test_delete_preview_tag_swallows_network_errors
        raising_client = Class.new(FakeClient) do
          def find_registry_repository(_suffix)
            raise SocketError, "connection refused"
          end
        end.new
        io = StringIO.new
        Registry.new(env: {}, io: io, client: raising_client).delete_preview_tag("feat-foo")
        assert_match(/SocketError/, io.string)
      end

      def test_delete_preview_tag_only_matches_anchored_ref_prefix
        client = FakeClient.new(tags: %w[feat-foo feat-foobar-sha-1 xfeat-foo-sha-1 feat-foo-sha-abc])
        Registry.new(env: {}, io: StringIO.new, client: client).delete_preview_tag("feat-foo")
        assert_equal %w[feat-foo feat-foo-sha-abc], client.deleted
      end
    end
  end
end
