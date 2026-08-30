# frozen_string_literal: true

module GraphQL
  module Modernize
    module RuleRegistry
      @rules = {}

      module_function

      def register(rule_class)
        id = rule_class.metadata.id
        raise ArgumentError, "duplicate rule id: #{id}" if @rules.key?(id)

        @rules[id] = rule_class
      end

      def all
        @rules.values.sort_by { |rule_class| rule_class.metadata.id }
      end

      def fetch(id)
        @rules.fetch(id.to_s.upcase) { raise ArgumentError, "unknown rule: #{id}" }
      end
    end
  end
end
