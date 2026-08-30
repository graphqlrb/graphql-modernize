# frozen_string_literal: true

module GraphQL
  module Modernize
    class SuppressionIndex
      Directive = Struct.new(:action, :line, :rules, :location, :inline, :valid, :used, keyword_init: true)
      PATTERN = /graphql-modernize:(?<action>disable-file|disable|enable)\b(?<body>.*)/

      def initialize(source_file, require_reason: false)
        @source_file = source_file
        first_statement = source_file.ast.statements.body.first
        @directives = source_file.comments.filter_map do |comment|
          match = comment.location.slice.match(PATTERN)
          next unless match

          reason = match[:body].split("--", 2)[1]
          next if require_reason && match[:action] != "enable" && reason.to_s.strip.empty?

          rules_text = match[:body].split("--", 2).first.strip
          ids = rules_text.split(/[,\s]+/)
          valid_rules = rules_text.empty? || ids.all? { |id| id.match?(/\AGQLM\d{3}\z/) }
          line_start = source_file.line_start(comment.location.start_offset)
          prefix = source_file.source.byteslice(line_start, comment.location.start_offset - line_start)
          inline = !prefix.strip.empty?
          valid_file_position = match[:action] != "disable-file" || (!inline &&
            (!first_statement || comment.location.start_offset < first_statement.location.start_offset))
          Directive.new(action: match[:action].tr("-", "_").to_sym, line: comment.location.start_line,
                        rules: rules_text.empty? ? nil : ids.freeze, location: comment.location,
                        inline: inline, valid: valid_rules && valid_file_position, used: false)
        end
      end

      def suppressed?(rule_id, location)
        directives = matching_directives(rule_id, location.start_line)
        file_directive = directives.find { |directive| directive.action == :disable_file }
        if file_directive
          file_directive.used = true
          return true
        end

        inline = directives.find do |directive|
          directive.inline && directive.action == :disable &&
            directive.line == location.start_line
        end
        if inline
          inline.used = true
          return true
        end

        active_directive = nil
        directives.reject(&:inline).each do |directive|
          active_directive = directive.action == :disable ? directive : nil
        end
        if active_directive
          active_directive.used = true
          closing = @directives.find do |directive|
            directive.valid && !directive.inline && directive.action == :enable &&
              directive.line > active_directive.line && matches_rule?(directive, rule_id)
          end
          closing.used = true if closing
        end
        !active_directive.nil?
      end

      def unused_offenses
        @directives.reject(&:used).map do |directive|
          Offense.new(rule_id: "GQLM000", location: directive.location,
                      message: "Unused suppression directive", safety: :manual,
                      path: @source_file.path, correctable: false)
        end
      end

      private

      def matching_directives(rule_id, line)
        @directives.select do |directive|
          next false unless directive.valid && matches_rule?(directive, rule_id)

          directive.action == :disable_file || directive.line <= line
        end
      end

      def matches_rule?(directive, rule_id)
        directive.rules.nil? || directive.rules.include?(rule_id)
      end
    end
  end
end
