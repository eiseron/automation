# frozen_string_literal: true

require "test_helper"
require "socket"
require "json"

module EiseronAutomation
  class CloudflareClientTest < Minitest::Test
    HTTP_STATUS = { "200" => "200 OK", "400" => "400 Bad Request", "500" => "500 Internal Server Error" }.freeze

    def setup
      @server = TCPServer.new("127.0.0.1", 0)
      @requests = []
      @stub_bodies = []
      @stub_codes = []
      @thread = Thread.new { serve }
      port = @server.addr[1]
      @client = CloudflareClient.new(
        token: "test-token",
        base: "http://127.0.0.1:#{port}"
      )
    end

    def teardown
      @server.close
      @thread.kill
    end

    def test_deployments_returns_result_array_on_success
      @stub_bodies << JSON.dump("result" => [{ "id" => "dep1" }], "result_info" => { "total_count" => 1 })
      @stub_codes << "200"

      result = @client.deployments("acct-1", "my-project")

      assert_equal [{ "id" => "dep1" }], result
    end

    def test_deployments_paginates_until_all_results_fetched
      full_page = Array.new(25) { |i| { "id" => "dep#{i}" } }
      page_one = JSON.dump("result" => full_page, "result_info" => { "total_count" => 26 })
      page_two = JSON.dump("result" => [{ "id" => "dep25" }], "result_info" => { "total_count" => 26 })
      @stub_bodies << page_one << page_two
      @stub_codes << "200" << "200"

      result = @client.deployments("acct-1", "my-project")

      assert_equal 26, result.length
      assert_equal 2, @requests.length
    end

    def test_deployments_uses_page_param_without_env_filter
      @stub_bodies << JSON.dump("result" => [], "result_info" => { "total_count" => 0 })
      @stub_codes << "200"

      @client.deployments("acct-1", "my-project")
      request = @requests.fetch(0)

      assert_includes request[:line], "per_page=25"
      assert_includes request[:line], "page=1"
      refute_includes request[:line], "env=preview"
    end

    def test_deployments_sends_bearer_token
      @stub_bodies << JSON.dump("result" => [], "result_info" => { "total_count" => 0 })
      @stub_codes << "200"

      @client.deployments("acct-1", "my-project")

      assert_equal "Bearer test-token", @requests.fetch(0)[:headers]["authorization"]
    end

    def test_deployments_stops_after_empty_page_when_result_info_absent
      @stub_bodies << JSON.dump("result" => [{ "id" => "dep1" }])
      @stub_codes << "200"

      result = @client.deployments("acct-1", "my-project")

      assert_equal [{ "id" => "dep1" }], result
      assert_equal 1, @requests.length
    end

    def test_deployments_raises_with_body_on_failure
      @stub_bodies << '{"errors":[{"message":"Invalid token"}]}'
      @stub_codes << "400"

      error = assert_raises(Error) { @client.deployments("acct-1", "my-project") }

      assert_includes error.message, "400"
      assert_includes error.message, "Invalid token"
    end

    def test_delete_deployment_returns_on_success
      @stub_bodies << ""
      @stub_codes << "200"

      @client.delete_deployment("acct-1", "my-project", "dep1")

      request = @requests.fetch(0)
      assert_includes request[:line], "DELETE"
      assert_includes request[:line], "/dep1"
    end

    def test_identity_providers_returns_result_array_on_success
      @stub_bodies << JSON.dump("success" => true, "result" => [{ "id" => "idp-1", "type" => "onetimepin" }])
      @stub_codes << "200"

      result = @client.identity_providers("acct-1")

      assert_equal [{ "id" => "idp-1", "type" => "onetimepin" }], result
    end

    def test_identity_providers_sends_bearer_token
      @stub_bodies << JSON.dump("success" => true, "result" => [])
      @stub_codes << "200"

      @client.identity_providers("acct-1")

      assert_equal "Bearer test-token", @requests.fetch(0)[:headers]["authorization"]
    end

    def test_identity_providers_raises_on_http_failure
      @stub_bodies << '{"errors":[{"message":"Unauthorized"}]}'
      @stub_codes << "400"

      error = assert_raises(Error) { @client.identity_providers("acct-1") }

      assert_includes error.message, "400"
    end

    def test_identity_providers_raises_on_api_error
      @stub_bodies << JSON.dump("success" => false, "errors" => [{ "message" => "bad token" }])
      @stub_codes << "200"

      error = assert_raises(Error) { @client.identity_providers("acct-1") }

      assert_includes error.message, "bad token"
    end

    def test_delete_deployment_raises_with_body_on_failure
      @stub_bodies << '{"errors":[{"message":"Deployment not found"}]}'
      @stub_codes << "400"

      error = assert_raises(Error) { @client.delete_deployment("acct-1", "my-project", "dep1") }

      assert_includes error.message, "400"
      assert_includes error.message, "Deployment not found"
    end

    private

    def serve
      loop do
        socket = @server.accept
        @requests << read_request(socket)
        body = @stub_bodies.shift || "{}"
        code = @stub_codes.shift || "200"
        status = HTTP_STATUS.fetch(code, "200 OK")
        socket.print "HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
        socket.close
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def read_request(socket)
      line = socket.gets
      headers = read_headers(socket)
      length = headers["content-length"].to_i
      body = length.positive? ? socket.read(length) : ""
      { line: line.strip, headers: headers, body: body }
    end

    def read_headers(socket)
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        key, value = line.split(":", 2)
        headers[key.downcase] = value.strip
      end
      headers
    end
  end
end
