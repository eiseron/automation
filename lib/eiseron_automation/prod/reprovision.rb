# frozen_string_literal: true

module EiseronAutomation
  module Prod
    class Reprovision
      HELP = <<~TEXT
        prod reprovision: git-driven, zero-downtime rolling node reprovision.

        For each PROD_NODE_TARGETS "node:tf_resource" pair, one at a time:
        move the CNPG primary off the node (switchover if needed), cordon and
        drain, terraform apply -replace=<tf_resource> in TF_WORKDIR, wait for
        the node Ready and the CNPG replica streaming, then uncordon. Never
        touches two nodes at once, so a quorum always stays up.

        Rollback is git revert: revert the provisioning commit and let CI
        reapply the previous declarative state; no imperative rollback here.

        Env: PROD_NODE_TARGETS (required), TF_WORKDIR (required),
        PG_CLUSTER (default platform-db), PG_NAMESPACE (default platform),
        PROD_NODE_TIMEOUT (default 600s).
      TEXT

      def initialize(env: ENV, io: $stdout, runner: Runner.new)
        @env = env
        @io = io
        @runner = runner
      end

      def run
        targets.each { |node, resource| reprovision(node, resource) }
        @io.puts "Reprovision complete: #{targets.map(&:first).join(', ')} rolled one at a time."
      end

      private

      def reprovision(node, resource)
        @io.puts "Reprovisioning #{node} (#{resource})"
        keep_primary_off(node)
        kubectl("cordon", node)
        kubectl("drain", node, "--ignore-daemonsets", "--delete-emptydir-data")
        terraform_replace(resource)
        wait_node_ready(node)
        wait_replica_streaming
        kubectl("uncordon", node)
      end

      def keep_primary_off(node)
        return unless primary_pod_node == node

        other = other_instance(node)
        raise Error, "cannot switch primary off #{node}: no other CNPG instance available" unless other

        @io.puts "Primary is on #{node}; promoting #{other} before draining"
        kubectl("cnpg", "promote", pg_cluster, other)
        return unless primary_pod_node == node

        raise Error, "primary is still on #{node} after promote; refusing to drain the primary"
      end

      def terraform_replace(resource)
        @runner.run(@env.to_h, "terraform", "-chdir=#{tf_workdir}", "apply",
                    "-auto-approve", "-replace=#{resource}")
      end

      def wait_node_ready(node)
        kubectl("wait", "--for=condition=Ready", "node/#{node}", "--timeout=#{node_timeout}")
      end

      def wait_replica_streaming
        kubectl("wait", "--for=condition=Ready",
                "-l", "cnpg.io/cluster=#{pg_cluster},cnpg.io/instanceRole=replica",
                "-n", pg_namespace, "pod", "--timeout=#{node_timeout}")
      end

      def primary_pod_node
        @runner.capture(
          "kubectl", "get", "pods", "-n", pg_namespace,
          "-l", "cnpg.io/cluster=#{pg_cluster},cnpg.io/instanceRole=primary",
          "-o", "jsonpath={.items[0].spec.nodeName}"
        ).strip
      end

      def other_instance(node)
        pairs = @runner.capture(
          "kubectl", "get", "pods", "-n", pg_namespace,
          "-l", "cnpg.io/cluster=#{pg_cluster}",
          "-o", "jsonpath={range .items[*]}{.metadata.name} {.spec.nodeName}{\"\\n\"}{end}"
        )
        instances_off(pairs, node).first
      end

      def instances_off(pairs, node)
        pairs.each_line.filter_map do |line|
          name, on = line.split
          name if name && on && on != node
        end
      end

      def kubectl(*)
        @runner.run(@env.to_h, "kubectl", *)
      end

      def targets
        @targets ||= parse_targets(require_env("PROD_NODE_TARGETS"))
      end

      def parse_targets(raw)
        raw.split.map { |pair| parse_pair(pair) }
      end

      def parse_pair(pair)
        node, resource = pair.split(":", 2)
        return [node, resource] unless node.to_s.empty? || resource.to_s.empty?

        raise Error, "PROD_NODE_TARGETS entry '#{pair}' must be node:tf_resource"
      end

      def tf_workdir = require_env("TF_WORKDIR")
      def pg_cluster = @env.fetch("PG_CLUSTER", "platform-db")
      def pg_namespace = @env.fetch("PG_NAMESPACE", "platform")
      def node_timeout = @env.fetch("PROD_NODE_TIMEOUT", "600s")

      def require_env(name)
        value = @env[name].to_s
        raise Error, "#{name} is empty" if value.empty?

        value
      end
    end
  end
end
