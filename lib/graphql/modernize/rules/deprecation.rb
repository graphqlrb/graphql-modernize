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
    end
  end
end
