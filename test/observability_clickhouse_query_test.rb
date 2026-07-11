# frozen_string_literal: true

require "test_helper"

class ObservabilityClickHouseQueryTest < Minitest::Test
  def query(args: [], env: {})
    EiseronAutomation::Observability::ClickHouseQuery.new(env: env, io: StringIO.new, args: args)
  end

  def test_duration_seconds_reads_hours
    assert_equal 3_600, query.duration_seconds("1h")
  end

  def test_duration_seconds_reads_minutes
    assert_equal 1_800, query.duration_seconds("30m")
  end

  def test_duration_seconds_reads_days
    assert_equal 172_800, query.duration_seconds("2d")
  end

  def test_duration_seconds_rejects_garbage
    assert_raises(EiseronAutomation::Error) { query.duration_seconds("later") }
  end

  def test_table_defaults_to_otel_database
    assert_equal "otel.otel_logs", query.table
  end

  def test_table_honors_database_override
    assert_equal "obs.otel_logs", query(env: { "CLICKHOUSE_DATABASE" => "obs" }).table
  end

  def test_tail_sql_binds_the_service_as_a_typed_param
    assert_includes query.build_tail_sql("15m"), "ServiceName = {svc:String}"
  end

  def test_tail_sql_filters_by_the_requested_window
    assert_includes query.build_tail_sql("2h"), "INTERVAL 7200 SECOND"
  end

  def test_tail_sql_defaults_the_limit
    assert_includes query.build_tail_sql("15m"), "LIMIT 100"
  end

  def test_tail_sql_honors_the_size_flag
    assert_includes query(args: ["--size", "5"]).build_tail_sql("15m"), "LIMIT 5"
  end

  def test_search_without_sql_raises_usage
    assert_raises(EiseronAutomation::Error) { query(args: ["--last", "1h"]).search }
  end

  def test_tail_without_service_raises_usage
    assert_raises(EiseronAutomation::Error) { query(args: ["--last", "1h"]).tail }
  end
end
