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

  it "rejects malformed nested settings and versions" do
    expect { described_class.new(base_classes: { object: "BaseObject" }) }
      .to raise_error(GraphQL::Modernize::Error, /base_classes/)
    expect { described_class.new(rules: { "GQLM401" => { "enabled" => "yes" } }) }
      .to raise_error(GraphQL::Modernize::Error, /enabled/)
    expect { described_class.new(target_version: "next") }
      .to raise_error(GraphQL::Modernize::Error, /version/)
    expect { described_class.new(base_classes: { typo: ["Base"] }) }
      .to raise_error(GraphQL::Modernize::Error, /base_classes kind/)
    expect { described_class.new(rules: { "GQLM9999" => {} }) }
      .to raise_error(GraphQL::Modernize::Error, /rule ID/)
    expect { described_class.new(from_version: "2.6", target_version: "2.5") }
      .to raise_error(GraphQL::Modernize::Error, /from_version/)
    expect { described_class.new(rules: { "GQLM307" => { "migration_errors" => "yes" } }) }
      .to raise_error(GraphQL::Modernize::Error, /migration_errors/)
    expect { described_class.new(base_classes: { object: [""] }) }
      .to raise_error(GraphQL::Modernize::Error, /class names/)
    expect { described_class.new(rules: { "GQLM401" => { "enable" => true } }) }
      .to raise_error(GraphQL::Modernize::Error, /Unknown settings/)
    expect { described_class.new(ruby_version: "latest") }
      .to raise_error(GraphQL::Modernize::Error, /ruby_version/)
    expect { described_class.new(ruby_version: 3.3) }
      .to raise_error(GraphQL::Modernize::Error, /ruby_version/)
    expect { described_class.new(target_version: 2.6) }
      .to raise_error(GraphQL::Modernize::Error, /version/)
    expect { described_class.new(target_version: " ") }
      .to raise_error(GraphQL::Modernize::Error, /empty/)
  end

  it "normalizes configured rule IDs" do
    config = described_class.new(rules: { "gqlm401" => { "enabled" => true } })

    expect(config.rule_enabled?(GraphQL::Modernize::Rules::RedundantRequiredTrue.metadata)).to be(true)
  end
end
