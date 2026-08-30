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
    expect(invoke("explain", "GQLM106")[1]).to include("safety: safe")
  end
end
