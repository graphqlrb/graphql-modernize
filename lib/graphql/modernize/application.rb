# frozen_string_literal: true

require "etc"
require "open3"

module GraphQL
  module Modernize
    class Application
      FileResult = Data.define(:source_file, :rewritten, :offenses)
      Result = Data.define(:files, :parse_errors, :iterations)

      def initialize(config:, rules: RuleRegistry.all, jobs: Etc.nprocessors)
        @config = config
        @rules = rules
        @jobs = [Integer(jobs), 1].max
      end

      def run(paths = [])
        files = FileFinder.new(@config).find(paths)
        originals = files.to_h do |path|
          source_file = Astel::SourceFile.parse(path: path, version: @config.ruby_version)
          [path, source_file.source]
        end
        current = originals.dup
        offenses = Hash.new { |hash, path| hash[path] = {} }
        parse_errors = []
        iterations = 0

        @config.iterations.times do |iteration|
          iterations = iteration + 1
          source_files = parse_sources(current, parse_errors)
          hierarchy = ClassHierarchy.new(base_classes: @config.base_classes).build(source_files)
          iteration_results = process_files(source_files.map(&:path), current, hierarchy)
          changed = false

          iteration_results.each do |path, rewritten, found|
            found.each do |offense|
              key = [offense.rule_id, offense.location.start_offset, offense.message]
              offenses[path][key] ||= offense
              offenses[path][key].corrected ||= offense.corrected?
            end
            changed ||= current[path] != rewritten
            current[path] = rewritten
          end
          break unless changed
          raise Error, "rewrites did not converge after #{@config.iterations} iterations" if iterations == @config.iterations
        end

        results = originals.map do |path, source|
          source_file = Astel::SourceFile.from_string(source, path: path, version: @config.ruby_version)
          FileResult.new(source_file: source_file, rewritten: current[path], offenses: offenses[path].values)
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
        found, rewriter = Runner.new(hierarchy: hierarchy, config: @config).run(source_file, @rules)
        [path, rewriter.rewrite(validate: :parse), found]
      end
    end
  end
end
