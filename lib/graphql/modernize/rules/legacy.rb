# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class DefineDsl < Base
        rule id: "GQLM101", safety: :manual, summary: "Migrate the `.define` DSL to the class-based API",
             since: "1.10.0", removed_in: "2.0.0", docs: "docs/rules/GQLM101.md"
        node_pattern :call_node, "(call_node name: :define)"

        def on_match(node, _captures)
          receiver = constant_source(node.receiver)
          return unless receiver&.match?(/\AGraphQL::(?:Object|InputObject|Interface|Enum|Scalar|Union)Type\z/) ||
                        receiver == "GraphQL::Relay::Mutation"

          add_offense(node.message_loc, message: "Migrate the `.define` DSL to the class-based API manually")
        end
      end

      class ResolveFieldOption < Base
        RESERVED_METHOD_NAMES = %i[context initialize object].freeze
        UNSUPPORTED_NODES = [
          Prism::BlockNode, Prism::LambdaNode, Prism::DefNode, Prism::ClassNode, Prism::ModuleNode,
          Prism::SelfNode, Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode,
          Prism::ClassVariableReadNode, Prism::ClassVariableWriteNode,
          Prism::GlobalVariableReadNode, Prism::GlobalVariableWriteNode,
          Prism::SuperNode, Prism::ForwardingSuperNode, Prism::YieldNode,
          Prism::NextNode, Prism::BreakNode, Prism::RedoNode, Prism::RetryNode
        ].freeze

        rule id: "GQLM102", safety: :unsafe, summary: "Move `resolve:` field options to resolver methods",
             removed_in: "2.0.1", docs: "docs/rules/GQLM102.md"
        node_pattern :call_node, "(call_node receiver: nil name: :field)"

        def on_match(node, _captures)
          return unless inside?(node, :object, :interface)

          arguments = keyword_arguments(node, :resolve)
          return if arguments.empty?

          argument = arguments.first
          if arguments.length > 1
            return add_offense(argument.location, safety: :manual,
                                                  message: "Resolve duplicate `resolve:` options manually")
          end

          method_name = field_method_name(node)
          lambda_node = argument.value
          unless convertible?(node, lambda_node, method_name)
            return add_offense(argument.location, safety: :manual,
                                                  message: "Move `resolve:` logic to a resolver method manually")
          end

          @generated_method_names ||= {}
          if @generated_method_names[method_name] || hierarchy.method_defined?(context_for(node).class_name,
                                                                               method_name)
            return add_offense(argument.location, safety: :manual,
                                                  message: "`#{method_name}` already exists; migrate manually")
          end
          @generated_method_names[method_name] = true

          body = resolver_body(lambda_node)
          method_source = "def #{method_name}(**)\n#{indent_body(body)}\nend"
          add_offense(argument.location, message: "Move `resolve:` to the `#{method_name}` method") do |rw|
            rw.remove_keyword_argument(node, :resolve)
            rw.insert_into_body(context_for(node).class_node, method_source, position: :before_private)
          end
        end

        private

        def field_method_name(node)
          field_name = node.arguments&.arguments&.first
          name = case field_name
                 when Prism::SymbolNode, Prism::StringNode then field_name.unescaped
                 end
          name if name&.match?(/\A[a-z_]\w*[!?]?\z/) && !RESERVED_METHOD_NAMES.include?(name.to_sym)
        end

        def convertible?(field, lambda_node, method_name)
          return false unless method_name && lambda_node.is_a?(Prism::LambdaNode) && lambda_node.body
          return false unless body_boundaries_are_whitespace?(lambda_node)
          return false if dynamic_keyword_arguments?(field)
          return false if %i[method resolver_method hash_key].any? do |name|
            rewriter.find_keyword_argument(field, name)
          end

          parameters = lambda_node.parameters&.parameters
          return false unless simple_parameters?(parameters)

          names = parameters.requireds.map(&:name)
          safe_body?(lambda_node.body, names)
        end

        def simple_parameters?(parameters)
          parameters && parameters.requireds.length == 3 && parameters.optionals.empty? && !parameters.rest &&
            parameters.posts.empty? && parameters.keywords.empty? && !parameters.keyword_rest && !parameters.block
        end

        def safe_body?(body, names)
          nodes = descendants(body)
          return false if nodes.any? { |child| UNSUPPORTED_NODES.any? { |type| child.is_a?(type) } }

          assignment_names = names.values_at(0, 2) + %i[object context]
          return false if nodes.any? do |child|
            child.respond_to?(:name) && assignment_names.include?(child.name) &&
            (child.is_a?(Prism::LocalVariableTargetNode) || child.class.name.end_with?("WriteNode"))
          end
          return false if nodes.grep(Prism::LocalVariableReadNode).any? { |read| read.depth.positive? }
          return false if nodes.grep(Prism::LocalVariableReadNode).any? { |read| read.name == names[1] }
          return false if nodes.grep(Prism::CallNode).any? { |call| call.receiver.nil? }

          true
        end

        def body_boundaries_are_whitespace?(lambda_node)
          source = rewriter.source_file.source
          prefix = source.byteslice(lambda_node.opening_loc.end_offset,
                                    lambda_node.body.location.start_offset - lambda_node.opening_loc.end_offset)
          suffix = source.byteslice(lambda_node.body.location.end_offset,
                                    lambda_node.closing_loc.start_offset - lambda_node.body.location.end_offset)
          prefix.strip.empty? && suffix.strip.empty?
        end

        def resolver_body(lambda_node)
          body = lambda_node.body.location.slice.dup
          parameters = lambda_node.parameters.parameters.requireds.map(&:name)
          replacements = descendants(lambda_node.body).grep(Prism::LocalVariableReadNode).filter_map do |read|
            replacement = "object" if read.name == parameters[0]
            replacement ||= "context" if read.name == parameters[2]
            next unless replacement

            [read.location.start_offset - lambda_node.body.location.start_offset,
             read.location.end_offset - lambda_node.body.location.start_offset, replacement]
          end
          replacements.sort_by(&:first).reverse_each { |from, to, replacement| body.bytesplice(from...to, replacement) }
          rewriter.dedent(body)
        end

        def indent_body(body)
          rewriter.indent(body).delete_suffix(rewriter.source_file.newline)
        end

        def descendants(node)
          node.compact_child_nodes.flat_map { |child| [child, *descendants(child)] }
        end
      end

      class FunctionSuperclass < Base
        rule id: "GQLM103", safety: :unsafe, summary: "Migrate GraphQL::Function to Resolver",
             removed_in: "2.0.0", docs: "docs/rules/GQLM103.md"
        node_pattern :class_node, "(class_node)"

        def on_match(node, _captures)
          return unless constant_source(node.superclass) == "GraphQL::Function"

          add_offense(node.superclass.location, message: "Migrate `GraphQL::Function` to Resolver") do |rw|
            replace_constant(rw, node.superclass, "GraphQL::Schema::Resolver")
          end
        end
      end

      class DeprecatedDefinitionCall < Base
        rule id: "GQLM104", safety: :manual, summary: "Remove legacy definition conversion calls",
             removed_in: "2.0.0", docs: "docs/rules/GQLM104.md"
        node_pattern :call_node, "(call_node)"

        def on_match(node, _captures)
          return unless %i[to_graphql graphql_definition].include?(node.name)

          context = context_for(node)
          return if context && ClassHierarchy::DIRECT_KINDS.key?(context.class_name)

          add_offense(node.message_loc, message: "`#{node.name}` was removed; review this call manually")
        end
      end

      class QueryArgumentsConstant < Base
        rule id: "GQLM108", safety: :manual, summary: "Migrate GraphQL::Query::Arguments references",
             removed_in: "2.0.0", docs: "docs/rules/GQLM108.md"
        node_pattern :constant_path_node, "(constant_path_node name: :Arguments)"

        def on_match(node, _captures)
          return unless constant_source(node) == "GraphQL::Query::Arguments"

          add_offense(node.location, message: "Migrate this use of `GraphQL::Query::Arguments` manually")
        end
      end

      class TypesShortcut < Base
        REPLACEMENTS = {
          "Boolean" => "GraphQL::Types::Boolean",
          "Float" => "Float",
          "ID" => "GraphQL::Types::ID",
          "Int" => "Integer",
          "String" => "String"
        }.freeze

        rule id: "GQLM105", safety: :safe, summary: "Replace `types.X` with class references",
             removed_in: "2.0.0", docs: "docs/rules/GQLM105.md"
        node_pattern :call_node, "(call_node receiver: (call_node receiver: nil name: :types))"

        def on_match(node, _captures)
          return unless inside?(node, :object, :input_object, :interface, :resolver, :mutation, :subscription)
          return if node.block || node.arguments&.arguments&.any?

          name = node.message_loc.slice
          replacement = REPLACEMENTS[name]
          return unless replacement

          if @context.call_receiver?(node)
            return add_offense(node.location, safety: :manual,
                                              message: "Migrate chained `types.#{name}` to the class API manually")
          end

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

          arguments = keyword_arguments(node, :property)
          return if arguments.empty?

          argument = arguments.first

          if arguments.length > 1 || keyword_arguments(node, :method).any? || dynamic_keyword_arguments?(node)
            return add_offense(argument.location, safety: :manual,
                                                  message: "Resolve duplicate `property:` and `method:` manually")
          end

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
            argument.is_a?(Prism::AssocNode) && argument.key.is_a?(Prism::SymbolNode) &&
              TARGETS.include?(argument.key.unescaped.to_sym)
          end
          return if arguments.empty?

          unless arguments.all? { |argument| safe_to_discard?(argument.value) } && !dynamic_keyword_arguments?(node)
            message = "Remove `field:` and `function:` manually; preserve side effects"
            return add_offense(arguments.first.location, safety: :manual, message: message)
          end

          add_offense(arguments.first.location, message: "Remove the deleted `field:` and `function:` options") do |rw|
            if arguments.length == keyword_hash.elements.length
              if node.arguments.arguments.one? && !node.opening_loc
                rw.remove(node.message_loc.end_offset...keyword_hash.location.end_offset)
              else
                rw.remove_list_element(node.arguments, keyword_hash)
              end
            else
              rw.remove_list_elements(keyword_hash, arguments)
            end
          end
        end
      end
    end
  end
end
