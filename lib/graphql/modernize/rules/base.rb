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

        def initialize(context:, rewriter:, config:, suppression: nil)
          @context = context
          @rewriter = rewriter
          @config = config
          @suppression = suppression
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

        attr_reader :rewriter, :config

        def add_offense(location, message:, &correction)
          return if @suppression&.suppressed?(self.class.metadata.id, location)

          offense = Offense.new(rule_id: self.class.metadata.id, location: location, message: message,
                                safety: self.class.metadata.safety, path: rewriter.source_file.path,
                                correctable: !correction.nil?)
          @offenses << offense
          return offense unless correction && correction_enabled?

          offense.corrected = rewriter.transaction { |rw| correction.call(rw) }
          offense
        end

        def correction_enabled?
          safety = self.class.metadata.safety
          safety == :safe || (safety == :unsafe && config.apply_unsafe)
        end

        def context_for(node)
          @context.context_at(node.location.start_offset)
        end

        def graphql_kind(node)
          context_for(node)&.graphql_kind
        end

        def inside?(node, *kinds)
          kinds.include?(graphql_kind(node))
        end
      end
    end
  end
end
