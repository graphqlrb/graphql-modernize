# frozen_string_literal: true

module GraphQL
  module Modernize
    class SuppressionIndex
      Directive = Struct.new(:action, :line, :rules, :location, :used, keyword_init: true)
      PATTERN = /graphql-modernize:(?<action>disable-file|disable|enable)\b(?<body>.*)/

      def initialize(source_file, require_reason: false)
        @source_file = source_file
        @directives = source_file.comments.filter_map do |comment|
          match = comment.location.slice.match(PATTERN)
          next unless match
          next if require_reason && !match[:body].include?("--")

          ids = match[:body].split("--", 2).first.scan(/GQLM\d{3}/)
          Directive.new(action: match[:action].tr("-", "_").to_sym, line: comment.location.start_line,
                        rules: ids.empty? ? nil : ids.freeze, location: comment.location, used: false)
        end
      end

      def suppressed?(rule_id, location)
        directives = matching_directives(rule_id, location.start_line)
        file_directive = directives.find { |directive| directive.action == :disable_file }
        if file_directive
          file_directive.used = true
          return true
        end

        active_directive = nil
        directives.each do |directive|
          active_directive = directive.action == :disable ? directive : nil
        end
        active_directive.used = true if active_directive
        !active_directive.nil?
      end

      def unused_offenses
        @directives.reject(&:used).reject { |directive| directive.action == :enable }.map do |directive|
          Offense.new(rule_id: "GQLM000", location: directive.location,
                      message: "Unused suppression directive", safety: :manual,
                      path: @source_file.path, correctable: false)
        end
      end

      private

      def matching_directives(rule_id, line)
        @directives.select do |directive|
          next false unless directive.rules.nil? || directive.rules.include?(rule_id)

          directive.action == :disable_file || directive.line <= line
        end
      end
    end
  end
end
