# frozen_string_literal: true

require "test_helper"

class ObservabilityQueryTest < Minitest::Test
  def query(args: [], env: {}, clock: -> { 1_700.0 })
    EiseronAutomation::Observability::Query.new(env: env, io: StringIO.new, args: args, clock: clock)
  end

  def test_duration_seconds_reads_hours
    assert_equal 3_600, query.duration_seconds("1h")
  end

  def test_duration_seconds_reads_minutes_and_days
    assert_equal 1_800, query.duration_seconds("30m")
    assert_equal 172_800, query.duration_seconds("2d")
  end

  def test_duration_seconds_rejects_garbage
    assert_raises(EiseronAutomation::Error) { query.duration_seconds("later") }
  end

  def test_window_returns_microsecond_bounds_relative_to_now
    from, to = query(clock: -> { 1_700.0 }).window("1h")
    assert_equal 1_700_000_000, to
    assert_equal 1_700_000_000 - 3_600_000_000, from
  end

  def test_search_body_wraps_the_sql_and_bounds
    body = query.search_body("SELECT 1", 10, 20)
    assert_equal "SELECT 1", body.dig(:query, :sql)
    assert_equal 10, body.dig(:query, :start_time)
    assert_equal 20, body.dig(:query, :end_time)
  end

  def test_size_defaults_when_no_flag
    assert_equal 100, query.search_body("x", 0, 1).dig(:query, :size)
  end

  def test_size_honors_the_flag
    sized = query(args: ["--size", "5"])
    assert_equal 5, sized.search_body("x", 0, 1).dig(:query, :size)
  end

  def test_search_without_sql_raises_usage
    assert_raises(EiseronAutomation::Error) { query(args: ["--last", "1h"]).search }
  end

  def test_authorization_prepends_basic_to_raw_token
    authed = query(env: { "OBSERVABILITY_TOKEN" => "abc123" })
    assert_equal "Basic abc123", authed.authorization
  end

  def test_authorization_keeps_existing_scheme
    authed = query(env: { "OBSERVABILITY_TOKEN" => "Bearer tok" })
    assert_equal "Bearer tok", authed.authorization
  end

  def test_authorization_requires_token
    assert_raises(EiseronAutomation::Error) { query(env: {}).authorization }
  end
end
