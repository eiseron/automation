# frozen_string_literal: true

module EiseronAutomation
  module Preview
    class Diagnostics
      DOCKER_NAME = /\A[a-z0-9][a-z0-9_.-]*\z/
      HOST = /\A[a-z0-9][a-z0-9.-]*\z/
      PATH = %r{\A/[A-Za-z0-9/_.~-]*\z}
      CURL_TIMEOUT = "--connect-timeout 3 --max-time 5"

      def initialize(io:, ssh:, project:, container:, host:, health_path:, port:)
        @io = io
        @ssh = ssh
        @project = safe("project", project, DOCKER_NAME)
        @container = safe("container", container, DOCKER_NAME)
        @host = safe("host", host, HOST)
        @health_path = safe("health_path", health_path, PATH)
        @port = Integer(port)
      end

      def dump
        @io.puts "[diagnose] === preview host state (healthcheck failed) ==="
        probes.each do |title, remote_cmd|
          @io.puts "[diagnose] --- #{title} ---"
          safe_run(remote_cmd)
        end
        @io.puts "[diagnose] === end preview host state ==="
      end

      private

      def probes
        [
          ["compose ps", "docker compose -p #{@project} ps -a"],
          ["container labels", "docker inspect #{@container} --format '{{json .Config.Labels}}'"],
          ["container networks", "docker inspect #{@container} --format '{{json .NetworkSettings.Networks}}'"],
          ["phoenix direct on :#{@port}#{@health_path}",
           "docker exec #{@container} wget -qO- --timeout=5 http://localhost:#{@port}#{@health_path}; echo \" rc=$?\""],
          ["traefik via Host on :80#{@health_path}", traefik_host_probe],
          ["traefik discovery log tail", "docker logs traefik 2>&1 | tail -40"],
          ["traefik routers for #{@host}", traefik_routers_probe]
        ]
      end

      def traefik_host_probe
        write_out = "code=%{http_code}\\n" # rubocop:disable Style/FormatStringToken
        "curl -sS #{CURL_TIMEOUT} -o /dev/null -w '#{write_out}' -H 'Host: #{@host}' http://localhost#{@health_path}"
      end

      def traefik_routers_probe
        "curl -sS #{CURL_TIMEOUT} http://localhost:8080/api/http/routers 2>&1 | grep -F #{@host} | head -c 4000; echo"
      end

      def safe(name, value, pattern)
        return value if value.to_s.match?(pattern)

        raise Error, "diagnostics #{name}='#{value}' has unexpected characters; refusing to build a shell probe"
      end

      def safe_run(remote_cmd)
        @ssh.run("#{remote_cmd} 2>&1 || true")
      rescue Error => e
        @io.puts "[diagnose] probe failed: #{e.message}"
      end
    end
  end
end
