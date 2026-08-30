# frozen_string_literal: true

module GraphQL
  module Modernize
    class Config
      DEFAULT_INCLUDE = ["app/graphql/**/*.rb", "lib/graphql/**/*.rb"].freeze
      DEFAULT_EXCLUDE = ["vendor/**/*", "tmp/**/*"].freeze

      attr_reader :root, :include_patterns, :exclude_patterns, :base_classes, :rules,
                  :ruby_version, :apply_unsafe

      def initialize(root: Dir.pwd, include_patterns: DEFAULT_INCLUDE, exclude_patterns: DEFAULT_EXCLUDE,
                     base_classes: {}, rules: {}, ruby_version: nil, apply_unsafe: false)
        @root = File.expand_path(root)
        @include_patterns = Array(include_patterns).freeze
        @exclude_patterns = Array(exclude_patterns).freeze
        @base_classes = base_classes.transform_keys(&:to_sym).transform_values { |names| Array(names) }.freeze
        @rules = rules.transform_keys(&:to_s).freeze
        @ruby_version = ruby_version
        @apply_unsafe = apply_unsafe
      end

      def rule_enabled?(metadata)
        configured = rules.fetch(metadata.id, {})
        configured.fetch("enabled", metadata.default_enabled)
      end

      def rule_options(rule_id)
        rules.fetch(rule_id, {})
      end
    end
  end
end
