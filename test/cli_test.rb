# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class CLITest < Minitest::Test
    def run_cli(argv, env: {})
      err = StringIO.new
      code = CLI.new(argv, env: env, io: StringIO.new, err: err).run
      [code, err.string]
    end

    def test_unknown_command_exits_nonzero_with_reason
      code, err = run_cli(%w[bogus cmd])
      assert_equal 1, code
      assert_match(/unknown command 'bogus cmd'/, err)
    end

    def test_release_tag_aborts_without_token_before_any_api_call
      code, err = run_cli(%w[release tag], env: {})
      assert_equal 1, code
      assert_match(/RELEASE_TOKEN is empty/, err)
    end

    def test_release_tag_uses_release_token_then_needs_ci_api_url
      code, err = run_cli(%w[release tag], env: { "RELEASE_TOKEN" => "a-token" })
      assert_equal 1, code
      assert_match(/CI_API_V4_URL is empty/, err)
    end
  end
end
