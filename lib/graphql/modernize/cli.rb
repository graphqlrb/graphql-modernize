# frozen_string_literal: true

require "optparse"
require "pathname"

module GraphQL
  module Modernize
    class CLI
      COMMANDS = %w[run list explain doctor version].freeze
      PACKAGE_ROOT = File.expand_path("../../..", __dir__)

      def self.start(arguments = ARGV, out: $stdout, err: $stderr)
        new(arguments.dup, out: out, err: err).start
      end

      def initialize(arguments, out:, err:)
        @arguments = arguments
        @out = out
        @err = err
      end

      def start
        command = COMMANDS.include?(@arguments.first) ? @arguments.shift : "run"
        public_send(command)
      rescue StandardError => e
        @err.puts("graphql-modernize: #{e.message}")
        2
      end

      def run
        options = { diff: true, format: "text", jobs: Etc.nprocessors, force: false, strict: false }
        parser = run_parser(options)
        paths = catch(:help) { parser.parse(@arguments) }
        return 0 if paths == :help

        config = Config.load(root: Dir.pwd, overrides: config_overrides(options))
        rules = selected_rules(options, config)
        application = Application.new(config: config, rules: rules, jobs: options[:jobs],
                                      explicit_rule_ids: options[:only] || [])
        application.ensure_write_safe!(paths: paths, force: options[:force]) if options[:write]
        result = application.run(paths)
        warn_parse_errors(result) unless %w[text json].include?(options[:format])
        output = Reporter.render(options[:format], result, diff: options[:diff])
        if options[:out]
          ensure_output_is_not_source!(options[:out], result)
          File.write(options[:out], output)
        else
          @out.write(output)
        end
        strict_failure = options[:strict] && result.parse_errors.any?
        application.write(result) if options[:write] && !strict_failure
        return 2 if strict_failure

        unresolved?(result, options[:fail_level]) ? 1 : 0
      end

      def list
        parse_no_options("list")
        RuleRegistry.all.each do |rule|
          metadata = rule.metadata
          @out.puts("#{metadata.id}\t#{metadata.safety}\t#{metadata.summary}")
        end
        0
      end

      def explain
        parser = OptionParser.new { |opts| opts.banner = "Usage: graphql-modernize explain RULE_ID" }
        parser.parse!(@arguments)
        raise Error, "Specify exactly one RULE_ID" unless @arguments.one?

        metadata = RuleRegistry.fetch(@arguments.first).metadata
        @out.puts("#{metadata.id}: #{metadata.summary}")
        @out.puts("safety: #{metadata.safety}")
        @out.puts("since: #{metadata.since}") if metadata.since
        @out.puts("removed_in: #{metadata.removed_in}") if metadata.removed_in
        docs = metadata.docs && File.expand_path(metadata.docs, PACKAGE_ROOT)
        @out.puts("\n#{File.read(docs)}") if docs && File.file?(docs)
        0
      end

      def doctor
        parse_no_options("doctor")
        config = Config.load(root: Dir.pwd)
        files = FileFinder.new(config).find
        @out.puts("configuration: ok")
        @out.puts("ruby: #{RUBY_VERSION}")
        @out.puts("astel: #{Astel::VERSION}")
        @out.puts("graphql: #{config.from_version || 'unknown'} -> #{config.target_version || 'unknown'}")
        @out.puts("files: #{files.length}")
        0
      end

      def version
        parse_no_options("version")
        @out.puts(GraphQL::Modernize::VERSION)
        0
      end

      private

      def run_parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: graphql-modernize run [PATHS...] [options]"
          opts.on("--write", "Rewrite files") { options[:write] = true }
          opts.on("--[no-]diff", "Print a diff") { |value| options[:diff] = value }
          opts.on("--only IDS", Array, "Run only the specified rules") { |value| options[:only] = value }
          opts.on("--except IDS", Array, "Exclude the specified rules") { |value| options[:except] = value }
          opts.on("--target-version VERSION") { |value| options[:target_version] = value }
          opts.on("--from-version VERSION") { |value| options[:from_version] = value }
          opts.on("--ruby-version VERSION") { |value| options[:ruby_version] = value }
          opts.on("--unsafe", "Apply unsafe corrections") { options[:apply_unsafe] = true }
          opts.on("--iterations N", Integer) { |value| options[:iterations] = value }
          opts.on("--format FORMAT", %w[text diff json github sarif]) { |value| options[:format] = value }
          opts.on("--out PATH") { |value| options[:out] = value }
          opts.on("--jobs N", Integer) { |value| options[:jobs] = value }
          opts.on("--strict") { options[:strict] = true }
          opts.on("--force") { options[:force] = true }
          opts.on("--fail-level LEVEL", %w[any manual unsafe none]) { |value| options[:fail_level] = value }
          opts.on("--no-color") { options[:no_color] = true }
          opts.on("-h", "--help") do
            @out.puts(opts)
            throw :help, :help
          end
        end
      end

      def config_overrides(options)
        options.slice(:target_version, :from_version, :ruby_version, :apply_unsafe, :iterations)
      end

      def selected_rules(options, config)
        rules = options[:only] ? options[:only].map { |id| RuleRegistry.fetch(id) }.uniq : RuleRegistry.all
        excluded = Array(options[:except]).map { |id| RuleRegistry.fetch(id).metadata.id }
        rules = rules.reject { |rule| excluded.include?(rule.metadata.id) }
        return rules unless config.target_version

        target = Gem::Version.new(config.target_version)
        rules.select do |rule|
          boundary = rule.metadata.since || rule.metadata.removed_in
          !boundary || target >= Gem::Version.new(boundary)
        end
      end

      def ensure_output_is_not_source!(output_path, result)
        output = File.expand_path(output_path)
        conflict = result.files.any? do |file|
          source = File.expand_path(file.source_file.path)
          output == source || (File.exist?(output) && File.identical?(output, source))
        end
        raise Error, "--out must differ from every input file" if conflict
      end

      def warn_parse_errors(result)
        result.parse_errors.each do |path, errors|
          @err.puts("#{path}: parse error: #{errors.join(', ')}")
        end
      end

      def unresolved?(result, fail_level)
        offenses = result.files.flat_map(&:offenses).reject(&:corrected?)
        case fail_level || "any"
        when "none" then false
        when "manual" then offenses.any? { |offense| offense.safety == :manual }
        when "unsafe" then offenses.any? { |offense| %i[manual unsafe].include?(offense.safety) }
        else offenses.any?
        end
      end

      def parse_no_options(command)
        OptionParser.new { |opts| opts.banner = "Usage: graphql-modernize #{command}" }.parse!(@arguments)
        raise Error, "Unexpected arguments: #{@arguments.join(' ')}" unless @arguments.empty?
      end
    end
  end
end
