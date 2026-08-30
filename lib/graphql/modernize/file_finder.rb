# frozen_string_literal: true

require "pathname"

module GraphQL
  module Modernize
    class FileFinder
      def initialize(config)
        @config = config
      end

      def find(paths = [])
        candidates = paths.empty? ? configured_files : explicit_files(paths)
        candidates.reject { |path| excluded?(path) }.uniq.sort
      end

      private

      attr_reader :config

      def configured_files
        config.include_patterns.flat_map { |pattern| Dir.glob(File.join(config.root, pattern)) }
      end

      def explicit_files(paths)
        paths.flat_map do |path|
          absolute = File.expand_path(path, config.root)
          if File.directory?(absolute)
            Dir.glob(File.join(absolute, "**/*.rb"))
          elsif File.file?(absolute) && absolute.end_with?(".rb")
            absolute
          else
            raise Error, "Input path does not exist or is not a Ruby file: #{path}"
          end
        end
      end

      def excluded?(path)
        relative = Pathname.new(path).relative_path_from(Pathname.new(config.root)).to_s
        config.exclude_patterns.any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      end
    end
  end
end
