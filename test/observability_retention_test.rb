# frozen_string_literal: true

require "test_helper"

class ObservabilityRetentionTest < Minitest::Test
  def retention(args: [], env: {})
    EiseronAutomation::Observability::Retention.new(env: env, io: StringIO.new, args: args)
  end

  def test_ttl_expr_maps_days_to_clickhouse_interval
    assert_equal "toDateTime(Timestamp) + INTERVAL 7 DAY", retention.ttl_expr("Timestamp", "7d")
  end

  def test_ttl_expr_maps_hours_to_clickhouse_interval
    assert_equal "toDateTime(TimeUnix) + INTERVAL 12 HOUR", retention.ttl_expr("TimeUnix", "12h")
  end

  def test_ttl_expr_rejects_a_malformed_window
    assert_raises(EiseronAutomation::Error) { retention.ttl_expr("Timestamp", "forever") }
  end

  def test_window_defaults_per_signal
    assert_equal "3d", retention.window("traces")
  end

  def test_window_honors_the_signal_flag
    assert_equal "1d", retention(args: ["--traces", "1d"]).window("traces")
  end

  def test_logs_statement_alters_the_logs_table_by_timestamp
    logs = retention.build_statements.find { |sql| sql.include?("otel_logs") }
    assert_equal "ALTER TABLE otel.otel_logs MODIFY TTL toDateTime(Timestamp) + INTERVAL 7 DAY", logs
  end

  def test_metrics_statements_use_the_time_unix_column
    metrics = retention.build_statements.select { |sql| sql.include?("otel_metrics") }
    assert(metrics.all? { |sql| sql.include?("MODIFY TTL toDateTime(TimeUnix) + INTERVAL") })
  end

  def test_provisions_a_statement_for_every_signal_table
    expected = EiseronAutomation::Observability::Retention::SIGNALS.values.sum { |meta| meta[:tables].size }
    assert_equal expected, retention.build_statements.size
  end

  def test_honored_flag_reaches_the_traces_statement
    traces = retention(args: ["--traces", "1d"]).build_statements.find { |sql| sql.include?("otel_traces") }
    assert_includes traces, "INTERVAL 1 DAY"
  end
end
