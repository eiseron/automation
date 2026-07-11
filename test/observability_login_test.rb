# frozen_string_literal: true

require "test_helper"

class ObservabilityLoginTest < Minitest::Test
  def login(args, env)
    EiseronAutomation::Observability::Login.new(env: env, io: StringIO.new, args: args)
  end

  def test_run_requires_the_client_id
    Dir.mktmpdir do |dir|
      env = { "EISERON_OBS_CONFIG" => File.join(dir, "o.json"), "CF_ACCESS_CLIENT_SECRET" => "s" }
      assert_raises(EiseronAutomation::Error) { login([], env).run }
    end
  end

  def test_run_requires_the_secret_from_the_environment
    Dir.mktmpdir do |dir|
      env = { "EISERON_OBS_CONFIG" => File.join(dir, "o.json") }
      assert_raises(EiseronAutomation::Error) { login(["--client-id", "i"], env).run }
    end
  end

  def test_run_persists_the_client_id
    Dir.mktmpdir do |dir|
      env = { "EISERON_OBS_CONFIG" => File.join(dir, "o.json"), "CF_ACCESS_CLIENT_SECRET" => "csecret" }
      login(["--client-id", "cid"], env).run
      assert_equal "cid", EiseronAutomation::Observability::Config.new(env).load["CF_ACCESS_CLIENT_ID"]
    end
  end

  def test_run_persists_the_secret_read_from_the_environment
    Dir.mktmpdir do |dir|
      env = { "EISERON_OBS_CONFIG" => File.join(dir, "o.json"), "CF_ACCESS_CLIENT_SECRET" => "csecret" }
      login(["--client-id", "cid"], env).run
      assert_equal "csecret", EiseronAutomation::Observability::Config.new(env).load["CF_ACCESS_CLIENT_SECRET"]
    end
  end
end
