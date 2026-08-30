# frozen_string_literal: true

module GraphQL
  module Modernize
    Context = Data.define(:class_stack, :superclass, :graphql_kind, :class_name, :class_node)

    class ContextBuilder
      def initialize(source_file, hierarchy)
        nodes = {}
        dispatcher = Astel::Dispatcher.new
        callback = ->(node) { nodes[node.location.start_offset] = node }
        dispatcher.on(:class_node, callback)
        dispatcher.on(:module_node, callback)
        dispatcher.run(source_file.ast)

        @ranges = hierarchy.declarations.fetch(source_file.path, {}).values.map do |declaration|
          context = Context.new(
            class_stack: declaration.name.split("::"),
            superclass: declaration.superclass,
            graphql_kind: hierarchy.resolve_kind(declaration.name),
            class_name: declaration.name,
            class_node: nodes[declaration.start_offset]
          )
          [declaration.start_offset, declaration.end_offset, context]
        end.sort_by(&:first)
      end

      def context_at(byte_offset)
        index = @ranges.bsearch_index { |start_offset, _end_offset, _context| start_offset > byte_offset }
        index = index ? index - 1 : @ranges.length - 1
        index.downto(0) do |candidate|
          start_offset, end_offset, context = @ranges[candidate]
          return context if byte_offset >= start_offset && byte_offset < end_offset
        end
        nil
      end
    end
  end
end
