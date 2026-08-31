# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      module DeprecatedPluginRule
        private

        def remove_plugin(node, constant)
          return unless inside?(node, :schema)

          arguments = node.arguments&.arguments
          first_argument = arguments&.first
          return unless constant_source(first_argument) == constant

          if !arguments.one? || node.block || !standalone_line?(node)
            return add_offense(node.location, safety: :manual,
                                              message: "Remove `use #{constant}` manually and preserve side effects")
          end

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
             since: "2.2.7", docs: "docs/rules/GQLM304.md"
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

          receiver = constant_source(node.receiver)
          return unless receiver == "GraphQL::Relay::ConnectionType"

          label = node.name.to_s.delete_suffix("=")
          value = node.arguments&.arguments&.first
          unless @context.top_level_statement?(node) && standalone_line?(node) && value && safe_to_discard?(value)
            return add_offense(node.location, safety: :manual,
                                              message: "Remove `#{label}` manually without discarding side effects")
          end

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
        node_pattern :call_node, "(call_node receiver: nil name: :use)", handler: :on_visibility_call

        def on_match(node, _captures)
          context = context_for(node)
          return unless inside?(node, :schema)
          return if hierarchy.visible_definitions.empty? || !hierarchy.visibility_plugin_target?(context.class_name)

          return if hierarchy.visibility_plugin_ambiguous?(context.class_name)

          definition = hierarchy.visible_definitions.first
          message = "visible? (#{definition.path}:#{definition.line}) requires a Visibility plugin"
          migration_errors = config.rule_options(self.class.metadata.id).fetch("migration_errors", true)
          plugin = "use GraphQL::Schema::Visibility, migration_errors: #{migration_errors}"
          add_offense(node.location, message: message) { |rw| rw.insert_into_body(node, plugin, position: :end) }
        end

        def on_visibility_call(node, _captures)
          context = context_for(node)
          return unless inside?(node, :schema)

          plugin = constant_source(node.arguments&.arguments&.first)
          return unless %w[GraphQL::Schema::Visibility GraphQL::Schema::Warden].include?(plugin)
          if hierarchy.visibility_plugin_ambiguous?(context.class_name)
            return add_offense(node.location, safety: :manual,
                                              message: "Resolve conditional Visibility plugin configuration manually")
          end
          return unless plugin == "GraphQL::Schema::Visibility"
          return unless hierarchy.visibility_plugin_misplaced?(context.class_name, rewriter.source_file.path,
                                                               node.location.start_offset)

          message = "Move `use GraphQL::Schema::Visibility` after root type configuration"
          line_end = rewriter.source_file.line_end(node.location.end_offset - 1)
          trailing = rewriter.source_file.source.byteslice(node.location.end_offset,
                                                           line_end - node.location.end_offset).strip
          if node.block || !standalone_line?(node) || !trailing.empty?
            return add_offense(node.location, safety: :manual, message: message)
          end

          source = rewriter.dedent(node.location.slice)
          add_offense(node.location, message: message) do |rw|
            rw.remove_line(node)
            rw.insert_into_body(context.class_node, source, position: :end)
          end
        end
      end

      class TypeIndexKeys < Base
        rule id: "GQLM308", safety: :manual, summary: "Update for possible_types and references_to key changes",
             since: "2.3.5", docs: "docs/rules/GQLM308.md"
        node_pattern :call_node, "(call_node)"

        def on_match(node, _captures)
          receiver = node.receiver&.location&.slice
          return unless %i[possible_types references_to].include?(node.name)
          return unless (receiver == "self" && inside?(node, :schema)) || hierarchy.resolve_kind(receiver) == :schema

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
          return unless inside?(node, :schema)

          configured = hierarchy.calls_for(context.class_name).any? do |call|
            call.direct && call.name == :allow_legacy_invalid_empty_selections_on_union
          end
          configured ||= %i[legacy_invalid_empty_selections_on_union
                            legacy_invalid_empty_selections_on_union_with_type].any? do |name|
            hierarchy.class_method_defined?(context.class_name, name)
          end
          return if configured

          add_offense(node.location, message: "Choose a policy for `allow_legacy_invalid_empty_selections_on_union`")
        end
      end
    end
  end
end
