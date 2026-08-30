# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe "advanced migration rules" do
  it "applies unsafe superclass migrations only when requested" do
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    expect_correction(
      GraphQL::Modernize::Rules::FunctionSuperclass,
      "class FindUser < GraphQL::Function\nend\n",
      "class FindUser < GraphQL::Schema::Resolver\nend\n",
      config: config
    )
    expect_correction(
      GraphQL::Modernize::Rules::RelayMutationSuperclass,
      "class UpdateUser < GraphQL::Relay::Mutation\nend\n",
      "class UpdateUser < GraphQL::Schema::RelayClassicMutation\nend\n",
      config: config
    )
  end

  it "detects manual legacy migrations without editing" do
    cases = {
      GraphQL::Modernize::Rules::DefineDsl => "UserType = GraphQL::ObjectType.define do\nend\n",
      GraphQL::Modernize::Rules::DeprecatedDefinitionCall => "type.to_graphql\n",
      GraphQL::Modernize::Rules::QueryArgumentsConstant => "GraphQL::Query::Arguments.new\n",
      GraphQL::Modernize::Rules::RelayConnectionType => "GraphQL::Relay::ConnectionType.create_type(User)\n",
      GraphQL::Modernize::Rules::RelayNodeField => "GraphQL::Relay::Node.field\n"
    }
    cases.each do |rule, code|
      offenses, rewriter = run_rule(rule, code)
      expect(offenses.map(&:rule_id)).to eq([rule.metadata.id])
      expect(rewriter.rewrite).to eq(code)
    end
  end

  it "detects resolve options across proc shapes without false positives" do
    detected = [
      "resolve: -> { 1 }",
      "resolve: ->(obj, args, ctx) { obj }",
      "resolve: lambda { 1 }",
      "resolve: proc { 1 }",
      "resolve: method(:resolve_name)",
      "resolve: RESOLVER",
      "resolve: ->(*) { 1 }",
      "resolve: ->(_object, _arguments, _context) { external }",
      "resolve: -> do\n      1\n    end",
      "resolve: ->(object, **) { object }"
    ]
    detected.each do |option|
      code = "class UserType < Types::BaseObject\n  field :name, String, #{option}\nend\n"
      offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, code)
      expect(offenses.map(&:rule_id)).to eq(["GQLM102"])
      expect(rewriter.rewrite).to eq(code)
    end

    ignored = [
      "class Form\n  field :name, String, resolve: -> { 1 }\nend\n",
      "object.field :name, String, resolve: -> { 1 }\n",
      "# field :name, String, resolve: -> { 1 }\n",
      "\"field :name, String, resolve: -> { 1 }\"\n",
      "{ field: :name, resolve: -> { 1 } }\n",
      "resolve(field: :name)\n",
      "class UserType < Types::BaseObject\n  field :name, String\nend\n",
      "class UserType < Types::BaseObject\n  self.field :name, String, resolve: -> { 1 }\nend\n",
      "class UserType\n  field :name, String, resolve: -> { 1 }\nend\n",
      "field(:name, String, resolve: -> { 1 })\n"
    ]
    ignored.each do |code|
      offenses, = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, code)
      expect(offenses).to be_empty
    end
  end

  it "adds Visibility after schema root configuration and remains idempotent" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app/graphql"))
      schema = File.join(root, "app/graphql/schema.rb")
      type = File.join(root, "app/graphql/type.rb")
      File.write(schema, "class AppSchema < GraphQL::Schema\n  query Types::Query\nend\n")
      File.write(type, "class UserType < Types::BaseObject\n  def self.visible?(_ctx) = true\nend\n")
      config = GraphQL::Modernize::Config.new(root: root, apply_unsafe: true)
      application = GraphQL::Modernize::Application.new(
        config: config,
        rules: [GraphQL::Modernize::Rules::VisibilityPlugin],
        jobs: 1
      )

      result = application.run
      rewritten = result.files.find { |file| file.source_file.path == schema }.rewritten

      expect(rewritten).to include("query Types::Query\n  use GraphQL::Schema::Visibility, migration_errors: true")
      expect(result.files.flat_map(&:offenses).map(&:rule_id)).to eq(["GQLM307"])
    end
  end

  it "removes each obsolete pagination setting" do
    code = <<~RUBY
      class AppSchema < GraphQL::Schema
        self.bidirectional_pagination = true
        self.default_nodes_field = false
      end
    RUBY
    first, first_rewriter = run_rule(GraphQL::Modernize::Rules::BidirectionalPagination, code)
    second, second_rewriter = run_rule(GraphQL::Modernize::Rules::DefaultNodesField, first_rewriter.rewrite)

    expect(first.map(&:rule_id)).to eq(["GQLM305"])
    expect(second.map(&:rule_id)).to eq(["GQLM306"])
    expect(second_rewriter.rewrite).to eq("class AppSchema < GraphQL::Schema\nend\n")
  end

  it "keeps modernize rules opt-in" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String, null: true
        argument :id, ID, required: true
      end
    RUBY
    disabled = GraphQL::Modernize::Config.new
    enabled = GraphQL::Modernize::Config.new(
      rules: { "GQLM401" => { "enabled" => true }, "GQLM402" => { "enabled" => true } }
    )
    source = Astel::SourceFile.from_string(code, path: "example.rb")
    hierarchy = GraphQL::Modernize::ClassHierarchy.new.build([source])

    disabled_offenses, = GraphQL::Modernize::Runner.new(hierarchy: hierarchy, config: disabled).run(
      source,
      [GraphQL::Modernize::Rules::RedundantRequiredTrue, GraphQL::Modernize::Rules::RedundantNullTrue]
    )
    enabled_offenses, rewriter = GraphQL::Modernize::Runner.new(hierarchy: hierarchy, config: enabled).run(
      source,
      [GraphQL::Modernize::Rules::RedundantRequiredTrue, GraphQL::Modernize::Rules::RedundantNullTrue]
    )

    expect(disabled_offenses).to be_empty
    expect(enabled_offenses.map(&:rule_id)).to contain_exactly("GQLM401", "GQLM402")
    expect(rewriter.rewrite(validate: :parse)).not_to include("null: true", "required: true")
  end
end
