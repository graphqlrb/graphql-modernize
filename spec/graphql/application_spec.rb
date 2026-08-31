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

  it "refuses writes when Git cannot inspect the working tree" do
    success = instance_double(Process::Status, success?: true)
    failure = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["true\n", "", success], ["", "broken index", failure])

    application = described_class.new(config: GraphQL::Modernize::Config.new, rules: [], jobs: 1)
    expect { application.ensure_write_safe! }.to raise_error(GraphQL::Modernize::Error, /broken index/)
  end

  it "refuses writes in a bare Git repository" do
    success = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(["false\n", "", success])

    application = described_class.new(config: GraphQL::Modernize::Config.new, rules: [], jobs: 1)
    expect { application.ensure_write_safe! }.to raise_error(GraphQL::Modernize::Error, /Git working tree/)
  end

  it "refuses write targets outside or linked through the Git working tree" do
    Dir.mktmpdir do |directory|
      root = File.join(directory, "repo")
      outside = File.join(directory, "outside.rb")
      linked = File.join(root, "linked.rb")
      FileUtils.mkdir_p(root)
      File.write(outside, "class Outside; end\n")
      FileUtils.ln_s(outside, linked)
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(
        ["true\n", "", success], ["", "", success], ["#{root}\n", "", success]
      )
      application = described_class.new(config: GraphQL::Modernize::Config.new(root: root), rules: [], jobs: 1)

      expect do
        application.ensure_write_safe!(paths: [outside])
      end.to raise_error(GraphQL::Modernize::Error, /outside the Git working tree/)

      allow(Open3).to receive(:capture3).and_return(
        ["true\n", "", success], ["", "", success], ["#{root}\n", "", success]
      )
      expect do
        application.ensure_write_safe!(paths: [linked])
      end.to raise_error(GraphQL::Modernize::Error, /symbolic link/)
    end
  end

  it "refuses an untracked write target even when Git reports a clean tree" do
    Dir.mktmpdir do |root|
      path = File.join(root, "ignored.rb")
      File.write(path, "class Ignored; end\n")
      success = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(
        ["true\n", "", success], ["", "", success], ["#{root}\n", "", success], ["", "", success]
      )
      application = described_class.new(config: GraphQL::Modernize::Config.new(root: root), rules: [], jobs: 1)

      expect do
        application.ensure_write_safe!(paths: [path])
      end.to raise_error(GraphQL::Modernize::Error, /not tracked by Git/)
    end
  end

  it "uses the configured rewrite rounds plus a convergence check" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.write(path, <<~RUBY)
        class Type < Types::BaseObject
          field :name, String, property: :name, field: nil, null: true
        end
      RUBY
      config = GraphQL::Modernize::Config.new(
        root: root,
        rules: { "GQLM402" => { "enabled" => true } },
        iterations: 3
      )
      result = described_class.new(
        config: config,
        rules: [GraphQL::Modernize::Rules::PropertyOption,
                GraphQL::Modernize::Rules::RemovedFieldOptions,
                GraphQL::Modernize::Rules::RedundantNullTrue],
        jobs: 1
      ).run([path])

      expect(result.iterations).to eq(4)
      expect(result.files.first.rewritten).to include("field :name, String")
      expect(result.files.first.rewritten).not_to include("property:", "field:", "null:")
      expect(result.files.first.offenses).to all(be_corrected)
    end
  end

  it "allows the initial rewrite plus the configured conflict retries" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.write(path, <<~RUBY)
        class Type < Types::BaseObject
          field :name, String, resolve: ->(obj, _args, _ctx) { obj.name },
                property: :name, field: nil, null: true
        end
      RUBY
      config = GraphQL::Modernize::Config.new(
        root: root,
        apply_unsafe: true,
        rules: { "GQLM402" => { "enabled" => true } },
        iterations: 3
      )
      result = described_class.new(
        config: config,
        rules: [GraphQL::Modernize::Rules::ResolveFieldOption,
                GraphQL::Modernize::Rules::PropertyOption,
                GraphQL::Modernize::Rules::RemovedFieldOptions,
                GraphQL::Modernize::Rules::RedundantNullTrue],
        jobs: 1
      ).run([path])

      expect(result.iterations).to eq(5)
      expect(result.files.first.rewritten).not_to include("resolve:", "property:", "field:", "null:")
    end
  end

  it "still stops oscillating rewrites after the retry limit" do
    forward = Class.new(GraphQL::Modernize::Rules::Base) do
      rule id: "GQLM996", safety: :safe, summary: "test forward rewrite"
      node_pattern :constant_read_node, "(constant_read_node name: :OLD)"

      def on_match(node, _captures)
        add_offense(node.location, message: "forward") { |rewriter| rewriter.replace(node.location, "NEW") }
      end
    end
    backward = Class.new(GraphQL::Modernize::Rules::Base) do
      rule id: "GQLM997", safety: :safe, summary: "test backward rewrite"
      node_pattern :constant_read_node, "(constant_read_node name: :NEW)"

      def on_match(node, _captures)
        add_offense(node.location, message: "backward") { |rewriter| rewriter.replace(node.location, "OLD") }
      end
    end

    Dir.mktmpdir do |root|
      path = File.join(root, "value.rb")
      File.write(path, "OLD\n")
      config = GraphQL::Modernize::Config.new(root: root, iterations: 1)

      expect { described_class.new(config: config, rules: [forward, backward], jobs: 1).run([path]) }
        .to raise_error(GraphQL::Modernize::Error, /1 retry iterations.*GQLM996/)
    end
  end
end
