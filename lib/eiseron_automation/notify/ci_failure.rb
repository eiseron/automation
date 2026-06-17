# frozen_string_literal: true

module EiseronAutomation
  module Notify
    class CIFailure
      def initialize(env: ENV, io: $stdout, err: $stderr, telegram: nil)
        @env = env
        @io = io
        @err = err
        @telegram = telegram
      end

      def run
        telegram.deliver(text: message)
      end

      private

      def message
        lines = ["FAIL: #{project} · job #{job_name}"]
        lines << "Pipeline: #{pipeline_url}" unless pipeline_url.empty?
        lines << "Job: #{job_url}" unless job_url.empty?
        ref_line = [ref, sha].reject(&:empty?).join(" @ ")
        lines << "Ref: #{ref_line}" unless ref_line.empty?
        lines.join("\n")
      end

      def telegram = @telegram ||= Telegram.new(env: @env, io: @io, err: @err)
      def project = require_env("CI_PROJECT_PATH")
      def job_name = require_env("CI_JOB_NAME")
      def pipeline_url = @env.fetch("CI_PIPELINE_URL", "")
      def job_url = @env.fetch("CI_JOB_URL", "")
      def ref = @env.fetch("CI_COMMIT_REF_NAME", "")
      def sha = @env.fetch("CI_COMMIT_SHORT_SHA", "")

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
