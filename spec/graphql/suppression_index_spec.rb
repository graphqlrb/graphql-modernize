# frozen_string_literal: true

RSpec.describe GraphQL::Modernize::SuppressionIndex do
  let(:rule) { GraphQL::Modernize::Rules::PropertyOption }

  it "suppresses inline and range offenses" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :one, String, property: :one # graphql-modernize:disable GQLM106
        # graphql-modernize:disable GQLM106
        field :two, String, property: :two
        # graphql-modernize:enable GQLM106
        field :three, String, property: :three
      end
    RUBY
    offenses, rewriter = run_rule(rule, code)

    expect(offenses.map(&:rule_id)).to eq(["GQLM106"])
    expect(rewriter.rewrite).to include("property: :one", "property: :two", "method: :three")
  end

  it "requires a reason when configured and reports unused directives" do
    config = GraphQL::Modernize::Config.new(require_suppression_reason: true)
    code = <<~RUBY
      # graphql-modernize:disable-file GQLM106
      class UserType < Types::BaseObject
        field :name, String, property: :name
      end
      # graphql-modernize:disable GQLM105 -- no matching offense
    RUBY
    offenses, rewriter = run_rule(rule, code, config: config)

    expect(offenses.map(&:rule_id)).to contain_exactly("GQLM106", "GQLM000")
    expect(rewriter.rewrite).to include("method: :name")
  end

  it "keeps inline suppression on its own line" do
    code = <<~RUBY
      class UserType < Types::BaseObject
        field :one, String, property: :one # graphql-modernize:disable GQLM106
        field :two, String, property: :two
      end
    RUBY
    offenses, rewriter = run_rule(rule, code)

    expect(offenses.map(&:rule_id)).to eq(["GQLM106"])
    expect(rewriter.rewrite).to include("property: :one", "method: :two")
  end

  it "rejects an empty required reason" do
    config = GraphQL::Modernize::Config.new(require_suppression_reason: true)
    code = <<~RUBY
      # graphql-modernize:disable-file GQLM106 --
      class UserType < Types::BaseObject
        field :name, String, property: :name
      end
    RUBY
    offenses, rewriter = run_rule(rule, code, config: config)

    expect(offenses.map(&:rule_id)).to eq(["GQLM106"])
    expect(rewriter.rewrite).to include("method: :name")
  end
end
