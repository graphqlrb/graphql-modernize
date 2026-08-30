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

  it "resolves custom base suffixes and inherits schema metadata" do
    types = source(<<~RUBY)
      class DatabaseObject
      end

      class ApplicationBaseObject
      end

      class BaseSchema < GraphQL::Schema
        use GraphQL::Schema::Visibility
        def inherited_resolver = true
      end

      class AppSchema < BaseSchema
        def helper
          use GraphQL::Schema::Warden
        end
      end
    RUBY
    hierarchy = described_class.new.build([types])

    expect(hierarchy.resolve_kind("DatabaseObject")).to be_nil
    expect(hierarchy.resolve_kind("ApplicationBaseObject")).to eq(:object)
    expect(hierarchy.visibility_plugin?("AppSchema")).to be(true)
    expect(hierarchy.method_defined?("AppSchema", :inherited_resolver)).to be(true)
    expect(hierarchy.class_method_defined?("AppSchema", :inherited_resolver)).to be(false)
  end

  it "does not treat DSL-shaped calls inside methods as schema configuration" do
    types = source(<<~RUBY)
      class AppSchema < GraphQL::Schema
        def helper
          use GraphQL::Schema::Visibility
        end

        def other.complexity_cost_calculation_mode_for(context) = :future
      end
    RUBY
    hierarchy = described_class.new.build([types])

    expect(hierarchy.visibility_plugin?("AppSchema")).to be(false)
    expect(hierarchy.class_method_defined?("AppSchema", :complexity_cost_calculation_mode_for)).to be(false)
  end

  it "selects only the highest project schema for Visibility insertion" do
    types = source(<<~RUBY)
      class BaseSchema < GraphQL::Schema
      end

      class AppSchema < BaseSchema
      end
    RUBY
    hierarchy = described_class.new.build([types])

    expect(hierarchy.visibility_plugin_target?("BaseSchema")).to be(true)
    expect(hierarchy.visibility_plugin_target?("AppSchema")).to be(false)
  end
end
