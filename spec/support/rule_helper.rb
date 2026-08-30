# frozen_string_literal: true

module RuleHelper
  def run_rule(rule_class, code, config: GraphQL::Modernize::Config.new)
    source = Astel::SourceFile.from_string(code, path: "example.rb")
    hierarchy = GraphQL::Modernize::ClassHierarchy.new(base_classes: config.base_classes).build([source])
    GraphQL::Modernize::Runner.new(hierarchy: hierarchy, config: config).run(source, [rule_class])
  end

  def expect_correction(rule_class, before, after, config: GraphQL::Modernize::Config.new)
    offenses, rewriter = run_rule(rule_class, before, config: config)
    corrected = rewriter.rewrite(validate: :parse)

    expect(offenses).not_to be_empty
    expect(corrected).to eq(after)
    expect(run_rule(rule_class, corrected, config: config).last.rewrite(validate: :parse)).to eq(after)
  end
end

RSpec.configure { |config| config.include RuleHelper }
