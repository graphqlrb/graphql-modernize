# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class ComplexityCostMode < Base
        rule id: "GQLM501", safety: :manual, summary: "Choose an explicit complexity cost mode",
             since: "2.5.3", docs: "docs/rules/GQLM501.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          context = context_for(node)
          return unless inside?(node, :schema)

          configured = hierarchy.calls_for(context.class_name).any? do |call|
            call.name == :complexity_cost_calculation_mode
          end
          configured ||= hierarchy.class_method_defined?(context.class_name, :complexity_cost_calculation_mode_for)
          return if configured

          add_offense(node.location, message: "Choose a migration policy for `complexity_cost_calculation_mode`")
        end
      end

      class DefaultMaxPageSize < Base
        rule id: "GQLM502", safety: :unsafe, summary: "Migrate default_max_page_size to the new page size settings",
             docs: "docs/rules/GQLM502.md"
        node_pattern :call_node, "(call_node receiver: nil name: :default_max_page_size)"

        def on_match(node, _captures)
          return unless inside?(node, :schema)

          add_offense(node.location, message: "Review the split into `default_page_size` and `max_page_size`")
        end
      end
    end
  end
end
