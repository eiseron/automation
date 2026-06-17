# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class NotifyTelegramTest < Minitest::Test
    Response = Struct.new(:code, :body) do
      def is_a?(klass)
        klass == Net::HTTPSuccess && code.to_i.between?(200, 299)
      end
    end

    class FakeHTTP
      attr_reader :requests

      def initialize(responses)
        @responses = responses.dup
        @requests = []
      end

      def start(host, port, **)
        @host = host
        @port = port
        yield self
      end

      def request(req)
        @requests << { host: @host, port: @port, uri: req.path, body: JSON.parse(req.body) }
        response = @responses.shift
        raise response if response.is_a?(StandardError)

        response
      end
    end

    def env(over = {})
      {
        "TELEGRAM_BOT_TOKEN" => "123:ABC",
        "TELEGRAM_CHAT_ID" => "-1001234567890"
      }.merge(over)
    end

    def deliver(text:, responses:, vars: env)
      err = StringIO.new
      http = FakeHTTP.new(responses)
      ok = Notify::Telegram.new(env: vars, io: StringIO.new, err: err, http: http).deliver(text: text)
      [ok, http, err.string]
    end

    def test_returns_true_and_posts_the_payload_when_telegram_returns_2xx
      ok, http, = deliver(text: "hello", responses: [Response.new(200, "{\"ok\":true}")])
      assert_equal true, ok
      body = http.requests.fetch(0)[:body]
      assert_equal "-1001234567890", body["chat_id"]
      assert_equal "hello", body["text"]
      assert_equal true, body["disable_web_page_preview"]
    end

    def test_targets_the_telegram_send_message_endpoint_with_the_bot_token
      _, http, = deliver(text: "x", responses: [Response.new(200, "")])
      assert_equal "api.telegram.org", http.requests.fetch(0)[:host]
      assert_equal "/bot123:ABC/sendMessage", http.requests.fetch(0)[:uri]
    end

    def test_truncates_text_to_3500_characters_with_an_ellipsis
      _, http, = deliver(text: "x" * 5000, responses: [Response.new(200, "")])
      text = http.requests.fetch(0)[:body]["text"]
      assert_equal 3500, text.length
      assert text.end_with?("…")
    end

    def test_short_text_is_not_truncated
      _, http, = deliver(text: "small", responses: [Response.new(200, "")])
      assert_equal "small", http.requests.fetch(0)[:body]["text"]
    end

    def test_4xx_returns_false_and_logs_the_response_without_retrying
      ok, http, err = deliver(text: "x", responses: [Response.new(400, "{\"description\":\"Bad chat\"}")])
      assert_equal false, ok
      assert_equal 1, http.requests.length
      assert_match("Notify::Telegram failed", err)
      assert_match("400", err)
    end

    def test_network_errors_retry_up_to_three_times_then_return_false
      ok, http, err = deliver(text: "x", responses: Array.new(3, SocketError.new("getaddrinfo")))
      assert_equal false, ok
      assert_equal 3, http.requests.length
      assert_equal 3, err.scan("network error").length
    end

    def test_network_error_then_success_returns_true
      ok, http, err = deliver(text: "x", responses: [SocketError.new("transient"), Response.new(200, "")])
      assert_equal true, ok
      assert_equal 2, http.requests.length
      assert_match(%r{network error.*try 1/3}, err)
    end

    def test_missing_bot_token_raises
      telegram = Notify::Telegram.new(
        env: env.except("TELEGRAM_BOT_TOKEN"), io: StringIO.new, err: StringIO.new, http: FakeHTTP.new([])
      )
      error = assert_raises(Error) { telegram.deliver(text: "x") }
      assert_match(/TELEGRAM_BOT_TOKEN is empty/, error.message)
    end

    def test_missing_chat_id_raises
      telegram = Notify::Telegram.new(
        env: env.except("TELEGRAM_CHAT_ID"), io: StringIO.new, err: StringIO.new, http: FakeHTTP.new([])
      )
      error = assert_raises(Error) { telegram.deliver(text: "x") }
      assert_match(/TELEGRAM_CHAT_ID is empty/, error.message)
    end
  end
end
