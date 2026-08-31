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

          arguments = keyword_arguments(node, :required)
          return if arguments.empty?

          if arguments.length > 1
            return unless arguments.any? { |argument| argument.value.is_a?(Prism::TrueNode) }

            return add_offense(arguments.first.location, safety: :manual,
                                                         message: "Resolve duplicate `required:` options manually")
          end
          return unless arguments.first.value.is_a?(Prism::TrueNode)

          argument = arguments.first
          if dynamic_keyword_arguments?(node)
            return add_offense(argument.location, safety: :manual,
                                                  message: "Review `**` before removing `required: true` manually")
          end

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

          arguments = keyword_arguments(node, :null)
          return if arguments.empty?

          if arguments.length > 1
            return unless arguments.any? { |argument| argument.value.is_a?(Prism::TrueNode) }

            return add_offense(arguments.first.location, safety: :manual,
                                                         message: "Resolve duplicate `null:` options manually")
          end
          return unless arguments.first.value.is_a?(Prism::TrueNode)

          argument = arguments.first
          if dynamic_keyword_arguments?(node)
            return add_offense(argument.location, safety: :manual,
                                                  message: "Review `**` expansion and resolve `null: true` manually")
          end

          add_offense(argument.location, message: "Remove the default `null: true` option") do |rw|
            rw.remove_keyword_argument(node, :null)
          end
        end
      end
    end
  end
end
