# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe GraphQL::Modernize::CLI do
  def invoke(*arguments)
    out = StringIO.new
    err = StringIO.new
    status = described_class.start(arguments, out: out, err: err)
    [status, out.string, err.string]
  end

  it "runs a dry-run and emits machine-readable output" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app/graphql"))
      path = File.join(root, "app/graphql/type.rb")
      File.write(path, "class Type < Types::BaseObject\n  field :name, String, property: :name\nend\n")

      Dir.chdir(root) do
        status, output, error = invoke("run", "--only", "GQLM106", "--format", "json", "--jobs", "1")
        parsed = JSON.parse(output)

        expect(status).to eq(0)
        expect(error).to be_empty
        expect(parsed.fetch("offenses").first.fetch("rule_id")).to eq("GQLM106")
        expect(File.read(path)).to include("property: :name")
      end
    end
  end

  it "writes with an explicit safety override" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.write(path, "class Type < Types::BaseObject\n  field :name, String, property: :name\nend\n")

      Dir.chdir(root) do
        status, = invoke("run", path, "--only", "GQLM106", "--write", "--force", "--no-diff", "--jobs", "1")
        expect(status).to eq(0)
        expect(File.read(path)).to include("method: :name")
      end
    end
  end

  it "lists and explains registered rules" do
    expect(invoke("list")[1]).to include("GQLM106")
    Dir.mktmpdir do |root|
      Dir.chdir(root) do
        explanation = invoke("explain", "GQLM106")[1]
        expect(explanation).to include("safety: safe", "# GQLM106")
      end
    end
  end

  it "returns exit 2 for invalid worker counts and output paths" do
    expect(invoke("run", "--jobs", "0").then { |status, _out, error| [status, error] })
      .to match([2, /jobs/])
    expect(invoke("run", "--out", "/missing/directory/result.json").first).to eq(2)
    expect(invoke("run", "--except", "GQLM9999").first).to eq(2)
  end

  it "never overwrites a source file with reporter output" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      source = "class Type < Types::BaseObject\n  field :name, String, property: :name\nend\n"
      File.write(path, source)

      Dir.chdir(root) do
        status, _output, error = invoke("run", path, "--only", "GQLM106", "--write", "--force",
                                        "--out", path, "--jobs", "1")
        expect(status).to eq(2)
        expect(error).to include("--out")
        expect(File.read(path)).to eq(source)
      end
    end
  end

  it "runs a default-disabled rule when explicitly selected" do
    Dir.mktmpdir do |root|
      path = File.join(root, "type.rb")
      File.write(path, <<~RUBY)
        class Type < Types::BaseObject
          argument :id, ID, required: true
        end
      RUBY

      Dir.chdir(root) do
        status, output, = invoke("run", path, "--only", "GQLM401", "--jobs", "1", "--no-diff")
        expect(status).to eq(0)
        expect(output).to include("GQLM401")
      end
    end
  end

  it "warns about parse errors in diff-oriented formats" do
    Dir.mktmpdir do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "class Broken <\n")

      status, _output, error = invoke("run", path, "--format", "github", "--strict", "--jobs", "1")
      expect(status).to eq(2)
      expect(error).to include("parse error")
    end
  end
end
