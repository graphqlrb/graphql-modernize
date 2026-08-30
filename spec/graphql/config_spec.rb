# frozen_string_literal: true

require "tmpdir"

RSpec.describe GraphQL::Modernize::Config do
  it "loads YAML and normalizes rule options" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".graphql-modernize.yml"), <<~YAML)
        include: ["graphql/**/*.rb"]
        apply_unsafe: true
        iterations: 2
        rules:
          GQLM401:
            enabled: true
      YAML

      config = described_class.load(root: root)

      expect(config.include_patterns).to eq(["graphql/**/*.rb"])
      expect(config.apply_unsafe).to be(true)
      expect(config.iterations).to eq(2)
      expect(config.rules.dig("GQLM401", "enabled")).to be(true)
    end
  end

  it "rejects unknown settings" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".graphql-modernize.yml"), "unknown: true\n")
      expect { described_class.load(root: root) }.to raise_error(GraphQL::Modernize::Error, /Unknown configuration/)
    end
  end
end
