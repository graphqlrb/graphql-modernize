# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class DefineDsl < Base
        rule id: "GQLM101", safety: :manual, summary: "Migrate the `.define` DSL to the class-based API",
             since: "1.10.0", removed_in: "2.0.0", docs: "docs/rules/GQLM101.md"
        node_pattern :call_node, "(call_node name: :define)"

        def on_match(node, _captures)
          receiver = node.receiver&.location&.slice
          return unless receiver&.match?(/\AGraphQL::(?:Object|InputObject|Interface|Enum|Scalar|Union)Type\z/) ||
                        receiver == "GraphQL::Relay::Mutation"

          add_offense(node.message_loc, message: "Migrate the `.define` DSL to the class-based API manually")
        end
      end

      class ResolveFieldOption < Base
        rule id: "GQLM102", safety: :manual, summary: "Move `resolve:` field options to resolver methods",
             removed_in: "2.0.1", docs: "docs/rules/GQLM102.md"
        node_pattern :call_node, "(call_node receiver: nil name: :field)"

        def on_match(node, _captures)
          return unless inside?(node, :object, :interface)

          argument = rewriter.find_keyword_argument(node, :resolve)
          add_offense(argument.location, message: "Move `resolve:` logic to a resolver method manually") if argument
        end
      end

      class FunctionSuperclass < Base
        rule id: "GQLM103", safety: :unsafe, summary: "Migrate GraphQL::Function to Resolver",
             removed_in: "2.0.0", docs: "docs/rules/GQLM103.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          return unless node.superclass&.location&.slice == "GraphQL::Function"

          add_offense(node.superclass.location, message: "Migrate `GraphQL::Function` to Resolver") do |rw|
            rw.replace(node.superclass.location, "GraphQL::Schema::Resolver")
          end
        end
      end

      class DeprecatedDefinitionCall < Base
        rule id: "GQLM104", safety: :manual, summary: "Remove legacy definition conversion calls",
             removed_in: "2.0.0", docs: "docs/rules/GQLM104.md"
        node_pattern :call_node, "(call_node)"

        def on_match(node, _captures)
          return unless %i[to_graphql graphql_definition].include?(node.name)

          add_offense(node.message_loc, message: "`#{node.name}` was removed; review this call manually")
        end
      end

      class QueryArgumentsConstant < Base
        rule id: "GQLM108", safety: :manual, summary: "Migrate GraphQL::Query::Arguments references",
             removed_in: "2.0.0", docs: "docs/rules/GQLM108.md"
        node_pattern :constant_path_node, "(constant_path_node name: :Arguments)"

        def on_match(node, _captures)
          return unless node.location.slice == "GraphQL::Query::Arguments"

          add_offense(node.location, message: "Migrate this use of `GraphQL::Query::Arguments` manually")
        end
      end

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
