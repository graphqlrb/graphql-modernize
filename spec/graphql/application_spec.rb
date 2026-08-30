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
end
