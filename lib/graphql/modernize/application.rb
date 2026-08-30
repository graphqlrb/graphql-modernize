# frozen_string_literal: true

require "etc"
require "open3"

module GraphQL
  module Modernize
    class Application
      FileResult = Data.define(:source_file, :rewritten, :offenses)
      Result = Data.define(:files, :parse_errors, :iterations)

      def initialize(config:, rules: RuleRegistry.all, jobs: Etc.nprocessors, explicit_rule_ids: [])
        @config = config
        @rules = rules
        @explicit_rule_ids = explicit_rule_ids.map { |id| id.to_s.upcase }.freeze
        @jobs = Integer(jobs)
        raise Error, "jobs must be an integer greater than or equal to 1" unless @jobs.positive?
      end

      def run(paths = [])
        files = FileFinder.new(@config).find(paths)
        originals = files.to_h do |path|
          source_file = Astel::SourceFile.parse(path: path, version: @config.ruby_version)
          [path, source_file.source]
        end
        current = originals.dup
        corrected_offenses = Hash.new { |hash, path| hash[path] = [] }
        current_offenses = Hash.new { |hash, path| hash[path] = [] }
        parse_errors = []
        iterations = 0

        (@config.iterations + 1).times do |iteration|
          iterations = iteration + 1
          source_files = parse_sources(current, parse_errors)
          hierarchy = ClassHierarchy.new(base_classes: @config.base_classes).build(source_files)
          iteration_results = process_files(source_files.map(&:path), current, hierarchy)
          changed = false

          iteration_results.each do |path, rewritten, found|
            current_offenses[path] = found
            corrected_offenses[path].concat(found.select(&:corrected?))
            changed ||= current[path] != rewritten
            current[path] = rewritten
          end
          break unless changed

          next unless iterations > @config.iterations

          rule_ids = iteration_results.flat_map do |_path, _rewritten, found|
            found.filter_map do |offense|
              offense.rule_id if offense.corrected? || offense.conflicting_rule_id
            end
          end.uniq.sort
          detail = rule_ids.empty? ? "" : " (related rules: #{rule_ids.join(', ')})"
          raise Error, "rewrites did not converge after #{@config.iterations} iterations#{detail}"
        end

        results = originals.map do |path, source|
          source_file = Astel::SourceFile.from_string(source, path: path, version: @config.ruby_version)
          unresolved = current_offenses[path].reject(&:corrected?)
          FileResult.new(source_file: source_file, rewritten: current[path],
                         offenses: corrected_offenses[path] + unresolved)
        end
        Result.new(files: results, parse_errors: parse_errors.uniq, iterations: iterations)
      end

      def ensure_write_safe!(force: false)
        return if force

        _output, _error, status = Open3.capture3("git", "-C", @config.root, "rev-parse", "--is-inside-work-tree")
        raise Error, "--write must run inside a Git working tree (use --force to override)" unless status.success?

        output, = Open3.capture2("git", "-C", @config.root, "status", "--porcelain")
        raise Error, "The working tree is not clean (use --force to override)" unless output.empty?
      end

      def write(result)
        result.files.each do |file|
          next if file.source_file.source == file.rewritten

          File.binwrite(file.source_file.path, file.rewritten)
        end
      end

      private

      def parse_sources(contents, parse_errors)
        contents.filter_map do |path, source|
          parsed = Astel::SourceFile.from_string(source, path: path, version: @config.ruby_version)
          if parsed.valid?
            parsed
          else
            parse_errors << [path, parsed.errors.map(&:message)]
            nil
          end
        end
      end

      def process_files(paths, contents, hierarchy)
        sequential = @jobs == 1 || !Process.respond_to?(:fork)
        return paths.map { |path| process_file(path, contents.fetch(path), hierarchy) } if sequential

        paths.each_slice(@jobs).flat_map do |batch|
          workers = batch.map do |path|
            reader, writer = IO.pipe
            pid = Process.fork do
              reader.close
              Marshal.dump([true, process_file(path, contents.fetch(path), hierarchy)], writer)
            rescue StandardError => e
              Marshal.dump([false, [e.class.name, e.message]], writer)
            ensure
              writer.close
              exit! 0
            end
            writer.close
            [pid, reader]
          end
          workers.map do |pid, reader|
            success, payload = Marshal.load(reader) # rubocop:disable Security/MarshalLoad -- trusted forked worker only
            Process.wait(pid)
            raise Error, "worker failed: #{payload.join(': ')}" unless success

            payload
          ensure
            reader.close
          end
        end
      end

      def process_file(path, source, hierarchy)
        source_file = Astel::SourceFile.from_string(source, path: path, version: @config.ruby_version)
        found, rewriter = Runner.new(hierarchy: hierarchy, config: @config,
                                     explicit_rule_ids: @explicit_rule_ids).run(source_file, @rules)
        [path, rewriter.rewrite(validate: :parse), found]
      rescue Astel::Rewriter::ValidationError => e
        rules = found ? found.select(&:corrected?).map(&:rule_id).uniq.sort : []
        edits = if rewriter
                  rewriter.edits.map do |edit|
                    "#{edit.start_offset}...#{edit.end_offset}=#{edit.replacement.inspect}"
                  end
                else
                  []
                end
        raise Error, "Rewritten source failed syntax validation: #{path}; rules=#{rules.join(',')}; " \
                     "edits=[#{edits.join(', ')}]; errors=#{e.parse_errors.map(&:message).join(', ')}; " \
                     "Please report an issue with reproduction details."
      end
    end
  end
end
