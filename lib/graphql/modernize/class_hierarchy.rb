# frozen_string_literal: true

module GraphQL
  module Modernize
    class ClassHierarchy
      Declaration = Data.define(:path, :start_offset, :end_offset, :name, :superclass, :module_node)
      Definition = Data.define(:class_name, :path, :line)
      Call = Data.define(:name, :first_argument, :path, :start_offset)

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
          call.path == path && call.start_offset > start_offset && %i[query mutation subscription].include?(call.name)
        end
      end

      private

      def visible_definition?(item) = resolve_kind(item.class_name) && !DIRECT_KINDS.key?(item.class_name)

      def defined_in?(table, class_name, name) = ancestors(class_name).any? { |ancestor| table[ancestor][name.to_sym] }

      def index(source_file)
        nodes = []
        includes = []
        calls = []
        methods = []
        singleton_classes = []
        scopes = []
        dispatcher = Astel::Dispatcher.new
        dispatcher.on(:class_node) { |node| nodes << [node, false] }
        dispatcher.on(:module_node) { |node| nodes << [node, true] }
        dispatcher.on(:call_node) do |node|
          calls << node
          includes << node if node.receiver.nil? && node.name == :include &&
                              node.arguments&.arguments&.any? { |arg| constant_name(arg) == "GraphQL::Schema::Interface" }
        end
        dispatcher.on(:def_node) do |node|
          methods << node
          scopes << node
        end
        dispatcher.on(:block_node) { |node| scopes << node }
        dispatcher.on(:lambda_node) { |node| scopes << node }
        dispatcher.on(:singleton_class_node) do |node|
          singleton_classes << node if node.expression.is_a?(Prism::SelfNode)
        end
        dispatcher.run(source_file.ast)

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
          Declaration.new(path: source_file.path, start_offset: node.location.start_offset,
                          end_offset: node.location.end_offset, name: resolve_name.call(node),
                          superclass: superclass, module_node: module_node)
        end
        offset_map = entries.to_h { |entry| [entry.start_offset, entry] }
        @declarations[source_file.path] = offset_map
        index_metadata(source_file, entries, includes, calls, methods, singleton_classes, scopes)
      end

      def index_metadata(source_file, entries, includes, calls, methods, singleton_classes, scopes)
        entries.each do |entry|
          @declared_names[entry.name] = true
          @superclasses[entry.name] = entry.superclass if entry.superclass
        end
        includes.reject { |call| scopes.any? { |scope| nested_in?(scope, call) } }.each do |call|
          owner = owner_for(entries, call)
          @interface_names[owner.name] = true if owner&.module_node
        end
        calls.reject { |call| scopes.any? { |scope| nested_in?(scope, call) } }.each do |call|
          owner = owner_for(entries, call)
          if owner
            @calls[owner.name] << Call.new(name: call.name, first_argument: first_argument(call),
                                           path: source_file.path, start_offset: call.location.start_offset)
          end
        end
        methods.each do |node|
          next if scopes.any? { |scope| !scope.equal?(node) && nested_in?(scope, node) }

          owner = owner_for(entries, node)
          next unless owner

          inside_singleton = singleton_classes.any? { |scope| nested_in?(scope, node) }
          next if node.receiver && !node.receiver.is_a?(Prism::SelfNode)

          class_method = node.receiver.is_a?(Prism::SelfNode) || inside_singleton
          (class_method ? @class_methods : @methods)[owner.name][node.name] = true
          if class_method && node.name == :visible?
            @visible_definitions << Definition.new(class_name: owner.name, path: source_file.path,
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

      def first_argument(call)
        argument = call.arguments&.arguments&.first
        constant_name(argument) || argument&.location&.slice
      end

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
        return unless node
        return node.name.to_s if node.is_a?(Prism::ConstantReadNode)
        return node.location.slice.delete_prefix("::") if node.is_a?(Prism::ConstantPathNode)

        nil
      end

      def normalize(name) = name.to_s.delete_prefix("::")
    end
  end
end
