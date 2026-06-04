# frozen_string_literal: true

module RuboCop
  module Cop
    module Eiseron
      class NoComments < Base
        MSG = "Avoid comments; rationale belongs in the merge request, not the source."

        ALLOWED = /\A#(!|\s*(rubocop:|frozen_string_literal:|encoding:|coding:|warn_indent:|shareable_constant_value:|typed:))/

        def on_new_investigation
          processed_source.comments.each do |comment|
            add_offense(comment) unless comment.text.match?(ALLOWED)
          end
        end
      end
    end
  end
end
