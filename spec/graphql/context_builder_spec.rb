# frozen_string_literal: true

RSpec.describe GraphQL::Modernize::ContextBuilder do
  it "returns the innermost class context only within its byte range" do
    code = <<~RUBY
      outside
      class Types::UserType < Types::BaseObject
        field :name, String
        class Nested < GraphQL::Schema::InputObject
          argument :name, String
        end
      end
      outside
    RUBY
    source = Astel::SourceFile.from_string(code, path: "types.rb")
    hierarchy = GraphQL::Modernize::ClassHierarchy.new.build([source])
    context = described_class.new(source, hierarchy)

    expect(context.context_at(code.index("field"))&.class_name).to eq("Types::UserType")
    expect(context.context_at(code.index("argument"))&.class_name).to eq("Types::UserType::Nested")
    expect(context.context_at(code.index("outside"))).to be_nil
    expect(context.context_at(code.rindex("outside"))).to be_nil
  end
end
