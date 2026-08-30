# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe GraphQL::Modernize::Application do
  it "processes independent files in workers and preserves the original diff base" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app/graphql"))
      2.times do |index|
        File.write(File.join(root, "app/graphql/type_#{index}.rb"), <<~RUBY)
          class Type#{index} < Types::BaseObject
            field :name, String, property: :name
          end
        RUBY
      end
      config = GraphQL::Modernize::Config.new(root: root)
      result = described_class.new(config: config, rules: [GraphQL::Modernize::Rules::PropertyOption], jobs: 2).run

      expect(result.files.length).to eq(2)
      expect(result.files).to all(satisfy { |file| file.rewritten.include?("method: :name") })
      expect(result.files.flat_map(&:offenses)).to all(be_corrected)
    end
  end

  it "does not treat source encoding normalization as a rewrite" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.binwrite(path, "# café\nclass Type < Types::BaseObject\nend\n")
      config = GraphQL::Modernize::Config.new(root: root, iterations: 1)
      result = described_class.new(config: config, rules: [], jobs: 1).run([path])

      expect(result.iterations).to eq(1)
      expect(result.files.first.rewritten).to eq(result.files.first.source_file.source)
    end
  end

  it "does not retain a stale unresolved offense after a later iteration resolves it" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.write(path, <<~RUBY)
        class Type < Types::BaseObject
          field :name, String, property: :name
        end
      RUBY
      config = GraphQL::Modernize::Config.new(root: root)
      result = described_class.new(
        config: config,
        rules: [GraphQL::Modernize::Rules::PropertyOption, GraphQL::Modernize::Rules::PropertyOption],
        jobs: 1
      ).run([path])

      expect(result.files.first.offenses).to all(be_corrected)
      expect(result.files.first.offenses.map(&:rule_id)).to eq(["GQLM106"])
    end
  end

  it "reports reproducible diagnostics when a rewrite creates invalid syntax" do
    bad_rule = Class.new(GraphQL::Modernize::Rules::Base) do
      rule id: "GQLM998", safety: :safe, summary: "test invalid rewrite"
      node_pattern :class_node, "(class_node)"

      def on_match(node, _captures)
        add_offense(node.superclass.location, message: "break syntax") do |rewriter|
          rewriter.replace(node.superclass.location, "(")
        end
      end
    end

    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.write(path, "class Type < Types::BaseObject\nend\n")
      config = GraphQL::Modernize::Config.new(root: root)

      expect { described_class.new(config: config, rules: [bad_rule], jobs: 1).run([path]) }
        .to raise_error(GraphQL::Modernize::Error, /type\.rb; rules=GQLM998; edits=.*issue/)
    end
  end
end
