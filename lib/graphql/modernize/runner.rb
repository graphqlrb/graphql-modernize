# frozen_string_literal: true

module GraphQL
  module Modernize
    class Runner
      def initialize(hierarchy:, config: Config.new)
        @hierarchy = hierarchy
        @config = config
      end

      def run(source_file, rules = RuleRegistry.all)
        context = ContextBuilder.new(source_file, @hierarchy)
        rewriter = Astel::Rewriter.new(source_file)
        dispatcher = Astel::Dispatcher.new
        suppression = SuppressionIndex.new(source_file, require_reason: @config.require_suppression_reason)
        instances = rules.select { |rule| @config.rule_enabled?(rule.metadata) }
                         .map do |rule|
          rule.new(context: context, rewriter: rewriter, config: @config, suppression: suppression,
                   hierarchy: @hierarchy)
        end

        instances.each do |rule|
          rule.class.node_types.each { |type| dispatcher.on(type) { |node| rule.visit(node) } }
        end
        dispatcher.run(source_file.ast)
        [instances.flat_map(&:offenses) + suppression.unused_offenses, rewriter]
      end
    end
  end
end
