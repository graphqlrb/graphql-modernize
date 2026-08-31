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
    expect_correction(
      GraphQL::Modernize::Rules::FunctionSuperclass,
      "class FindUser < ::GraphQL::Function\nend\n",
      "class FindUser < ::GraphQL::Schema::Resolver\nend\n",
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

  it "does not report legacy conversion internals on framework base classes" do
    code = <<~RUBY
      module GraphQL
        class Schema
          def deprecated_graphql_definition
            graphql_definition(silence_deprecation_warning: true)
          end
        end
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::DeprecatedDefinitionCall, code)

    expect(offenses).to be_empty
    expect(rewriter.rewrite).to eq(code)
  end

  it "converts a self-contained resolve lambda to a method before private" do
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    before = <<~RUBY
      class UserType < Types::BaseObject
        field :posts, [PostType], null: false, resolve: ->(obj, _args, ctx) {
          obj.posts.where(context: ctx)
        }

        private

        def helper = true
      end
    RUBY
    after = <<~RUBY
      class UserType < Types::BaseObject
        field :posts, [PostType], null: false

        def posts(**)
          object.posts.where(context: context)
        end

        private

        def helper = true
      end
    RUBY

    expect_correction(GraphQL::Modernize::Rules::ResolveFieldOption, before, after, config: config)
  end

  it "downgrades resolve forms that cannot be converted without changing semantics" do
    detected = [
      "resolve: -> { 1 }",
      "resolve: lambda { 1 }",
      "resolve: proc { 1 }",
      "resolve: method(:resolve_name)",
      "resolve: RESOLVER",
      "resolve: ->(*) { 1 }",
      "resolve: ->(_object, _arguments, _context) { external }",
      "resolve: -> do\n      1\n    end",
      "resolve: ->(object, **) { object }",
      "resolve: ->(obj, args, ctx) { args[:id] }",
      "resolve: ->(obj, args, ctx) { helper(obj) }",
      "resolve: ->(obj, args, ctx) { obj.items.map { |item| item.id } }",
      "resolve: ->(obj, args, ctx) { obj = obj.parent; obj.name }",
      "resolve: ->(obj, args, ctx) { object = obj.parent; ctx[object.id] }",
      "resolve: ->(obj, args, ctx) { context = ctx.merge(admin: true); obj.name if context[:admin] }",
      "resolve: ->(obj, args, ctx) { super() }",
      "resolve: ->(obj, args, ctx) { next obj.name }",
      "resolve: ->(obj, args, ctx) {\n      # keep this comment\n      obj.name\n    }"
    ]
    detected.each do |option|
      code = "class UserType < Types::BaseObject\n  field :name, String, #{option}\nend\n"
      offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, code)
      expect(offenses.map(&:rule_id)).to eq(["GQLM102"])
      expect(offenses.first.safety).to eq(:manual)
      expect(rewriter.rewrite).to eq(code)
    end

    %i[object context initialize].each do |field_name|
      code = "class UserType < Types::BaseObject\n  field :#{field_name}, String, " \
             "resolve: ->(obj, _args, _ctx) { obj.public_send(:#{field_name}) }\nend\n"
      offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, code)
      expect(offenses.map(&:safety)).to eq([:manual])
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

  it "does not generate a resolver method that already exists" do
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String, resolve: ->(obj, _args, _ctx) { obj.name }
        field :other, String, resolve: ->(obj, _args, _ctx) { obj.other }
        field :nickname, String, resolve: ->(obj, _args, _ctx) { obj.nickname }
        field :nested, String, resolve: ->(obj, _args, _ctx) { obj.nested }
        field :hidden, String, resolve: ->(obj, _args, _ctx) { obj.hidden }

        attr :other
        alias nickname other
        begin
          def nested = object.nested
        end
        private attr_reader :hidden
        private def name = object.name
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, code, config: config)

    expect(offenses.map(&:safety)).to eq(%i[manual manual manual manual manual])
    expect(rewriter.rewrite).to eq(code)
  end

  it "does not partially convert duplicate resolve options" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String,
              resolve: ->(obj, _args, _ctx) { obj.first },
              resolve: ->(obj, _args, _ctx) { obj.last }
        field :other, String, **options,
              resolve: ->(obj, _args, _ctx) { obj.other }
      end
    RUBY
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, code, config: config)

    expect(offenses.map(&:safety)).to eq(%i[manual manual])
    expect(rewriter.rewrite).to eq(code)
  end

  it "rewrites parameter references by byte offset in UTF-8 source" do
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    before = <<~RUBY
      class UserType < Types::BaseObject
        field :label, String, resolve: ->(obj, _args, ctx) { "café: \#{obj.name} / \#{ctx[:locale]}" }
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ResolveFieldOption, before, config: config)
    rewritten = rewriter.rewrite(validate: :parse)

    expect(offenses.first).to be_corrected
    expect(rewritten).to include("\"café: \#{object.name} / \#{context[:locale]}\"")
  end

  it "adds Visibility after schema configuration and remains idempotent" do
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

  it "does not infer application visibility requirements from framework definitions" do
    code = <<~RUBY
      module GraphQL
        class Schema
          def self.visible?(_context) = true
        end
      end

      class AppSchema < GraphQL::Schema
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, code,
                                  config: GraphQL::Modernize::Config.new(apply_unsafe: true))

    expect(offenses).to be_empty
    expect(rewriter.rewrite).to eq(code)
  end

  it "does not infer visibility requirements from instance methods" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        def visible?(_context) = true
      end

      class AppSchema < GraphQL::Schema
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, code,
                                  config: GraphQL::Modernize::Config.new(apply_unsafe: true))

    expect(offenses).to be_empty
    expect(rewriter.rewrite).to eq(code)
  end

  it "does not accept receiver calls as schema migration configuration" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        def self.visible?(_context) = true
      end

      class AppSchema < GraphQL::Schema
        helper.use GraphQL::Schema::Visibility
        helper.complexity_cost_calculation_mode :legacy
      end
    RUBY
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    visibility, = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, code, config: config)
    complexity, = run_rule(GraphQL::Modernize::Rules::ComplexityCostMode, code, config: config)

    expect(visibility.map(&:rule_id)).to eq(["GQLM307"])
    expect(complexity.map(&:rule_id)).to eq(["GQLM501"])
  end

  it "does not accept conditional calls as schema migration configuration" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        def self.visible?(_context) = true
      end

      class AppSchema < GraphQL::Schema
        use GraphQL::Schema::Visibility if enabled
        complexity_cost_calculation_mode :legacy if enabled
      end
    RUBY
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    visibility, visibility_rewriter = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, code, config: config)
    complexity, = run_rule(GraphQL::Modernize::Rules::ComplexityCostMode, code, config: config)

    expect(visibility.map(&:rule_id)).to eq(["GQLM307"])
    expect(visibility.map(&:safety)).to eq([:manual])
    expect(visibility_rewriter.rewrite).to eq(code)
    expect(complexity.map(&:rule_id)).to eq(["GQLM501"])

    warden = code.sub("GraphQL::Schema::Visibility", "GraphQL::Schema::Warden")
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, warden, config: config)
    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite).to eq(warden)
  end

  it "moves existing Visibility after root types without changing conditional setup" do
    config = GraphQL::Modernize::Config.new(apply_unsafe: true)
    before = <<~RUBY
      class AppSchema < GraphQL::Schema
        use GraphQL::Schema::Visibility, preload: true
        query Types::Query
      end
    RUBY
    after = <<~RUBY
      class AppSchema < GraphQL::Schema
        query Types::Query
        use GraphQL::Schema::Visibility, preload: true
      end
    RUBY
    expect_correction(GraphQL::Modernize::Rules::VisibilityPlugin, before, after, config: config)

    conditional = <<~RUBY
      class AppSchema < GraphQL::Schema
        use GraphQL::Schema::Visibility if enabled
        query Types::Query
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, conditional, config: config)
    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite).to eq(conditional)

    commented = before.sub("preload: true", "preload: true # keep")
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::VisibilityPlugin, commented, config: config)
    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite).to eq(commented)
  end

  it "removes each obsolete pagination setting" do
    code = <<~RUBY
      GraphQL::Relay::ConnectionType.bidirectional_pagination = true
      GraphQL::Relay::ConnectionType.default_nodes_field = false
    RUBY
    first, first_rewriter = run_rule(GraphQL::Modernize::Rules::BidirectionalPagination, code)
    second, second_rewriter = run_rule(GraphQL::Modernize::Rules::DefaultNodesField, first_rewriter.rewrite)

    expect(first.map(&:rule_id)).to eq(["GQLM305"])
    expect(second.map(&:rule_id)).to eq(["GQLM306"])
    expect(second_rewriter.rewrite).to eq("")

    root_qualified = "::GraphQL::Relay::ConnectionType.default_nodes_field = true\n"
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::DefaultNodesField, root_qualified)
    expect(offenses.map(&:rule_id)).to eq(["GQLM306"])
    expect(rewriter.rewrite).to eq("")
  end

  it "does not break a conditional pagination setting" do
    code = <<~RUBY
      GraphQL::Relay::ConnectionType.bidirectional_pagination = true if enabled
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::BidirectionalPagination, code)

    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite(validate: :parse)).to eq(code)
  end

  it "preserves pagination assignment results in nested expressions" do
    code = <<~RUBY
      class Configuration
        def self.apply
          GraphQL::Relay::ConnectionType.bidirectional_pagination = true
        end

        CALLBACK = lambda do
          GraphQL::Relay::ConnectionType.default_nodes_field = false
        end
      end

      RESULT = (
        GraphQL::Relay::ConnectionType.bidirectional_pagination = true
      )
    RUBY

    [GraphQL::Modernize::Rules::BidirectionalPagination,
     GraphQL::Modernize::Rules::DefaultNodesField].each do |rule|
      offenses, rewriter = run_rule(rule, code)
      expect(offenses).not_to be_empty
      expect(offenses.map(&:safety).uniq).to eq([:manual])
      expect(rewriter.rewrite(validate: :parse)).to eq(code)
    end
  end

  it "preserves pagination settings with trailing comments" do
    code = "GraphQL::Relay::ConnectionType.default_nodes_field = false # keep rationale\n"
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::DefaultNodesField, code)

    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite(validate: :parse)).to eq(code)
  end

  it "does not remove a pagination setting whose value may have side effects" do
    code = <<~RUBY
      GraphQL::Relay::ConnectionType.bidirectional_pagination = compute_setting!
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::BidirectionalPagination, code)

    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite(validate: :parse)).to eq(code)
  end

  it "does not remove same-named application setters" do
    code = <<~RUBY
      class AppSchema < GraphQL::Schema
        self.bidirectional_pagination = true
        self.default_nodes_field = false
      end
      GraphQL::CustomConnection.bidirectional_pagination = true
    RUBY

    [GraphQL::Modernize::Rules::BidirectionalPagination,
     GraphQL::Modernize::Rules::DefaultNodesField].each do |rule|
      offenses, rewriter = run_rule(rule, code)
      expect(offenses).to be_empty
      expect(rewriter.rewrite).to eq(code)
    end
  end

  it "recognizes method-based schema migration configurations" do
    code = <<~RUBY
      class AppSchema < GraphQL::Schema
        class << self
          def legacy_invalid_empty_selections_on_union_with_type(query, type) = nil
        end

        def self.complexity_cost_calculation_mode_for(context) = :future
      end
    RUBY
    empty_union, = run_rule(GraphQL::Modernize::Rules::EmptyUnionSelections, code)
    complexity, = run_rule(GraphQL::Modernize::Rules::ComplexityCostMode, code)

    expect(empty_union).to be_empty
    expect(complexity).to be_empty
  end

  it "only reports type index access on known schemas" do
    code = <<~RUBY
      class AppSchema < GraphQL::Schema
      end
      AppSchema.possible_types
      FakeSchema.references_to
    RUBY
    offenses, = run_rule(GraphQL::Modernize::Rules::TypeIndexKeys, code)

    expect(offenses.map(&:message)).to contain_exactly(/Return keys/)
    expect(offenses.first.location.slice).to eq("AppSchema.possible_types")
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
