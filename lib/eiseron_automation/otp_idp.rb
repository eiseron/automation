# frozen_string_literal: true

module EiseronAutomation
  class OtpIdp
    RESOURCE_ADDRESS = "module.eiseron_organization.cloudflare_zero_trust_access_identity_provider.otp[0]"

    def initialize(cf_client:, account_id:, io: $stdout, executor: method(:system), state_lister: nil)
      @cf_client = cf_client
      @account_id = account_id
      @io = io
      @executor = executor
      @state_lister = state_lister || method(:default_state_list)
    end

    def import
      if already_imported?
        @io.puts "OTP IdP already in state, nothing to do."
        return
      end

      idp_id = resolve_idp_id
      import_id = "accounts/#{@account_id}/#{idp_id}"
      @io.puts "Importing OTP IdP #{idp_id}..."
      result = @executor.call("tofu", "import", RESOURCE_ADDRESS, import_id)
      raise Error, "tofu import failed" unless result
    end

    private

    def already_imported?
      @state_lister.call.include?(RESOURCE_ADDRESS)
    end

    def default_state_list
      IO.popen(%w[tofu state list], err: File::NULL, &:read)
    end

    def resolve_idp_id
      providers = @cf_client.identity_providers(@account_id)
      otp = providers.select { |p| p["type"] == "onetimepin" }
      raise Error, "no onetimepin identity provider found in Cloudflare account #{@account_id}" if otp.empty?
      raise Error, "#{otp.length} onetimepin identity providers found; expected exactly 1" if otp.length > 1

      otp.first.fetch("id")
    end
  end
end
