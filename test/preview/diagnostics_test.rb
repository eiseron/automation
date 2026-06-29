# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  module Preview
    class DiagnosticsTest < Minitest::Test
      class FakeSsh
        attr_reader :commands

        def initialize(raise_on: nil)
          @commands = []
          @raise_on = raise_on
        end

        def run(cmd)
          @commands << cmd
          raise Error, "ssh blew up" if @raise_on && cmd.include?(@raise_on)
        end
      end

      def build(ssh, io: StringIO.new, project: "main", container: "main-afinados-1",
                host: "main-preview.afinados.io", health_path: "/up", port: 4000)
        Diagnostics.new(
          io: io, ssh: ssh, project: project, container: container,
          host: host, health_path: health_path, port: port
        )
      end

      def test_dump_probes_compose_labels_networks_phoenix_traefik
        ssh = FakeSsh.new
        build(ssh).dump
        joined = ssh.commands.join("\n")
        assert_includes joined, "docker compose -p main ps -a"
        assert_includes joined, "docker inspect main-afinados-1 --format '{{json .Config.Labels}}'"
        assert_includes joined, "docker inspect main-afinados-1 --format '{{json .NetworkSettings.Networks}}'"
        assert_includes joined, "docker exec main-afinados-1 wget -qO- --timeout=5 http://localhost:4000/up"
        assert_includes joined, "-H 'Host: main-preview.afinados.io' http://localhost/up"
        assert_includes joined, "docker logs traefik"
        assert_includes joined, "/api/http/routers"
      end

      def test_curl_probes_carry_connect_and_max_timeouts
        ssh = FakeSsh.new
        build(ssh).dump
        ssh.commands.select { |c| c.include?("curl") }.each do |cmd|
          assert_includes cmd, "--connect-timeout 3", "curl probe can hang: #{cmd}"
          assert_includes cmd, "--max-time 5", "curl probe can hang: #{cmd}"
        end
      end

      def test_routers_probe_is_filtered_to_the_host_not_a_global_dump
        ssh = FakeSsh.new
        build(ssh).dump
        routers = ssh.commands.find { |c| c.include?("/api/http/routers") }
        assert_includes routers, "grep -F main-preview.afinados.io"
      end

      def test_every_probe_is_suffixed_with_failure_tolerance
        ssh = FakeSsh.new
        build(ssh).dump
        ssh.commands.each { |cmd| assert_includes cmd, "|| true", "probe not failure-tolerant: #{cmd}" }
      end

      def test_a_probe_raising_does_not_abort_the_dump
        ssh = FakeSsh.new(raise_on: "compose")
        io = StringIO.new
        build(ssh, io: io).dump
        assert_includes io.string, "probe failed"
        assert_operator ssh.commands.length, :>, 1, "dump stopped at the first failing probe"
      end

      def test_rejects_health_path_with_shell_metacharacters
        err = assert_raises(Error) { build(FakeSsh.new, health_path: "/up; rm -rf /") }
        assert_match(/health_path=/, err.message)
      end

      def test_rejects_project_with_shell_metacharacters
        err = assert_raises(Error) { build(FakeSsh.new, project: "main$(touch pwned)") }
        assert_match(/project=/, err.message)
      end

      def test_rejects_host_with_backtick
        err = assert_raises(Error) { build(FakeSsh.new, host: "h`id`") }
        assert_match(/host=/, err.message)
      end
    end
  end
end
