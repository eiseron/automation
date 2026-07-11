# frozen_string_literal: true

require "test_helper"

class ObservabilityConfigTest < Minitest::Test
  def config(env)
    EiseronAutomation::Observability::Config.new(env)
  end

  def test_merged_env_prefers_the_process_env_over_stored
    Dir.mktmpdir do |dir|
      path = File.join(dir, "obs.json")
      config({ "EISERON_OBS_CONFIG" => path }).update("CF_ACCESS_CLIENT_ID" => "stored")
      merged = config({ "EISERON_OBS_CONFIG" => path, "CF_ACCESS_CLIENT_ID" => "env" }).merged_env
      assert_equal "env", merged["CF_ACCESS_CLIENT_ID"]
    end
  end

  def test_merged_env_falls_back_to_stored_when_env_absent
    Dir.mktmpdir do |dir|
      path = File.join(dir, "obs.json")
      config({ "EISERON_OBS_CONFIG" => path }).update("CF_ACCESS_CLIENT_SECRET" => "stored-secret")
      merged = config({ "EISERON_OBS_CONFIG" => path }).merged_env
      assert_equal "stored-secret", merged["CF_ACCESS_CLIENT_SECRET"]
    end
  end

  def test_update_merges_without_dropping_existing_keys
    Dir.mktmpdir do |dir|
      path = File.join(dir, "obs.json")
      config({ "EISERON_OBS_CONFIG" => path }).update("CF_ACCESS_CLIENT_ID" => "id")
      config({ "EISERON_OBS_CONFIG" => path }).update("CF_ACCESS_CLIENT_SECRET" => "secret")
      assert_equal "id", config({ "EISERON_OBS_CONFIG" => path }).load["CF_ACCESS_CLIENT_ID"]
    end
  end

  def test_update_writes_owner_only_permissions
    Dir.mktmpdir do |dir|
      path = File.join(dir, "obs.json")
      config({ "EISERON_OBS_CONFIG" => path }).update("CF_ACCESS_CLIENT_ID" => "id")
      assert_equal "600", format("%o", File.stat(path).mode & 0o777)
    end
  end

  def test_load_is_empty_without_a_config_file
    Dir.mktmpdir do |dir|
      assert_empty config({ "EISERON_OBS_CONFIG" => File.join(dir, "absent.json") }).load
    end
  end
end
