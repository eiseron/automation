# frozen_string_literal: true

require "test_helper"

module EiseronAutomation
  class PreviewDispatchTest < Minitest::Test
    def fake_handlers
      called = []
      handlers = ACTIONS.to_h { |name| [name, -> { called << name }] }
      [handlers, called]
    end

    ACTIONS = %w[deploy stop sweep].freeze

    ACTIONS.each do |action|
      define_method("test_#{action}_routes_to_handler") do
        handlers, called = fake_handlers
        PreviewDispatch.new(env: { "PREVIEW_ACTION" => action }, io: StringIO.new, handlers: handlers).run
        assert_equal [action], called
      end
    end

    def test_rejects_unknown_action
      handlers, = fake_handlers
      err = assert_raises(Error) do
        PreviewDispatch.new(env: { "PREVIEW_ACTION" => "bomb" }, io: StringIO.new, handlers: handlers).run
      end
      assert_match(/PREVIEW_ACTION='bomb'/, err.message)
    end

    def test_rejects_missing_action
      handlers, = fake_handlers
      err = assert_raises(Error) do
        PreviewDispatch.new(env: {}, io: StringIO.new, handlers: handlers).run
      end
      assert_match(/PREVIEW_ACTION/, err.message)
    end
  end
end
