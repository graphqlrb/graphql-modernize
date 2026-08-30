# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class TypesShortcut < Base
        rule id: "GQLM105", safety: :safe, summary: "Replace `types.X` with class references",
             removed_in: "2.0.0", docs: "docs/rules/GQLM105.md"
        node_pattern :call_node, "(call_node receiver: (call_node receiver: nil name: :types))"

        def on_match(node, _captures)
          return unless inside?(node, :object, :input_object, :interface, :resolver, :mutation, :subscription)

          name = node.message_loc.slice
          return unless name.match?(/\A[A-Z]\w*[!?]?\z/)

          replacement = name == "Int" ? "Integer" : name
          add_offense(node.location, message: "Replace `types.#{name}` with `#{replacement}`") do |rw|
            rw.replace(node.location, replacement)
          end
        end
      end

      class PropertyOption < Base
        rule id: "GQLM106", safety: :safe, summary: "Replace `property:` with `method:`",
             removed_in: "2.0.0", docs: "docs/rules/GQLM106.md"
        node_pattern :call_node, "(call_node receiver: nil name: :field)"

        def on_match(node, _captures)
          return unless inside?(node, :object, :interface)

          argument = rewriter.find_keyword_argument(node, :property)
          return unless argument

          add_offense(argument.key.location, message: "Replace `property:` with `method:`") do |rw|
            rw.replace_keyword_key(argument, :method)
          end
        end
      end

      class RemovedFieldOptions < Base
        TARGETS = %i[field function].freeze

        rule id: "GQLM107", safety: :safe, summary: "Remove deleted field options",
             removed_in: "2.0.1", docs: "docs/rules/GQLM107.md"
        node_pattern :call_node, "(call_node receiver: nil name: :field)"

        def on_match(node, _captures)
          return unless inside?(node, :object, :interface)

          keyword_hash = node.arguments&.arguments&.find { |argument| argument.is_a?(Prism::KeywordHashNode) }
          return unless keyword_hash

          arguments = keyword_hash.elements.select do |argument|
            argument.is_a?(Prism::AssocNode) && TARGETS.include?(argument.key.unescaped.to_sym)
          end
          return if arguments.empty?

          add_offense(arguments.first.location, message: "Remove the deleted `field:` and `function:` options") do |rw|
            rw.remove_list_elements(keyword_hash, arguments)
          end
        end
      end
    end
  end
end
