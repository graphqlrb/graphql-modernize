# frozen_string_literal: true

require "json"
require "pathname"

module GraphQL
  module Modernize
    module Reporter
      module_function

      def render(format, result, diff: true)
        case format.to_s
        when "text" then text(result, diff: diff)
        when "diff" then diffs(result)
        when "json" then JSON.pretty_generate(payload(result)) << "\n"
        when "github" then github(result)
        when "sarif" then JSON.pretty_generate(sarif_payload(result)) << "\n"
        else raise Error, "Unknown output format: #{format}"
        end
      end

      def text(result, diff: true)
        offenses = result.files.flat_map(&:offenses)
        output = result.parse_errors.map do |path, errors|
          "#{path}: parse error: #{errors.join(', ')}"
        end.join("\n")
        output << "\n" unless output.empty?
        offense_output = offenses.map do |offense|
          status = offense.corrected? ? " corrected" : ""
          conflict = offense.conflicting_rule_id ? " conflicts_with=#{offense.conflicting_rule_id}" : ""
          "#{offense.path}:#{offense.location.start_line}:#{offense.location.start_column + 1}: " \
            "[#{offense.rule_id}]#{status}#{conflict} #{offense.message}"
        end.join("\n")
        output << offense_output
        output << "\n" unless output.empty?
        output << diffs(result) if diff
        changed = result.files.count { |file| file.source_file.source != file.rewritten }
        output << "#{result.files.length} files inspected, #{offenses.length} offenses, #{changed} files changed\n"
      end

      def diffs(result)
        result.files.filter_map do |file|
          next if file.source_file.source == file.rewritten

          Astel::Diff.unified(file.source_file.source, file.rewritten, path: relative_path(file.source_file.path))
        end.join
      end

      def github(result)
        result.files.flat_map(&:offenses).map do |offense|
          message = escape(offense.message)
          "::warning file=#{escape(offense.path)},line=#{offense.location.start_line}," \
            "col=#{offense.location.start_column + 1},title=#{offense.rule_id}::#{message}"
        end.join("\n") << (result.files.any? { |file| file.offenses.any? } ? "\n" : "")
      end

      def payload(result)
        {
          files: result.files.length,
          iterations: result.iterations,
          parse_errors: result.parse_errors.map { |path, errors| { path: path, errors: errors } },
          offenses: result.files.flat_map(&:offenses).map { |offense| offense_payload(offense) }
        }
      end

      def sarif_payload(result)
        offenses = result.files.flat_map(&:offenses)
        rules = offenses.uniq(&:rule_id).map do |offense|
          { id: offense.rule_id, shortDescription: { text: offense.message } }
        end
        results = offenses.map do |offense|
          {
            ruleId: offense.rule_id,
            message: { text: offense.message },
            locations: [{ physicalLocation: {
              artifactLocation: { uri: offense.path },
              region: { startLine: offense.location.start_line, startColumn: offense.location.start_column + 1 }
            } }]
          }
        end
        { version: "2.1.0", "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
          runs: [{ tool: { driver: { name: "graphql-modernize", rules: rules } }, results: results }] }
      end

      def offense_payload(offense)
        { rule_id: offense.rule_id, path: offense.path, line: offense.location.start_line,
          column: offense.location.start_column + 1, message: offense.message, safety: offense.safety,
          correctable: offense.correctable?, corrected: offense.corrected?,
          conflicting_rule_id: offense.conflicting_rule_id }
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(Pathname.new(Dir.pwd)).to_s
      rescue ArgumentError
        path
      end

      def escape(value)
        value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A").gsub(",", "%2C")
      end
    end
  end
end
