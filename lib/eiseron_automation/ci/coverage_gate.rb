# frozen_string_literal: true

module EiseronAutomation
  module CI
    class CoverageGate
      DEFAULT_JOB = "test"

      def initialize(env: ENV, io: $stdout, err: $stderr, args: [], client: nil)
        @env = env
        @io = io
        @err = err
        @args = args
        @client = client
      end

      def run
        current = current_coverage
        return unless current

        target = target_coverage
        return unless target

        enforce(current, target)
      end

      private

      def current_coverage
        cov = coverage_for(require_env("CI_PIPELINE_ID"))
        @io.puts "No coverage data for current pipeline - skipping" unless cov
        cov
      end

      def target_coverage
        pipeline = client.last_successful_pipeline(target_branch)
        unless pipeline
          @io.puts "No successful pipeline on target branch (#{target_branch}) - skipping"
          return
        end

        cov = coverage_for(pipeline.fetch("id").to_s)
        @io.puts "No coverage data on target branch (#{target_branch}) - skipping" unless cov
        cov
      end

      def enforce(current, target)
        @io.puts "Coverage: current=#{current}% target(#{target_branch})=#{target}%"
        raise Error, "coverage dropped (#{current}% < #{target}%)" if current < target

        @io.puts "OK: coverage maintained (#{current}% >= #{target}%)"
      end

      def coverage_for(pipeline_id)
        parse_coverage(client.pipeline_jobs(pipeline_id), job_name)
      end

      def parse_coverage(jobs, name)
        job = jobs.find { |j| j["name"] == name }
        job&.fetch("coverage")&.to_f
      end

      def target_branch
        require_env("CI_MERGE_REQUEST_TARGET_BRANCH_NAME")
      end

      def job_name
        idx = @args.index("--test-job")
        return DEFAULT_JOB unless idx

        name = @args[idx + 1]
        raise Error, "--test-job requires a value" if name.nil? || name.start_with?("-")

        name
      end

      def client
        @client ||= GitlabClient.new(
          api_url: require_env("CI_API_V4_URL"),
          project_id: require_env("CI_PROJECT_ID"),
          token: require_env("CI_JOB_TOKEN"),
          token_header: "JOB-TOKEN"
        )
      end

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
