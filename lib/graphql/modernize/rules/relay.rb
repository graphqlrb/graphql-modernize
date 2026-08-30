# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
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
