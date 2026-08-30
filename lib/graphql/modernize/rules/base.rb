# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      Metadata = Data.define(:id, :safety, :summary, :since, :removed_in, :docs, :default_enabled)
      Pattern = Data.define(:node_type, :compiled, :handler)

      class Base
        class << self
          attr_reader :metadata, :patterns

          def rule(id:, safety:, summary:, since: nil, removed_in: nil, docs: nil, default_enabled: true)
            raise ArgumentError, "invalid rule id: #{id}" unless id.match?(/\AGQLM\d{3}\z/)
            raise ArgumentError, "invalid safety: #{safety}" unless %i[safe unsafe manual].include?(safety)

            @metadata = Metadata.new(id: id, safety: safety, summary: summary, since: since,
                                     removed_in: removed_in, docs: docs, default_enabled: default_enabled)
            RuleRegistry.register(self)
          end

          def node_pattern(node_type, pattern_source, handler: :on_match)
            @patterns ||= []
            @patterns << Pattern.new(node_type: node_type.to_sym,
                                     compiled: Astel::NodePattern.compile(pattern_source), handler: handler)
          end

          def node_types
            (@patterns || []).map(&:node_type).uniq
          end
        end

        attr_reader :offenses

        def initialize(context:, rewriter:, config:, suppression: nil, hierarchy: nil, edit_rules: {})
          @context = context
          @rewriter = rewriter
          @config = config
          @suppression = suppression
          @hierarchy = hierarchy
          @edit_rules = edit_rules
          @offenses = []
        end

        def visit(node)
          self.class.patterns.each do |pattern|
            next unless pattern.node_type == Astel::NodeType.from_class_name(node.class.name.split("::").last)

            captures = pattern.compiled.match(node)
            send(pattern.handler, node, captures) if captures
          end
        end

        private

        attr_reader :rewriter, :config, :hierarchy

        def add_offense(location, message:, safety: self.class.metadata.safety, &correction)
          return if @suppression&.suppressed?(self.class.metadata.id, location)

          offense = Offense.new(rule_id: self.class.metadata.id, location: location, message: message,
                                safety: safety, path: rewriter.source_file.path,
                                correctable: !correction.nil?)
          @offenses << offense
          return offense unless correction && correction_enabled?(safety)

          edit_count = rewriter.edits.length
          offense.corrected = rewriter.transaction(raise_on_conflict: true) { |rw| correction.call(rw) }
          rewriter.edits.drop(edit_count).each { |edit| @edit_rules[edit] = self.class.metadata.id }
          offense
        rescue Astel::Rewriter::ConflictError => e
          offense.conflicting_rule_id = @edit_rules.fetch(e.conflicting_edit, self.class.metadata.id)
          offense
        end

        def correction_enabled?(safety)
          safety == :safe || (safety == :unsafe && config.apply_unsafe)
        end

        def context_for(node)
          @context.context_at(node.location.start_offset)
        end

        def graphql_kind(node)
          context_for(node)&.graphql_kind
        end

        def inside?(node, *kinds)
          context = context_for(node)
          kinds.include?(context&.graphql_kind) && !ClassHierarchy::DIRECT_KINDS.key?(context.class_name)
        end

        def standalone_line?(node)
          source = rewriter.source_file
          line_start = source.line_start(node.location.start_offset)
          line_end = source.line_end([node.location.end_offset - 1, node.location.start_offset].max)
          before = source.source.byteslice(line_start, node.location.start_offset - line_start)
          after = source.source.byteslice(node.location.end_offset, line_end - node.location.end_offset).lstrip
          before.strip.empty? && (after.empty? || after.start_with?("#"))
        end

        def safe_to_discard?(node)
          node.static_literal? || node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
        end

        def constant_source(node)
          source = node&.location&.slice
          source&.delete_prefix("::")
        end

        def replace_constant(rewriter, node, replacement)
          prefix = node.location.slice.start_with?("::") ? "::" : ""
          rewriter.replace(node.location, "#{prefix}#{replacement}")
        end
      end
    end
  end
end
