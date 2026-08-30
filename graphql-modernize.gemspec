# frozen_string_literal: true

require_relative "lib/graphql/modernize/version"

Gem::Specification.new do |spec|
  spec.name = "graphql-modernize"
  spec.version = GraphQL::Modernize::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Modernize deprecated graphql-ruby APIs"
  spec.description = "A Prism-based codemod for migrating deprecated graphql-ruby APIs."
  spec.homepage = "https://github.com/ydah/graphql-modernize"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "astel", ">= 0.2", "< 1.0"
end
