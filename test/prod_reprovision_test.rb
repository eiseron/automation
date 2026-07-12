# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class ProdReprovisionTest < Minitest::Test
    class FakeRunner
      attr_reader :runs, :captures

      def initialize(primary_node: "node-a", stall_promote: false,
                     instances: { "platform-db-1" => "node-a", "platform-db-2" => "node-b" })
        @runs = []
        @captures = []
        @primary_node = primary_node
        @stall_promote = stall_promote
        @instances = instances
      end

      def run(_env, *cmd)
        @runs << cmd
        @primary_node = other_node(cmd[4]) if cnpg_promote?(cmd) && !@stall_promote
      end

      def capture(*cmd)
        @captures << cmd
        return @primary_node if cmd.include?("jsonpath={.items[0].spec.nodeName}")

        @instances.map { |name, node| "#{name} #{node}" }.join("\n")
      end

      def kubectl_verbs
        @runs.select { |cmd| cmd.first == "kubectl" }.map { |cmd| cmd[1] }
      end

      private

      def other_node(instance)
        @instances.fetch(instance, @primary_node)
      end

      def cnpg_promote?(cmd)
        cmd.first == "kubectl" && cmd[1] == "cnpg" && cmd[2] == "promote"
      end
    end

    def env(over = {})
      {
        "PROD_NODE_TARGETS" => "node-a:module.k3s.server[0] node-b:module.k3s.server[1]",
        "TF_WORKDIR" => "infra/prod"
      }.merge(over)
    end

    def reprovision(vars, runner)
      Prod::Reprovision.new(env: vars, io: StringIO.new, runner: runner)
    end

    def test_drains_each_node_exactly_once_in_target_order
      runner = FakeRunner.new
      reprovision(env, runner).run
      drained = runner.runs.select { |cmd| cmd[1] == "drain" }.map { |cmd| cmd[2] }
      assert_equal %w[node-a node-b], drained
    end

    def test_never_cordons_a_second_node_before_uncordoning_the_first
      runner = FakeRunner.new
      reprovision(env, runner).run
      lifecycle = runner.kubectl_verbs.select { |verb| %w[cordon uncordon].include?(verb) }
      assert_equal %w[cordon uncordon cordon uncordon], lifecycle
    end

    def test_switches_primary_off_the_node_before_draining_it
      runner = FakeRunner.new(primary_node: "node-a")
      reprovision(env, runner).run
      promote = runner.runs.index { |cmd| cmd[1] == "cnpg" && cmd[2] == "promote" }
      drain = runner.runs.index { |cmd| cmd[1] == "drain" && cmd[2] == "node-a" }
      assert_operator promote, :<, drain
    end

    def test_promotes_the_instance_that_lives_on_the_other_node
      runner = FakeRunner.new(primary_node: "node-a")
      reprovision(env, runner).run
      promote = runner.runs.find { |cmd| cmd[1] == "cnpg" && cmd[2] == "promote" }
      assert_equal "platform-db-2", promote.last
    end

    def test_does_not_switch_over_when_primary_is_already_off_the_node
      runner = FakeRunner.new(primary_node: "node-b")
      reprovision(env("PROD_NODE_TARGETS" => "node-a:module.k3s.server[0]"), runner).run
      refute(runner.runs.any? { |cmd| cmd[1] == "cnpg" && cmd[2] == "promote" })
    end

    def test_refuses_when_primary_stays_on_node_after_promote
      runner = FakeRunner.new(primary_node: "node-a", stall_promote: true)
      error = assert_raises(Error) do
        reprovision(env("PROD_NODE_TARGETS" => "node-a:module.k3s.server[0]"), runner).run
      end
      assert_match(/primary is still on node-a after promote/, error.message)
    end

    def test_does_not_drain_the_node_when_the_primary_switchover_stalls
      runner = FakeRunner.new(primary_node: "node-a", stall_promote: true)
      assert_raises(Error) do
        reprovision(env("PROD_NODE_TARGETS" => "node-a:module.k3s.server[0]"), runner).run
      end
      refute(runner.runs.any? { |cmd| cmd[1] == "drain" })
    end

    def test_terraform_replaces_the_per_node_resource_in_the_workdir
      runner = FakeRunner.new
      reprovision(env, runner).run
      apply = runner.runs.find { |cmd| cmd.first == "terraform" }
      assert_includes apply, "-replace=module.k3s.server[0]"
      assert_includes apply, "-chdir=infra/prod"
    end

    def test_terraform_runs_after_drain_and_before_uncordon_for_that_node
      runner = FakeRunner.new
      reprovision(env("PROD_NODE_TARGETS" => "node-a:module.k3s.server[0]"), runner).run
      verbs = runner.runs.map { |cmd| cmd.first == "terraform" ? "terraform" : cmd[1] }
      relevant = verbs.select { |v| %w[drain terraform].include?(v) }
      assert_equal %w[drain terraform], relevant
    end

    def test_waits_for_the_node_ready_and_replica_streaming_before_uncordon
      runner = FakeRunner.new
      reprovision(env("PROD_NODE_TARGETS" => "node-a:module.k3s.server[0]"), runner).run
      after_wait = runner.kubectl_verbs.drop_while { |verb| verb != "wait" }
      assert_equal %w[wait wait uncordon], after_wait
    end

    def test_refuses_to_drain_when_no_other_instance_exists_to_take_the_primary
      runner = FakeRunner.new(primary_node: "node-a", instances: { "platform-db-1" => "node-a" })
      error = assert_raises(Error) do
        reprovision(env("PROD_NODE_TARGETS" => "node-a:module.k3s.server[0]"), runner).run
      end
      assert_match(/no other CNPG instance available/, error.message)
    end

    def test_rejects_a_target_missing_the_tf_resource
      runner = FakeRunner.new
      error = assert_raises(Error) do
        reprovision(env("PROD_NODE_TARGETS" => "node-a"), runner).run
      end
      assert_match(/must be node:tf_resource/, error.message)
    end

    def test_requires_the_node_targets
      runner = FakeRunner.new
      assert_raises(Error) { reprovision(env.except("PROD_NODE_TARGETS"), runner).run }
    end

    def test_requires_the_terraform_workdir
      runner = FakeRunner.new
      assert_raises(Error) { reprovision(env.except("TF_WORKDIR"), runner).run }
    end
  end
end
