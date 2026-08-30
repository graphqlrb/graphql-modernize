# frozen_string_literal: true

module GraphQL
  module Modernize
    module Rules
      class TestProperty < Base
        rule id: "GQLM999", safety: :safe, summary: "test"
        node_pattern :call_node, "(call_node receiver: nil name: :field)"

        def on_match(node, _captures)
          return unless inside?(node, :object)

          argument = rewriter.find_keyword_argument(node, :property)
          return unless argument

          add_offense(argument.key.location, message: "replace property") do |rw|
            rw.replace_keyword_key(argument, :method)
          end
        end
      end
    end
  end
end

RSpec.describe GraphQL::Modernize::Runner do
  it "collects offenses and applies each correction transactionally" do
    source = Astel::SourceFile.from_string(<<~RUBY, path: "type.rb")
      class Types::UserType < Types::BaseObject
        field :name, String, property: :full_name
      end
    RUBY
    hierarchy = GraphQL::Modernize::ClassHierarchy.new.build([source])
    offenses, rewriter = described_class.new(hierarchy: hierarchy).run(
      source,
      [GraphQL::Modernize::Rules::TestProperty]
    )

    expect(offenses.map(&:rule_id)).to eq(["GQLM999"])
    expect(offenses.first).to be_corrected
    expect(rewriter.rewrite(validate: :parse)).to include("method: :full_name")
  end

  it "does not rewrite receiver calls or non-GraphQL classes" do
    source = Astel::SourceFile.from_string(<<~RUBY, path: "form.rb")
      class Form
        field :name, String, property: :full_name
        object.field :name, String, property: :full_name
      end
    RUBY
    hierarchy = GraphQL::Modernize::ClassHierarchy.new.build([source])
    offenses, = described_class.new(hierarchy: hierarchy).run(source, [GraphQL::Modernize::Rules::TestProperty])

    expect(offenses).to be_empty
  end

  it "reports the rule responsible for a conflicting edit" do
    source = Astel::SourceFile.from_string(<<~RUBY, path: "type.rb")
      class Types::UserType < Types::BaseObject
        field :name, String, property: :full_name
      end
    RUBY
    hierarchy = GraphQL::Modernize::ClassHierarchy.new.build([source])
    offenses, = described_class.new(hierarchy: hierarchy).run(
      source,
      [GraphQL::Modernize::Rules::PropertyOption, GraphQL::Modernize::Rules::TestProperty]
    )

    expect(offenses.last.corrected?).to be(false)
    expect(offenses.last.conflicting_rule_id).to eq("GQLM106")
  end
end
