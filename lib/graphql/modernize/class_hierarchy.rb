# frozen_string_literal: true

module GraphQL
  module Modernize
    class ClassHierarchy
      Declaration = Data.define(:path, :start_offset, :end_offset, :name, :superclass, :module_node)
      Definition = Data.define(:class_name, :path, :line)
      Call = Data.define(:name, :first_argument)

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
        @superclasses = {}
        @interface_names = {}
        @visible_definitions = []
        @calls = Hash.new { |hash, name| hash[name] = [] }
        @methods = Hash.new { |hash, name| hash[name] = {} }
      end

      def build(source_files)
        source_files.each { |source_file| index(source_file) }
        self
      end

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

      def declaration_at(source_file, start_offset)
        declarations.fetch(source_file.path, {})[start_offset]
      end

      def calls_for(class_name)
        ancestors(class_name).flat_map { |name| @calls[name] }
      end

      def method_defined?(class_name, method_name)
        ancestors(class_name).any? { |name| @methods[name][method_name.to_sym] }
      end

      def visible_definitions
        @visible_definitions.select { |definition| resolve_kind(definition.class_name) }
      end

      def visibility_plugin?(class_name)
        calls_for(class_name).any? do |call|
          call.name == :use && %w[GraphQL::Schema::Visibility GraphQL::Schema::Warden].include?(call.first_argument)
        end
      end

      private

      def index(source_file)
        nodes = []
        includes = []
        calls = []
        methods = []
        dispatcher = Astel::Dispatcher.new
        dispatcher.on(:class_node) { |node| nodes << [node, false] }
        dispatcher.on(:module_node) { |node| nodes << [node, true] }
        dispatcher.on(:call_node) do |node|
          calls << node
          includes << node if node.receiver.nil? && node.name == :include &&
                              node.arguments&.arguments&.any? { |arg| constant_name(arg) == "GraphQL::Schema::Interface" }
        end
        dispatcher.on(:def_node) { |node| methods << node }
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
        index_metadata(source_file, entries, includes, calls, methods)
      end

      def index_metadata(source_file, entries, includes, calls, methods)
        entries.each do |entry|
          @superclasses[entry.name] = entry.superclass if entry.superclass
        end
        includes.each do |call|
          owner = owner_for(entries, call)
          @interface_names[owner.name] = true if owner&.module_node
        end
        calls.each do |call|
          owner = owner_for(entries, call)
          @calls[owner.name] << Call.new(name: call.name, first_argument: first_argument(call)) if owner
        end
        methods.each do |node|
          owner = owner_for(entries, node)
          next unless owner

          @methods[owner.name][node.name] = true unless node.receiver
          if node.name == :visible?
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

      def first_argument(call)
        argument = call.arguments&.arguments&.first
        argument&.location&.slice
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

      def normalize(name)
        name.to_s.delete_prefix("::")
      end
    end
  end
end
