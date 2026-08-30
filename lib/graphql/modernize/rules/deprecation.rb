# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      module DeprecatedPluginRule
        private

        def remove_plugin(node, constant)
          return unless inside?(node, :schema)
          return unless node.arguments&.arguments&.one? && node.arguments.arguments.first.location.slice == constant

          add_offense(node.location, message: "Remove `use #{constant}` because it is now the default") do |rw|
            rw.remove_line(node)
          end
        end
      end

      class InterpreterPlugin < Base
        include DeprecatedPluginRule

        rule id: "GQLM301", safety: :safe, summary: "Remove the now-default Interpreter plugin",
             since: "1.12.0", docs: "docs/rules/GQLM301.md"
        node_pattern :call_node, "(call_node receiver: nil name: :use)"

        def on_match(node, _captures)
          remove_plugin(node, "GraphQL::Execution::Interpreter")
        end
      end

      class AnalysisAstPlugin < Base
        include DeprecatedPluginRule

        rule id: "GQLM302", safety: :safe, summary: "Remove the now-default Analysis::AST plugin",
             since: "1.12.0", docs: "docs/rules/GQLM302.md"
        node_pattern :call_node, "(call_node receiver: nil name: :use)"

        def on_match(node, _captures)
          remove_plugin(node, "GraphQL::Analysis::AST")
        end
      end

      class ConnectionsPlugin < Base
        include DeprecatedPluginRule

        rule id: "GQLM303", safety: :safe, summary: "Remove the now-default Connections plugin",
             since: "1.12.0", docs: "docs/rules/GQLM303.md"
        node_pattern :call_node, "(call_node receiver: nil name: :use)"

        def on_match(node, _captures)
          remove_plugin(node, "GraphQL::Pagination::Connections")
        end
      end

      class ErrorBubbling < Base
        rule id: "GQLM304", safety: :manual, summary: "Review error_bubbling(true)",
             since: "2.3.0", docs: "docs/rules/GQLM304.md"
        node_pattern :call_node, "(call_node receiver: nil name: :error_bubbling)"

        def on_match(node, _captures)
          return unless inside?(node, :schema)
          return unless node.arguments&.arguments&.first.is_a?(Prism::TrueNode)

          add_offense(node.location, message: "`error_bubbling(true)` is deprecated without a replacement")
        end
      end

      module RemovedPaginationSetting
        private

        def remove_setting(node, name)
          return unless node.name == name

          receiver = node.receiver&.location&.slice
          return unless inside?(node, :schema) || receiver&.start_with?("GraphQL::")

          label = node.name.to_s.delete_suffix("=")
          add_offense(node.location, message: "Remove the obsolete `#{label}` setting") { |rw| rw.remove_line(node) }
        end
      end

      class BidirectionalPagination < Base
        include RemovedPaginationSetting

        rule id: "GQLM305", safety: :safe, summary: "Remove the legacy pagination setting",
             since: "1.13.10", docs: "docs/rules/GQLM305.md"
        node_pattern :call_node, "(call_node)"

        def on_match(node, _captures)
          remove_setting(node, :bidirectional_pagination=)
        end
      end

      class DefaultNodesField < Base
        include RemovedPaginationSetting

        rule id: "GQLM306", safety: :safe, summary: "Remove the legacy default_nodes_field setting",
             since: "1.13.10", docs: "docs/rules/GQLM306.md"
        node_pattern :call_node, "(call_node)"

        def on_match(node, _captures)
          remove_setting(node, :default_nodes_field=)
        end
      end

      class VisibilityPlugin < Base
        rule id: "GQLM307", safety: :unsafe, summary: "Add the Visibility plugin required by visible?",
             since: "2.4.0", docs: "docs/rules/GQLM307.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          context = context_for(node)
          return unless context&.graphql_kind == :schema
          return if hierarchy.visible_definitions.empty? || hierarchy.visibility_plugin?(context.class_name)

          definition = hierarchy.visible_definitions.first
          message = "visible? (#{definition.path}:#{definition.line}) requires a Visibility plugin"
          migration_errors = config.rule_options(self.class.metadata.id).fetch("migration_errors", true)
          plugin = "use GraphQL::Schema::Visibility, migration_errors: #{migration_errors}"
          add_offense(node.location, message: message) { |rw| rw.insert_into_body(node, plugin, position: :end) }
        end
      end

      class TypeIndexKeys < Base
        rule id: "GQLM308", safety: :manual, summary: "Update for possible_types and references_to key changes",
             since: "2.3.5", docs: "docs/rules/GQLM308.md"
        node_pattern :call_node, "(call_node)"

        def on_match(node, _captures)
          receiver = node.receiver&.location&.slice
          return unless %i[possible_types references_to].include?(node.name)
          return unless (receiver == "self" && inside?(node, :schema)) || receiver&.end_with?("Schema")

          add_offense(node.location, message: "Return keys changed from type-name strings to type classes")
        end
      end

      class RescueFrom < Base
        rule id: "GQLM309", safety: :manual, summary: "Review rescue_from placement and handler signatures",
             docs: "docs/rules/GQLM309.md"
        node_pattern :call_node, "(call_node receiver: nil name: :rescue_from)"

        def on_match(node, _captures)
          return unless inside?(node, :schema)

          add_offense(node.location, message: "Review `rescue_from` placement and its handler signature")
        end
      end

      class EmptyUnionSelections < Base
        rule id: "GQLM310", safety: :manual, summary: "Choose a migration policy for empty Union selections",
             since: "2.5.3", docs: "docs/rules/GQLM310.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          context = context_for(node)
          return unless context&.graphql_kind == :schema
          return if hierarchy.calls_for(context.class_name).any? do |call|
            call.name == :allow_legacy_invalid_empty_selections_on_union
          end

          add_offense(node.location, message: "Choose a policy for `allow_legacy_invalid_empty_selections_on_union`")
        end
      end
    end
  end
end
