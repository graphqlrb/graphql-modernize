# frozen_string_literal: true

RSpec.describe GraphQL::Modernize::ClassHierarchy do
  def source(code, path: "types.rb")
    Astel::SourceFile.from_string(code, path: path)
  end

  it "resolves direct, indirect, compact, nested, interface, and configured classes" do
    types = source(<<~RUBY)
      module Types
        class BaseObject < GraphQL::Schema::Object
        end

        class UserType < BaseObject
          class Metadata < GraphQL::Schema::Object
          end
        end

        module Named
          include GraphQL::Schema::Interface
        end
      end

      class Types::Input < Types::BaseInputObject
      end

      class ExternalType < ApplicationObjectType
      end
    RUBY
    hierarchy = described_class.new(base_classes: { object: ["ApplicationObjectType"] }).build([types])

    expect(hierarchy.resolve_kind("Types::BaseObject")).to eq(:object)
    expect(hierarchy.resolve_kind("Types::UserType")).to eq(:object)
    expect(hierarchy.resolve_kind("Types::UserType::Metadata")).to eq(:object)
    expect(hierarchy.resolve_kind("Types::Input")).to eq(:input_object)
    expect(hierarchy.resolve_kind("Types::Named")).to eq(:interface)
    expect(hierarchy.resolve_kind("ExternalType")).to eq(:object)
    expect(hierarchy.resolve_kind("Unknown")).to be_nil
  end
end
