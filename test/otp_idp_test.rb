# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class OtpIdpTest < Minitest::Test
    ACCOUNT_ID = "acct-123"

    FakeCfClient = Struct.new(:providers) do
      def identity_providers(_account_id)
        providers
      end
    end

    def setup
      @io = StringIO.new
      @calls = []
      @executor = lambda { |*args|
        @calls << args
        true
      }
      @state_lister = -> { "" }
    end

    def otp(providers:)
      OtpIdp.new(
        cf_client: FakeCfClient.new(providers),
        account_id: ACCOUNT_ID,
        io: @io,
        executor: @executor,
        state_lister: @state_lister
      )
    end

    def test_import_discovers_idp_and_calls_tofu
      otp(providers: [{ "id" => "idp-abc", "type" => "onetimepin" }]).import

      assert_equal 1, @calls.length
      assert_equal ["tofu", "import", OtpIdp::RESOURCE_ADDRESS, "accounts/#{ACCOUNT_ID}/idp-abc"], @calls.first
    end

    def test_import_prints_idp_id
      otp(providers: [{ "id" => "idp-abc", "type" => "onetimepin" }]).import

      assert_includes @io.string, "idp-abc"
    end

    def test_import_id_uses_accounts_discriminator_prefix
      otp(providers: [{ "id" => "idp-abc", "type" => "onetimepin" }]).import

      import_id = @calls.first.last
      assert_equal "accounts/#{ACCOUNT_ID}/idp-abc", import_id
      assert import_id.start_with?("accounts/"),
             "Cloudflare v5 import id needs the accounts/ discriminator segment"
    end

    def test_import_skips_when_already_in_state
      @state_lister = -> { OtpIdp::RESOURCE_ADDRESS }
      otp(providers: []).import

      assert_includes @io.string, "already in state"
      assert_equal 0, @calls.length
    end

    def test_import_raises_when_no_otp_idp_found
      error = assert_raises(Error) { otp(providers: [{ "id" => "idp-x", "type" => "azureAD" }]).import }

      assert_includes error.message, "no onetimepin"
      assert_equal 0, @calls.length
    end

    def test_import_raises_when_multiple_otp_idps_found
      providers = [
        { "id" => "idp-1", "type" => "onetimepin" },
        { "id" => "idp-2", "type" => "onetimepin" }
      ]

      error = assert_raises(Error) { otp(providers: providers).import }

      assert_includes error.message, "2 onetimepin"
      assert_equal 0, @calls.length
    end

    def test_import_raises_when_tofu_fails
      failing_executor = ->(*_args) { false }
      subject = OtpIdp.new(
        cf_client: FakeCfClient.new([{ "id" => "idp-abc", "type" => "onetimepin" }]),
        account_id: ACCOUNT_ID,
        io: @io,
        executor: failing_executor,
        state_lister: -> { "" }
      )

      error = assert_raises(Error) { subject.import }

      assert_includes error.message, "tofu import failed"
    end
  end
end
