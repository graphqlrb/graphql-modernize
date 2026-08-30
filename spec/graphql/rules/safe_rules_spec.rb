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

  it "renames property without changing formatting" do
    expect_correction(
      GraphQL::Modernize::Rules::PropertyOption,
      "class UserType < Types::BaseObject\n  field :name, String, property: :full_name\nend\n",
      "class UserType < Types::BaseObject\n  field :name, String, method: :full_name\nend\n"
    )
  end

  it "removes field and function options together" do
    expect_correction(
      GraphQL::Modernize::Rules::RemovedFieldOptions,
      "class UserType < Types::BaseObject\n  field :name, String, field: OLD, function: FN, null: false\nend\n",
      "class UserType < Types::BaseObject\n  field :name, String, null: false\nend\n"
    )
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
