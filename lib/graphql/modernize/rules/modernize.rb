# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class RedundantRequiredTrue < Base
        rule id: "GQLM401", safety: :safe, summary: "Remove the default `required: true` option",
             since: "1.13.0", docs: "docs/rules/GQLM401.md", default_enabled: false
        node_pattern :call_node, "(call_node receiver: nil name: :argument)"

        def on_match(node, _captures)
          return unless inside?(node, :object, :input_object, :interface, :resolver, :mutation, :subscription)

          argument = rewriter.find_keyword_argument(node, :required)
          return unless argument&.value.is_a?(Prism::TrueNode)

          add_offense(argument.location, message: "Remove the default `required: true` option") do |rw|
            rw.remove_keyword_argument(node, :required)
          end
        end
      end

      class RedundantNullTrue < Base
        rule id: "GQLM402", safety: :safe, summary: "Remove the default `null: true` option",
             since: "1.13.0", docs: "docs/rules/GQLM402.md", default_enabled: false
        node_pattern :call_node, "(call_node receiver: nil name: :field)"

        def on_match(node, _captures)
          return unless inside?(node, :object, :interface)

          argument = rewriter.find_keyword_argument(node, :null)
          return unless argument&.value.is_a?(Prism::TrueNode)

          add_offense(argument.location, message: "Remove the default `null: true` option") do |rw|
            rw.remove_keyword_argument(node, :null)
          end
        end
      end
    end
  end
end
