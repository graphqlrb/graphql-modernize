# frozen_string_literal: true

module GraphQL
  module Modernize
    Context = Data.define(:class_stack, :superclass, :graphql_kind, :class_name, :class_node)

    class ContextBuilder
      def initialize(source_file, hierarchy)
        nodes = {}
        scopes = []
        @call_receivers = {}.compare_by_identity
        dispatcher = Astel::Dispatcher.new
        callback = ->(node) { nodes[node.location.start_offset] = node }
        dispatcher.on(:class_node, callback)
        dispatcher.on(:module_node, callback)
        dispatcher.on(:def_node) { |node| scopes << node }
        dispatcher.on(:lambda_node) { |node| scopes << node }
        dispatcher.on(:call_node) do |node|
          @call_receivers[node.receiver] = true if node.receiver
          scopes << node.block if node.block && (node.receiver || node.name != :field)
        end
        dispatcher.run(source_file.ast)
        @executable_scopes = scopes.map do |scope|
          [scope.location.start_offset, scope.location.end_offset]
        end.sort_by(&:first)

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

      def executable_scope_at?(byte_offset)
        index = @executable_scopes.bsearch_index { |start_offset, _end_offset| start_offset >= byte_offset }
        index = index ? index - 1 : @executable_scopes.length - 1
        index.downto(0).any? do |candidate|
          start_offset, end_offset = @executable_scopes[candidate]
          byte_offset > start_offset && byte_offset < end_offset
        end
      end

      def call_receiver?(node) = @call_receivers.key?(node)
    end
  end
end
