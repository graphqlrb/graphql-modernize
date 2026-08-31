# frozen_string_literal: true

RSpec.describe "safe migration rules" do
  it "rewrites types shortcuts" do
    expect_correction(
      GraphQL::Modernize::Rules::TypesShortcut,
      "class UserType < Types::BaseObject\n  field :age, types.Int\nend\n",
      "class UserType < Types::BaseObject\n  field :age, Integer\nend\n"
    )
  end

  it "maps every legacy scalar without inventing constants" do
    before = <<~RUBY
      class UserType < Types::BaseObject
        field :name, types.String
        field :score, types.Float
        field :enabled, types.Boolean
        field :id, types.ID
        field :custom, types.Custom
      end
    RUBY
    after = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String
        field :score, Float
        field :enabled, GraphQL::Types::Boolean
        field :id, GraphQL::Types::ID
        field :custom, types.Custom
      end
    RUBY

    expect_correction(GraphQL::Modernize::Rules::TypesShortcut, before, after)
  end

  it "does not discard arguments or blocks from types shortcuts" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :one, types.Int(side_effect!)
        field :two, types.Int { side_effect! }
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::TypesShortcut, code)

    expect(offenses).to be_empty
    expect(rewriter.rewrite).to eq(code)
  end

  it "does not break chained legacy type wrappers" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, types.String.to_non_null_type
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::TypesShortcut, code)

    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite).to eq(code)
  end

  it "only rewrites legacy scalars in type DSL arguments" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, types.String
        field :tags, [types.String]
        argument :id, types.ID
        type types.Boolean
        field :scores, types[types.Int]
        audit(types.String)
        LEGACY_TYPE = types.Int
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::TypesShortcut, code)
    rewritten = rewriter.rewrite(validate: :parse)

    expect(offenses.map(&:safety)).to eq(%i[safe safe safe safe safe manual manual])
    expect(rewritten).to include("field :name, String", "field :tags, [String]", "argument :id, GraphQL::Types::ID",
                                 "type GraphQL::Types::Boolean", "types[Integer]")
    expect(rewritten).to include("audit(types.String)", "LEGACY_TYPE = types.Int")
  end

  it "renames property without changing formatting" do
    expect_correction(
      GraphQL::Modernize::Rules::PropertyOption,
      "class UserType < Types::BaseObject\n  field :name, String, property: :full_name\nend\n",
      "class UserType < Types::BaseObject\n  field :name, String, method: :full_name\nend\n"
    )
  end

  it "does not create duplicate method keywords" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String, property: :legacy, method: :current
        field :other, String, property: :first, property: :second
        field :dynamic, String, **options, property: :legacy
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::PropertyOption, code)

    expect(offenses.map(&:safety)).to eq(%i[manual manual manual])
    expect(rewriter.rewrite).to eq(code)
  end

  it "removes field and function options together" do
    expect_correction(
      GraphQL::Modernize::Rules::RemovedFieldOptions,
      "class UserType < Types::BaseObject\n  field :name, String, field: nil, function: false\nend\n",
      "class UserType < Types::BaseObject\n  field :name, String\nend\n"
    )
    expect_correction(
      GraphQL::Modernize::Rules::RemovedFieldOptions,
      "class UserType < Types::BaseObject\n  field(:name, String, field: nil, function: false)\nend\n",
      "class UserType < Types::BaseObject\n  field(:name, String)\nend\n"
    )
  end

  it "does not discard constant evaluation or string-keyed hashes" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :one, String, field: LEGACY
        field :two, String, "field" => 1
        field :three, String, **options, field: nil
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::RemovedFieldOptions, code)

    expect(offenses.map(&:safety)).to eq(%i[manual manual])
    expect(rewriter.rewrite).to eq(code)
  end

  it "does not remove explicit defaults beside dynamic keyword options" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String, **field_options, null: true
        field :other, String, null: true, null: false
        argument :id, ID, **argument_options, required: true
        argument :other, ID, required: true, required: false
      end
    RUBY
    config = GraphQL::Modernize::Config.new(
      rules: {
        "GQLM401" => { "enabled" => true },
        "GQLM402" => { "enabled" => true }
      }
    )

    [GraphQL::Modernize::Rules::RedundantRequiredTrue,
     GraphQL::Modernize::Rules::RedundantNullTrue].each do |rule|
      offenses, rewriter = run_rule(rule, code, config: config)
      expect(offenses.map(&:safety)).to eq(%i[manual manual])
      expect(rewriter.rewrite).to eq(code)
    end
  end

  it "does not rewrite DSL-shaped calls inside executable scopes" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        def helper
          field :name, String, property: :name
        end

        HANDLER = -> { field :other, String, property: :other }
        OTHER_HANDLER = proc { field :third, String, property: :third }
      end

      class AppSchema < GraphQL::Schema
        def helper
          error_bubbling(true)
        end
      end
    RUBY

    [GraphQL::Modernize::Rules::PropertyOption, GraphQL::Modernize::Rules::ErrorBubbling].each do |rule|
      offenses, rewriter = run_rule(rule, code)
      expect(offenses).to be_empty
      expect(rewriter.rewrite).to eq(code)
    end
  end

  it "still rewrites declarations inside field blocks" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :search do
          argument :query, String, required: true
        end
      end
    RUBY
    config = GraphQL::Modernize::Config.new(rules: { "GQLM401" => { "enabled" => true } })
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::RedundantRequiredTrue, code, config: config)

    expect(offenses.map(&:rule_id)).to eq(["GQLM401"])
    expect(rewriter.rewrite(validate: :parse)).not_to include("required: true")
  end

  it "renames the load application object error constant" do
    expect_correction(
      GraphQL::Modernize::Rules::LoadApplicationObjectFailedError,
      "begin\nrescue GraphQL::Schema::Resolver::LoadApplicationObjectFailedError\nend\n",
      "begin\nrescue GraphQL::LoadApplicationObjectFailedError\nend\n"
    )
    expect_correction(
      GraphQL::Modernize::Rules::LoadApplicationObjectFailedError,
      "begin\nrescue ::GraphQL::Schema::Resolver::LoadApplicationObjectFailedError\nend\n",
      "begin\nrescue ::GraphQL::LoadApplicationObjectFailedError\nend\n"
    )
  end

  {
    GraphQL::Modernize::Rules::InterpreterPlugin => "GraphQL::Execution::Interpreter",
    GraphQL::Modernize::Rules::AnalysisAstPlugin => "GraphQL::Analysis::AST",
    GraphQL::Modernize::Rules::ConnectionsPlugin => "GraphQL::Pagination::Connections"
  }.each do |rule, plugin|
    it "removes #{plugin}" do
      expect_correction(
        rule,
        "class AppSchema < GraphQL::Schema\n  use #{plugin}\n  query Types::Query\nend\n",
        "class AppSchema < GraphQL::Schema\n  query Types::Query\nend\n"
      )
      expect_correction(
        rule,
        "class AppSchema < ::GraphQL::Schema\n  use ::#{plugin}\nend\n",
        "class AppSchema < ::GraphQL::Schema\nend\n"
      )
    end

    it "does not break a conditional #{plugin} call" do
      code = "class AppSchema < GraphQL::Schema\n  use #{plugin} if enabled\nend\n"
      offenses, rewriter = run_rule(rule, code)

      expect(offenses.map(&:safety)).to eq([:manual])
      expect(rewriter.rewrite(validate: :parse)).to eq(code)
    end

    it "does not remove a #{plugin} call with a block" do
      code = <<~RUBY
        class AppSchema < GraphQL::Schema
          use #{plugin} do
            side_effect!
          end
        end
      RUBY
      offenses, rewriter = run_rule(rule, code)

      expect(offenses.map(&:safety)).to eq([:manual])
      expect(rewriter.rewrite(validate: :parse)).to eq(code)
    end

    it "does not silently ignore options on #{plugin}" do
      code = "class AppSchema < GraphQL::Schema\n  use #{plugin}, custom: setup_plugin\nend\n"
      offenses, rewriter = run_rule(rule, code)

      expect(offenses.map(&:safety)).to eq([:manual])
      expect(rewriter.rewrite(validate: :parse)).to eq(code)
    end

    it "preserves a trailing comment on #{plugin}" do
      code = "class AppSchema < GraphQL::Schema\n  use #{plugin} # keep rationale\nend\n"
      offenses, rewriter = run_rule(rule, code)

      expect(offenses.map(&:safety)).to eq([:manual])
      expect(rewriter.rewrite(validate: :parse)).to eq(code)
    end
  end

  it "does not discard side effects in removed field options" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :name, String, function: build_function!
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::RemovedFieldOptions, code)

    expect(offenses.map(&:safety)).to eq([:manual])
    expect(rewriter.rewrite(validate: :parse)).to eq(code)
  end

  it "does not rewrite graphql-ruby's framework base classes" do
    code = <<~RUBY
      module GraphQL
        class Schema
          use GraphQL::Pagination::Connections
        end
      end
    RUBY
    offenses, rewriter = run_rule(GraphQL::Modernize::Rules::ConnectionsPlugin, code)

    expect(offenses).to be_empty
    expect(rewriter.rewrite).to eq(code)
  end

  it "does not match unrelated DSLs, receivers, strings, comments, or heredocs" do
    code = <<~RUBY
      class Form
        field :name, types.String, property: :x
      end
      object.field :name, String, property: :x
      "field :name, types.String, property: :x"
      # field :name, types.String, property: :x
      <<~TEXT
        field :name, types.String, property: :x
      TEXT
    RUBY

    [
      GraphQL::Modernize::Rules::TypesShortcut,
      GraphQL::Modernize::Rules::PropertyOption,
      GraphQL::Modernize::Rules::RemovedFieldOptions
    ].each do |rule|
      offenses, rewriter = run_rule(rule, code)
      expect(offenses).to be_empty
      expect(rewriter.rewrite).to eq(code)
    end
  end
end
