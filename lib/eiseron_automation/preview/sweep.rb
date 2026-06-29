# frozen_string_literal: true

require "json"

module EiseronAutomation
  module Preview
    class Sweep
      MR_PROJECT = /\Amr-(.+)\z/

      def initialize(env: ENV, io: $stdout, runner: Runner.new, ssh: nil, registry: nil, teardown: nil)
        @env = env
        @io = io
        @runner = runner
        @ssh = ssh
        @registry = registry
        @teardown = teardown
      end

      def run
        names = list_mr_projects
        return @io.puts "[sweep] no mr-* projects running; nothing to reconcile" if names.empty?

        names.each { |project| reconcile(project) }
        @io.puts "[sweep] complete"
      end

      private

      def reconcile(project)
        ref = MR_PROJECT.match(project)&.captures&.first
        return @io.puts "[sweep] skip non-mr project #{project}" unless ref

        iid = container_label(project, "preview.mr_iid")
        return @io.puts "[sweep] project=#{project} ref=#{ref} has no mr_iid label; leaving alone" if iid.empty?

        decide(project, ref, iid, registry.mr_state(iid))
      end

      def decide(project, ref, iid, state)
        case state
        when "opened"
          @io.puts "[sweep] mr=#{iid} ref=#{ref} still open"
        when "merged", "closed", "not_found"
          @io.puts "[sweep] tearing down mr=#{iid} ref=#{ref} state=#{state}"
          teardown.run(project: project, ref: ref)
        else
          @io.puts "[sweep] mr=#{iid} ref=#{ref} unknown state=#{state}; leaving alone"
        end
      end

      def list_mr_projects
        raw = ssh.capture("docker compose ls --filter name=mr- --format json")
        return [] if raw.strip.empty? || raw.strip == "[]"

        JSON.parse(raw).map { |project| project["Name"].to_s }.reject(&:empty?)
      end

      def container_label(project, label)
        container_id = ssh.capture("docker compose -p #{project} ps -q #{service}").strip
        return "" if container_id.empty?

        ssh.capture("docker inspect #{container_id} --format '{{ index .Config.Labels \"#{app}.#{label}\" }}'").strip
      rescue Error
        ""
      end

      def teardown
        @teardown ||= Teardown.new(env: @env, io: @io, ssh: ssh, registry: registry)
      end

      def ssh
        @ssh ||= SshSession.new(env: @env, runner: @runner)
      end

      def registry
        @registry ||= Registry.new(env: @env, io: @io)
      end

      def app
        @env["EISERON_PREVIEW_APP_NAME"].to_s.tap do |v|
          raise Error, "EISERON_PREVIEW_APP_NAME is empty" if v.empty?
        end
      end

      def service
        @env.fetch("EISERON_PREVIEW_SERVICE", app)
      end
    end
  end
end
