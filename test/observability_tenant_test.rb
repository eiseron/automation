# frozen_string_literal: true

require "test_helper"

class ObservabilityTenantTest < Minitest::Test
  def tenant(args: [], env: {})
    EiseronAutomation::Observability::Tenant.new(env: env, io: StringIO.new, args: args)
  end

  def statements(product)
    tenant(args: [product]).build_statements(product, "deadbeef")
  end

  def test_valid_product_accepts_a_lowercase_slug
    assert_equal "afinados", tenant(args: ["afinados"]).valid_product
  end

  def test_valid_product_rejects_injection_characters
    assert_raises(EiseronAutomation::Error) { tenant(args: ["a; DROP"]).valid_product }
  end

  def test_valid_product_requires_a_positional_argument
    assert_raises(EiseronAutomation::Error) { tenant(args: ["--flag"]).valid_product }
  end

  def test_reader_name_is_scoped_to_the_product
    assert_equal "holter_reader", tenant.reader("holter")
  end

  def test_creates_the_reader_with_a_hashed_password
    assert_includes statements("afinados").first,
                    "CREATE USER IF NOT EXISTS afinados_reader IDENTIFIED WITH sha256_hash BY 'deadbeef'"
  end

  def test_grants_select_on_the_database
    assert_includes statements("afinados"), "GRANT SELECT ON otel.* TO afinados_reader"
  end

  def test_row_policy_scopes_logs_to_the_product_service
    logs_policy = statements("afinados").find { |sql| sql.include?("otel.otel_logs") }
    assert_includes logs_policy, "USING ServiceName = 'afinados' TO afinados_reader"
  end

  def test_provisions_a_row_policy_for_every_otel_table
    policies = statements("afinados").select { |sql| sql.start_with?("CREATE ROW POLICY") }
    assert_equal EiseronAutomation::Observability::Tenant::TABLES.size, policies.size
  end

  def test_provision_requires_the_reader_password_env
    assert_raises(EiseronAutomation::Error) { tenant(args: ["afinados"]).provision }
  end
end
