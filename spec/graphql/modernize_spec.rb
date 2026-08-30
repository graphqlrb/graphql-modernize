# frozen_string_literal: true

RSpec.describe GraphQL::Modernize do
  it "has a version number" do
    expect(GraphQL::Modernize::VERSION).not_to be nil
  end

  it "ships documentation for every registered production rule" do
    rules = GraphQL::Modernize::RuleRegistry.all.reject { |rule| rule.metadata.id.start_with?("GQLM99") }
    missing = rules.filter_map do |rule|
      path = rule.metadata.docs
      rule.metadata.id unless path && File.file?(File.expand_path("../../#{path}", __dir__))
    end

    expect(missing).to be_empty
  end
end
