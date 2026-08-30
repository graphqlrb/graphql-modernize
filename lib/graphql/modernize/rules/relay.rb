# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class RelayMutationSuperclass < Base
        rule id: "GQLM201", safety: :unsafe, summary: "Migrate Relay::Mutation to RelayClassicMutation",
             removed_in: "2.0.0", docs: "docs/rules/GQLM201.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          return unless node.superclass&.location&.slice == "GraphQL::Relay::Mutation"

          add_offense(node.superclass.location, message: "Migrate to RelayClassicMutation") do |rw|
            rw.replace(node.superclass.location, "GraphQL::Schema::RelayClassicMutation")
          end
        end
      end

      class RelayConnectionType < Base
        rule id: "GQLM202", safety: :manual, summary: "Migrate ConnectionType.create_type to connection_type",
             removed_in: "2.0.0", docs: "docs/rules/GQLM202.md"
        node_pattern :call_node, "(call_node name: :create_type)"

        def on_match(node, _captures)
          return unless node.receiver&.location&.slice == "GraphQL::Relay::ConnectionType"

          add_offense(node.location, message: "Migrate to the generated type's `connection_type` manually")
        end
      end

      class RelayNodeField < Base
        rule id: "GQLM203", safety: :unsafe, summary: "Migrate Relay::Node.field to the Relay node interface",
             removed_in: "2.0.0", docs: "docs/rules/GQLM203.md"
        node_pattern :call_node, "(call_node name: :field)"

        def on_match(node, _captures)
          return unless node.receiver&.location&.slice == "GraphQL::Relay::Node"

          add_offense(node.location, message: "Migrate to `implements GraphQL::Types::Relay::Node`")
        end
      end

      class DirectBaseConnection < Base
        rule id: "GQLM204", safety: :unsafe, summary: "Inherit from the generated BaseConnection",
             docs: "docs/rules/GQLM204.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          return unless node.superclass&.location&.slice == "GraphQL::Types::Relay::BaseConnection"

          add_offense(node.superclass.location, message: "Inherit from the application's `Types::BaseConnection`")
        end
      end

      class LoadApplicationObjectFailedError < Base
        OLD_NAME = "GraphQL::Schema::Resolver::LoadApplicationObjectFailedError"
        NEW_NAME = "GraphQL::LoadApplicationObjectFailedError"

        rule id: "GQLM205", safety: :safe, summary: "Update the LoadApplicationObjectFailedError constant path",
             since: "1.9.4", docs: "docs/rules/GQLM205.md"
        node_pattern :constant_path_node, "(constant_path_node name: :LoadApplicationObjectFailedError)"

        def on_match(node, _captures)
          return unless node.location.slice == OLD_NAME

          add_offense(node.location, message: "Replace `#{OLD_NAME}` with `#{NEW_NAME}`") do |rw|
            rw.replace(node.location, NEW_NAME)
          end
        end
      end
    end
  end
end
