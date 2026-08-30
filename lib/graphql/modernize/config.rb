# frozen_string_literal: true

require "yaml"

module GraphQL
  module Modernize
    class Config
      DEFAULT_INCLUDE = ["app/graphql/**/*.rb", "lib/graphql/**/*.rb"].freeze
      DEFAULT_EXCLUDE = ["vendor/**/*", "tmp/**/*"].freeze
      DEFAULTS = {
        "include" => DEFAULT_INCLUDE,
        "exclude" => DEFAULT_EXCLUDE,
        "base_classes" => {},
        "rules" => {},
        "apply_unsafe" => false,
        "require_suppression_reason" => false,
        "iterations" => 3
      }.freeze
      KEYS = (DEFAULTS.keys + %w[from_version target_version ruby_version]).freeze

      attr_reader :root, :include_patterns, :exclude_patterns, :base_classes, :rules,
                  :ruby_version, :apply_unsafe, :from_version, :target_version,
                  :require_suppression_reason, :iterations

      def self.load(root: Dir.pwd, path: nil, overrides: {})
        root = File.expand_path(root)
        path ||= File.join(root, ".graphql-modernize.yml")
        file_options = File.file?(path) ? YAML.safe_load_file(path, aliases: false) : {}
        raise Error, "The configuration root must be a mapping" unless file_options.nil? || file_options.is_a?(Hash)

        options = DEFAULTS.merge(file_options || {}).merge(overrides.compact.transform_keys(&:to_s))
        unknown = options.keys - KEYS
        raise Error, "Unknown configuration keys: #{unknown.join(', ')}" unless unknown.empty?

        new(root: root, include_patterns: options["include"], exclude_patterns: options["exclude"],
            base_classes: options["base_classes"], rules: options["rules"], ruby_version: options["ruby_version"],
            apply_unsafe: options["apply_unsafe"], from_version: options["from_version"],
            target_version: options["target_version"],
            require_suppression_reason: options["require_suppression_reason"], iterations: options["iterations"])
      rescue Psych::Exception => e
        raise Error, "Unable to load the configuration file: #{e.message}"
      end

      def initialize(root: Dir.pwd, include_patterns: DEFAULT_INCLUDE, exclude_patterns: DEFAULT_EXCLUDE,
                     base_classes: {}, rules: {}, ruby_version: nil, apply_unsafe: false, from_version: nil,
                     target_version: nil, require_suppression_reason: false, iterations: 3)
        unless iterations.is_a?(Integer) && iterations.positive?
          raise Error, "iterations must be an integer greater than or equal to 1"
        end
        raise Error, "base_classes must be a mapping" unless base_classes.is_a?(Hash)
        raise Error, "rules must be a mapping" unless rules.is_a?(Hash)
        unless [true, false].include?(apply_unsafe) && [true, false].include?(require_suppression_reason)
          raise Error, "Boolean settings must be true or false"
        end
        unless Array(include_patterns).all?(String) && Array(exclude_patterns).all?(String)
          raise Error, "include and exclude must be arrays of strings"
        end
        raise Error, "Each rule configuration must be a mapping" unless rules.values.all?(Hash)

        @root = File.expand_path(root)
        @include_patterns = Array(include_patterns).freeze
        @exclude_patterns = Array(exclude_patterns).freeze
        @base_classes = base_classes.transform_keys(&:to_sym).transform_values { |names| Array(names) }.freeze
        @rules = rules.to_h { |id, options| [id.to_s, options.transform_keys(&:to_s).freeze] }.freeze
        @ruby_version = ruby_version
        @apply_unsafe = apply_unsafe
        @from_version = from_version || locked_graphql_version
        @target_version = target_version
        @require_suppression_reason = require_suppression_reason
        @iterations = iterations
      end

      def rule_enabled?(metadata)
        configured = rules.fetch(metadata.id, {})
        configured.fetch("enabled", metadata.default_enabled)
      end

      def rule_options(rule_id)
        rules.fetch(rule_id, {})
      end

      private

      def locked_graphql_version
        lockfile = File.join(root, "Gemfile.lock")
        return unless File.file?(lockfile)

        File.foreach(lockfile) do |line|
          match = line.match(/^    graphql \((\d+(?:\.\d+)+)/)
          return match[1] if match
        end
        nil
      end
    end
  end
end
