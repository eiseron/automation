# frozen_string_literal: true

require "test_helper"
require "socket"

module EiseronAutomation
  class GitlabClientTest < Minitest::Test
    HTTP_STATUS = { "200" => "200 OK", "404" => "404 Not Found", "500" => "500 Internal Server Error" }.freeze

    def setup
      @server = TCPServer.new("127.0.0.1", 0)
      @requests = []
      @thread = Thread.new { serve }
      @client = GitlabClient.new(
        api_url: "http://127.0.0.1:#{@server.addr[1]}/api/v4",
        project_id: "123",
        token: "secret"
      )
    end

    def teardown
      @server.close
      @thread.kill
    end

    def test_create_tag_posts_token_and_form_body
      @client.create_tag("v0.1.1", "deadbeef")
      request = @requests.fetch(0)
      assert_equal "POST /api/v4/projects/123/repository/tags HTTP/1.1", request[:line]
      assert_equal "secret", request[:headers]["private-token"]
      assert_includes request[:body], "tag_name=v0.1.1"
      assert_includes request[:body], "ref=deadbeef"
    end

    def test_tag_exists_is_true_on_success_response
      assert @client.tag_exists?("v0.1.1")
      assert_equal "GET /api/v4/projects/123/repository/tags/v0.1.1 HTTP/1.1", @requests.fetch(0)[:line]
    end

    def test_trigger_pipeline_posts_trigger_token_without_private_token
      result = @client.trigger_pipeline(trigger_token: "trig", ref: "main", variables: { "PROD_TAG" => "v1.2.3" })
      request = @requests.fetch(0)
      assert_equal "POST /api/v4/projects/123/trigger/pipeline HTTP/1.1", request[:line]
      refute request[:headers].key?("private-token")
      assert_includes request[:body], "token=trig"
      assert_includes request[:body], "ref=main"
      assert_includes request[:body], CGI.escape("variables[PROD_TAG]")
      assert_instance_of Hash, result
    end

    def test_open_merge_request_iids_accumulates_across_pages
      @stub_bodies = ['[{"iid":7},{"iid":8}]', "[]"]
      assert_equal %w[7 8], @client.open_merge_request_iids
      assert_equal "GET /api/v4/projects/123/merge_requests?state=opened&per_page=100&page=1 HTTP/1.1",
                   @requests.fetch(0)[:line]
      assert_equal 2, @requests.length
    end

    def test_merge_request_state_returns_state_string
      @stub_bodies = ['{"state":"merged"}']
      assert_equal "merged", @client.merge_request_state("9")
    end

    def test_merge_request_state_returns_not_found_when_missing
      @stub_codes = ["404"]
      @stub_bodies = ['{"message":"404 Not found"}']
      assert_equal "not_found", @client.merge_request_state("999")
    end

    def test_find_registry_repository_matches_path_suffix
      @stub_bodies = ['[{"id":10,"path":"group/proj/foo"},{"id":42,"path":"group/proj/preview"}]']
      assert_equal 42, @client.find_registry_repository("/preview")
    end

    def test_list_registry_tags_paginates
      @stub_bodies = ['[{"name":"feat-foo"},{"name":"feat-foo-sha-abc"}]', "[]"]
      assert_equal %w[feat-foo feat-foo-sha-abc], @client.list_registry_tags(42)
    end

    def test_delete_registry_tag_is_idempotent_on_missing_tag
      @stub_codes = ["404"]
      assert @client.delete_registry_tag(42, "feat-foo")
    end

    def test_merge_request_state_returns_error_on_server_failure
      @stub_codes = ["500"]
      @stub_bodies = ['{"message":"500 Server Error"}']
      assert_equal "error", @client.merge_request_state("9")
    end

    def test_merge_request_state_returns_error_on_unknown_state_value
      @stub_bodies = ['{"state":"locked"}']
      assert_equal "error", @client.merge_request_state("9")
    end

    def test_delete_registry_tag_raises_on_non_404_failure
      @stub_codes = ["500"]
      assert_raises(Error) { @client.delete_registry_tag(42, "feat-foo") }
    end

    private

    def serve
      loop do
        socket = @server.accept
        @requests << read_request(socket)
        body = @stub_bodies&.shift || "{}"
        code = @stub_codes&.shift || "200"
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
