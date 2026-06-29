# frozen_string_literal: true

require "test_helper"
require "json"

module EiseronAutomation
  module Preview
    class SweepTest < Minitest::Test
      class FakeSsh
        attr_reader :captures

        def initialize(scripted: {})
          @captures = []
          @scripted = scripted
        end

        def capture(cmd)
          @captures << cmd
          @scripted.fetch(cmd, "")
        end
      end

      class FakeRegistry
        attr_accessor :states

        def initialize(states: {})
          @states = states
        end

        def mr_state(iid) = @states.fetch(iid, "error")
      end

      class FakeTeardown
        attr_reader :calls

        def initialize
          @calls = []
        end

        def run(project:, ref:)
          @calls << { project: project, ref: ref }
        end
      end

      def env = { "EISERON_PREVIEW_APP_NAME" => "afinados" }

      def run_sweep(projects_json:, labels: {}, ids: {}, states: {})
        ssh = FakeSsh.new(scripted: {
          "docker compose ls --filter name=mr- --format json" => projects_json
        }.merge(ids).merge(labels))
        registry = FakeRegistry.new(states: states)
        teardown = FakeTeardown.new
        Sweep.new(env: env, io: StringIO.new, ssh: ssh, registry: registry, teardown: teardown).run
        teardown
      end

      def test_no_projects_does_nothing
        td = run_sweep(projects_json: "[]")
        assert_empty td.calls
      end

      def test_tears_down_merged_closed_and_not_found
        names = %w[mr-a mr-b mr-c mr-d]
        td = run_sweep(
          projects_json: JSON.generate(names.map { |n| { "Name" => n } }),
          ids: {
            "docker compose -p mr-a ps -q afinados" => "cid-a",
            "docker compose -p mr-b ps -q afinados" => "cid-b",
            "docker compose -p mr-c ps -q afinados" => "cid-c",
            "docker compose -p mr-d ps -q afinados" => "cid-d"
          },
          labels: {
            'docker inspect cid-a --format \'{{ index .Config.Labels "afinados.preview.mr_iid" }}\'' => "1\n",
            'docker inspect cid-b --format \'{{ index .Config.Labels "afinados.preview.mr_iid" }}\'' => "2\n",
            'docker inspect cid-c --format \'{{ index .Config.Labels "afinados.preview.mr_iid" }}\'' => "3\n",
            'docker inspect cid-d --format \'{{ index .Config.Labels "afinados.preview.mr_iid" }}\'' => "4\n"
          },
          states: { "1" => "opened", "2" => "merged", "3" => "closed", "4" => "not_found" }
        )
        torn = td.calls.map { |c| c[:ref] }.sort
        assert_equal %w[b c d], torn
      end

      def test_skips_projects_without_mr_iid_label
        td = run_sweep(
          projects_json: JSON.generate([{ "Name" => "mr-orphan" }]),
          ids: { "docker compose -p mr-orphan ps -q afinados" => "cid-x" },
          labels: { 'docker inspect cid-x --format \'{{ index .Config.Labels "afinados.preview.mr_iid" }}\'' => "" }
        )
        assert_empty td.calls
      end

      def test_skips_projects_with_no_running_container
        td = run_sweep(
          projects_json: JSON.generate([{ "Name" => "mr-stopped" }]),
          ids: { "docker compose -p mr-stopped ps -q afinados" => "" }
        )
        assert_empty td.calls
      end

      def test_skips_unknown_states
        td = run_sweep(
          projects_json: JSON.generate([{ "Name" => "mr-weird" }]),
          ids: { "docker compose -p mr-weird ps -q afinados" => "cid-w" },
          labels: { 'docker inspect cid-w --format \'{{ index .Config.Labels "afinados.preview.mr_iid" }}\'' => "99" },
          states: { "99" => "error" }
        )
        assert_empty td.calls
      end

      def test_service_name_can_be_overridden
        ssh = FakeSsh.new(
          scripted: {
            "docker compose ls --filter name=mr- --format json" => JSON.generate([{ "Name" => "mr-foo" }]),
            "docker compose -p mr-foo ps -q holter" => ""
          }
        )
        Sweep.new(env: env.merge("EISERON_PREVIEW_SERVICE" => "holter"),
                  io: StringIO.new, ssh: ssh, registry: FakeRegistry.new,
                  teardown: FakeTeardown.new).run
        assert_includes ssh.captures, "docker compose -p mr-foo ps -q holter"
      end
    end
  end
end
