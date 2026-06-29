# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class DbHistoryTest < Minitest::Test
    def test_parses_plain_keys_without_a_hash
      history = DB::History.parse("app/2026-06-13T030000Z.sql.age\n")
      assert_equal ["app/2026-06-13T030000Z.sql.age"], history.keys
      assert_nil history.sha256_for("app/2026-06-13T030000Z.sql.age")
    end

    def test_parses_a_tab_separated_key_and_hash
      history = DB::History.parse("app/2026-06-13T030000Z.sql.age\tabc\n")
      assert_equal "abc", history.sha256_for("app/2026-06-13T030000Z.sql.age")
    end

    def test_ignores_blank_and_non_backup_lines
      history = DB::History.parse("\napp/notes.txt\napp/2026-06-13T030000Z.sql.age\n")
      assert_equal ["app/2026-06-13T030000Z.sql.age"], history.keys
    end

    def test_treats_nil_text_as_empty
      assert DB::History.parse(nil).empty?
    end

    def test_latest_is_the_lexicographically_greatest_key
      history = DB::History.parse("app/2026-06-10T030000Z.sql.age\napp/2026-06-13T030000Z.sql.age\n")
      assert_equal "app/2026-06-13T030000Z.sql.age", history.latest.key
    end

    def test_add_appends_an_entry_with_its_hash
      history = DB::History.parse("app/2026-06-10T030000Z.sql.age\n")
      grown = history.add("app/2026-06-13T030000Z.sql.age", "h2")
      assert_equal "h2", grown.sha256_for("app/2026-06-13T030000Z.sql.age")
    end

    def test_without_drops_the_named_keys
      history = DB::History.parse("app/a.sql.age\tx\napp/b.sql.age\ty\n")
      assert_equal ["app/b.sql.age"], history.without(["app/a.sql.age"]).keys
    end

    def test_dump_round_trips_keys_and_hashes
      text = "app/a.sql.age\napp/b.sql.age\ty\n"
      assert_equal text, DB::History.parse(text).dump
    end

    def test_dump_of_an_empty_history_is_blank
      assert_equal "", DB::History.parse("").dump
    end
  end
end
