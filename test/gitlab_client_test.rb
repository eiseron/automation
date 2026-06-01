# frozen_string_literal: true

require "test_helper"
require "socket"

module EiseronAutomation
  # Drives the real Net::HTTP client against an in-process TCP stub so the wire
  # format (verb, path encoding, auth header, form body) is asserted directly.
  class GitlabClientTest < Minitest::Test
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

    def test_delete_tag_protection_url_encodes_wildcard
      @client.delete_tag_protection
      request = @requests.fetch(0)
      assert_equal "DELETE /api/v4/projects/123/protected_tags/%2A HTTP/1.1", request[:line]
    end

    def test_tag_exists_is_true_on_success_response
      assert @client.tag_exists?("v0.1.1")
      assert_equal "GET /api/v4/projects/123/repository/tags/v0.1.1 HTTP/1.1", @requests.fetch(0)[:line]
    end

    private

    def serve
      loop do
        socket = @server.accept
        @requests << read_request(socket)
        socket.print "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
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
