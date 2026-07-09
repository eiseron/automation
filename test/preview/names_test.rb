# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class NamesTest < Minitest::Test
      def test_project_main_kind_gives_main
        assert_equal "main", Names.project("main", "feat-foo")
      end

      def test_project_mr_kind_prefixes_mr
        assert_equal "mr-feat-foo", Names.project("mr", "feat-foo")
      end

      def test_db_role_naming_uses_app_and_ref
        assert_equal "app_feat_foo", Names.db("app", "feat_foo")
        assert_equal "app_feat_foo_app", Names.app_role("app", "feat_foo")
        assert_equal "app_feat_foo_admin", Names.admin_role("app", "feat_foo")
      end

      def test_shared_roles_use_app_prefix_only
        assert_equal "app_app", Names.shared_app_role("app")
        assert_equal "app_admin", Names.shared_admin_role("app")
      end

      def test_long_refs_collapse_to_hash_under_postgres_63_byte_limit
        long_ref = "a" * 80
        [
          Names.db("app", long_ref),
          Names.app_role("app", long_ref),
          Names.admin_role("app", long_ref)
        ].each { |id| assert_operator id.length, :<=, Names::PG_IDENTIFIER_LIMIT, "identifier #{id} exceeds 63 bytes" }
      end

      def test_two_long_refs_with_same_prefix_do_not_collide
        prefix = "x" * 50
        a = "#{prefix}branch-aaa"
        b = "#{prefix}branch-bbb"
        refute_equal Names.db("app", a), Names.db("app", b)
        refute_equal Names.app_role("app", a), Names.app_role("app", b)
        refute_equal Names.admin_role("app", a), Names.admin_role("app", b)
      end

      def test_app_role_and_admin_role_never_truncate_to_same_string
        long_ref = "a" * 80
        refute_equal Names.app_role("app", long_ref), Names.admin_role("app", long_ref)
      end

      def test_short_refs_pass_through_unchanged
        assert_equal "app_feat-foo", Names.db("app", "feat-foo")
      end
    end
  end
end
