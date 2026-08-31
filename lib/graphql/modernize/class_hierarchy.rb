# frozen_string_literal: true

module GraphQL
  module Modernize
    ClassDeclaration = Data.define(:path, :start_offset, :end_offset, :name, :superclass, :module_node)
    VisibleDefinition = Data.define(:class_name, :path, :line)
    SchemaCall = Data.define(:name, :first_argument, :path, :start_offset, :direct)
    HierarchyNodes = Data.define(:declarations, :calls, :method_nodes, :singleton_classes, :scopes)

    module HierarchyScanner
      module_function

      def call(ast)
        declarations = []
        calls = []
        methods = []
        singleton_classes = []
        scopes = []
        dispatcher = Astel::Dispatcher.new
        dispatcher.on(:class_node) { |node| declarations << [node, false] }
        dispatcher.on(:module_node) { |node| declarations << [node, true] }
        dispatcher.on(:call_node) { |node| calls << node if node.receiver.nil? }
        dispatcher.on(:def_node) do |node|
          methods << node
          scopes << node
        end
        dispatcher.on(:alias_method_node) { |node| methods << node }
        dispatcher.on(:block_node) { |node| scopes << node }
        dispatcher.on(:lambda_node) { |node| scopes << node }
        dispatcher.on(:singleton_class_node) do |node|
          singleton_classes << node if node.expression.is_a?(Prism::SelfNode)
        end
        dispatcher.run(ast)
        HierarchyNodes.new(declarations: declarations, calls: calls, method_nodes: methods,
                           singleton_classes: singleton_classes, scopes: scopes)
      end
    end

    module MethodDeclarations
      module_function

      def body_statements(nodes)
        {}.compare_by_identity.tap do |result|
          add = lambda do |statements|
            statements&.body&.each do |statement|
              result[statement] = true
              plain_begin = statement.is_a?(Prism::BeginNode) && !statement.rescue_clause &&
                            !statement.else_clause && !statement.ensure_clause
              add.call(statement.statements) if plain_begin
            end
          end
          nodes.each { |node| add.call(node.body) }
        end
      end

      def select(methods, calls, body_statements)
        wrapped = calls.select do |call|
          body_statements.key?(call) && %i[private protected public].include?(call.name)
        end.flat_map { |call| call.arguments&.arguments.to_a }.grep(Prism::DefNode)
        methods.select { |method| body_statements.key?(method) || wrapped.include?(method) }
      end

      def calls(calls, body_statements)
        direct = calls.select { |call| body_statements.key?(call) }
        wrapped = direct.select { |call| %i[private protected public].include?(call.name) }
                        .flat_map { |call| call.arguments&.arguments.to_a }.grep(Prism::CallNode)
        direct.concat(wrapped).to_h { |call| [call, true] }.compare_by_identity
      end

      def names(call)
        names = call.arguments&.arguments.to_a.filter_map do |argument|
          argument.unescaped.to_sym if argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
        end
        return names if %i[attr attr_reader attr_accessor].include?(call.name)
        return names.first(1) if %i[alias_method define_method define_singleton_method].include?(call.name)

        []
      end

      def class_method?(call, singleton_classes)
        call.name == :define_singleton_method || singleton_classes.any? do |scope|
          call.location.start_offset > scope.location.start_offset &&
            call.location.end_offset < scope.location.end_offset
        end
      end
    end

    class ClassHierarchy
      DIRECT_KINDS = {
        "GraphQL::Schema::Object" => :object,
        "GraphQL::Schema::InputObject" => :input_object,
        "GraphQL::Schema::Enum" => :enum,
        "GraphQL::Schema::Union" => :union,
        "GraphQL::Schema::Resolver" => :resolver,
        "GraphQL::Schema::Mutation" => :mutation,
        "GraphQL::Schema::RelayClassicMutation" => :mutation,
        "GraphQL::Schema::Subscription" => :subscription,
        "GraphQL::Schema" => :schema
      }.freeze
      SUFFIX_KINDS = {
        "BaseObject" => :object,
        "BaseInputObject" => :input_object,
        "BaseEnum" => :enum,
        "BaseUnion" => :union,
        "BaseResolver" => :resolver,
        "BaseMutation" => :mutation
      }.freeze

      attr_reader :declarations

      def initialize(base_classes: {})
        @configured_kinds = base_classes.each_with_object({}) do |(kind, names), result|
          Array(names).each { |name| result[normalize(name)] = kind.to_sym }
        end
        @declarations = {}
        @declared_names = {}
        @superclasses = {}
        @interface_names = {}
        @visible_definitions = []
        @calls = Hash.new { |hash, name| hash[name] = [] }
        @methods = Hash.new { |hash, name| hash[name] = {} }
        @class_methods = Hash.new { |hash, name| hash[name] = {} }
      end

      def build(source_files) = tap { source_files.each { |source_file| index(source_file) } }

      def resolve_kind(class_name)
        name = normalize(class_name)
        seen = {}
        until name.empty? || seen[name]
          seen[name] = true
          kind = direct_kind(name)
          return kind if kind

          name = resolve_superclass(name)
        end
        nil
      end

      def calls_for(class_name) = ancestors(class_name).flat_map { |name| @calls[name] }

      def method_defined?(class_name, method_name) = defined_in?(@methods, class_name, method_name)

      def class_method_defined?(class_name, method_name) = defined_in?(@class_methods, class_name, method_name)

      def visible_definitions = @visible_definitions.select { |definition| visible_definition?(definition) }

      def visibility_plugin?(class_name)
        calls_for(class_name).any? do |call|
          call.direct && call.name == :use &&
            %w[GraphQL::Schema::Visibility GraphQL::Schema::Warden].include?(call.first_argument)
        end
      end

      def visibility_plugin_ambiguous?(class_name)
        !visibility_plugin?(class_name) && calls_for(class_name).any? do |call|
          call.name == :use && %w[GraphQL::Schema::Visibility GraphQL::Schema::Warden].include?(call.first_argument)
        end
      end

      def visibility_plugin_target?(class_name)
        return false if visibility_plugin?(class_name)

        ancestors(class_name).drop(1).none? do |name|
          @declared_names[name] && resolve_kind(name) == :schema && !visibility_plugin?(name)
        end
      end

      def visibility_plugin_misplaced?(class_name, path, start_offset)
        @calls[normalize(class_name)].any? do |call|
          call.direct && call.path == path && call.start_offset > start_offset &&
            %i[query mutation subscription].include?(call.name)
        end
      end

      private

      def visible_definition?(item) = resolve_kind(item.class_name) && !DIRECT_KINDS.key?(item.class_name)

      def defined_in?(table, class_name, name) = ancestors(class_name).any? { |ancestor| table[ancestor][name.to_sym] }

      def index(source_file)
        scan = HierarchyScanner.call(source_file.ast)
        nodes = scan.declarations
        calls = scan.calls
        methods = scan.method_nodes
        singleton_classes = scan.singleton_classes
        includes = calls.select do |node|
          node.name == :include &&
            node.arguments&.arguments&.any? { |arg| constant_name(arg) == "GraphQL::Schema::Interface" }
        end

        body_statements = MethodDeclarations.body_statements(nodes.map(&:first) + singleton_classes)
        includes.select! { |call| body_statements.key?(call) }
        calls.reject! { |call| scan.scopes.any? { |scope| nested_in?(scope, call) } }
        methods = MethodDeclarations.select(methods, calls, body_statements)
        method_calls = MethodDeclarations.calls(calls, body_statements)

        name_cache = {}.compare_by_identity
        resolve_name = lambda do |node|
          name_cache[node] ||= begin
            raw_name = constant_name(node.constant_path)
            parent = nodes.filter_map do |candidate, _candidate_module|
              next if candidate.equal?(node)
              next unless candidate.location.start_offset < node.location.start_offset &&
                          candidate.location.end_offset >= node.location.end_offset

              candidate
            end.min_by { |candidate| candidate.location.end_offset - candidate.location.start_offset }
            qualify(raw_name, parent && resolve_name.call(parent))
          end
        end

        entries = nodes.sort_by { |node, _module_node| node.location.start_offset }.map do |node, module_node|
          superclass = node.respond_to?(:superclass) ? constant_name(node.superclass) : nil
          ClassDeclaration.new(path: source_file.path, start_offset: node.location.start_offset,
                               end_offset: node.location.end_offset, name: resolve_name.call(node),
                               superclass: superclass, module_node: module_node)
        end
        offset_map = entries.to_h { |entry| [entry.start_offset, entry] }
        @declarations[source_file.path] = offset_map
        index_metadata(source_file, entries, includes, calls, methods, singleton_classes, body_statements, method_calls)
      end

      def index_metadata(source_file, entries, includes, calls, methods, singleton_classes, body_statements,
                         method_calls)
        entries.each do |entry|
          @declared_names[entry.name] = true
          @superclasses[entry.name] = entry.superclass if entry.superclass
        end
        includes.each do |call|
          owner = owner_for(entries, call)
          @interface_names[owner.name] = true if owner&.module_node
        end
        calls.each do |call|
          owner = owner_for(entries, call)
          next unless owner

          @calls[owner.name] << SchemaCall.new(name: call.name, first_argument: first_argument(call),
                                               path: source_file.path, start_offset: call.location.start_offset,
                                               direct: body_statements.key?(call))
          names = MethodDeclarations.names(call)
          if method_calls.key?(call) && !names.empty?
            table = MethodDeclarations.class_method?(call, singleton_classes) ? @class_methods : @methods
            names.each { |name| table[owner.name][name] = true }
          end
        end
        methods.each do |node|
          owner = owner_for(entries, node)
          next unless owner

          inside_singleton = singleton_classes.any? { |scope| nested_in?(scope, node) }
          if node.is_a?(Prism::AliasMethodNode)
            (inside_singleton ? @class_methods : @methods)[owner.name][node.new_name.unescaped.to_sym] = true
            next
          end

          next if node.receiver && !node.receiver.is_a?(Prism::SelfNode)

          class_method = node.receiver.is_a?(Prism::SelfNode) || inside_singleton
          (class_method ? @class_methods : @methods)[owner.name][node.name] = true
          if class_method && node.name == :visible?
            @visible_definitions << VisibleDefinition.new(class_name: owner.name, path: source_file.path,
                                                          line: node.location.start_line)
          end
        end
      end

      def resolve_superclass(name)
        superclass = @superclasses[name]
        return "" unless superclass
        return normalize(superclass) if superclass.include?("::")

        namespace = name.split("::")[0...-1]
        while namespace.any?
          candidate = (namespace + [superclass]).join("::")
          return candidate if @superclasses.key?(candidate) || direct_kind(candidate)

          namespace.pop
        end
        superclass
      end

      def owner_for(entries, node)
        entries.select do |entry|
          node.location.start_offset > entry.start_offset && node.location.end_offset < entry.end_offset
        end.min_by { |entry| entry.end_offset - entry.start_offset }
      end

      def nested_in?(scope, node)
        node.location.start_offset > scope.location.start_offset && node.location.end_offset < scope.location.end_offset
      end

      def first_argument(call) = (arg = call.arguments&.arguments&.first) && (constant_name(arg) || arg.location.slice)

      def direct_kind(name)
        DIRECT_KINDS[name] || @configured_kinds[name] || (@interface_names[name] && :interface) ||
          SUFFIX_KINDS.find { |suffix, _kind| name.end_with?(suffix) }&.last
      end

      def ancestors(class_name)
        name = normalize(class_name)
        result = []
        seen = {}
        until name.empty? || seen[name]
          result << name
          seen[name] = true
          name = resolve_superclass(name)
        end
        result
      end

      def qualify(name, parent_name)
        normalized = normalize(name)
        return normalized if normalized.include?("::") || !parent_name

        "#{parent_name}::#{normalized}"
      end

      def constant_name(node)
        return node.name.to_s if node.is_a?(Prism::ConstantReadNode)

        node.location.slice.delete_prefix("::") if node.is_a?(Prism::ConstantPathNode)
      end

      def normalize(name) = name.to_s.delete_prefix("::")
    end
  end
end
