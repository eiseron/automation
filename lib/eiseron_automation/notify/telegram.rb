# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EiseronAutomation
  module Notify
    class Telegram
      MAX_TEXT = 3500
      MAX_TRIES = 3
      ENDPOINT = "https://api.telegram.org"

      def initialize(env: ENV, io: $stdout, err: $stderr, http: Net::HTTP)
        @env = env
        @io = io
        @err = err
        @http = http
      end

      def deliver(text:)
        payload = JSON.dump(chat_id: chat_id, text: truncate(text), disable_web_page_preview: true)
        uri = URI.parse("#{ENDPOINT}/bot#{bot_token}/sendMessage")
        try = 0
        loop do
          try += 1
          response = post(uri, payload)
          return true if response.is_a?(Net::HTTPSuccess)

          @err.puts "Notify::Telegram failed (#{response.code} #{response.body}); not retrying"
          return false
        rescue *RETRY_ERRORS => e
          @err.puts "Notify::Telegram network error (try #{try}/#{MAX_TRIES}): #{e.class}: #{e.message}"
          return false if try >= MAX_TRIES
        end
      end

      RETRY_ERRORS = [
        SocketError, IOError, EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET,
        Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout
      ].freeze

      private

      def post(uri, payload)
        @http.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
          request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
          request.body = payload
          http.request(request)
        end
      end

      def truncate(text) = text.length > MAX_TEXT ? "#{text[0, MAX_TEXT - 1]}…" : text
      def bot_token = require_env("TELEGRAM_BOT_TOKEN")
      def chat_id = require_env("TELEGRAM_CHAT_ID")

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
