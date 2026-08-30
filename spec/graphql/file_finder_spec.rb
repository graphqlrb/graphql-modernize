# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe GraphQL::Modernize::FileFinder do
  it "expands Ruby files and applies exclusions" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p("#{root}/app/graphql/legacy")
      File.write("#{root}/app/graphql/type.rb", "")
      File.write("#{root}/app/graphql/legacy/type.rb", "")
      config = GraphQL::Modernize::Config.new(root: root, exclude_patterns: ["app/graphql/legacy/**/*.rb"])

      expect(described_class.new(config).find).to eq(["#{root}/app/graphql/type.rb"])
    end
  end
end
