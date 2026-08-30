# frozen_string_literal: true

require_relative "modernize/version"
require "astel"
require "astel/refactor"
require "astel/diff"

module GraphQL
  module Modernize
    class Error < StandardError; end
  end
end

require_relative "modernize/config"
require_relative "modernize/file_finder"
require_relative "modernize/class_hierarchy"
require_relative "modernize/context_builder"
require_relative "modernize/offense"
require_relative "modernize/rule_registry"
require_relative "modernize/rules/base"
require_relative "modernize/runner"
require_relative "modernize/rules/legacy"
require_relative "modernize/rules/relay"
require_relative "modernize/rules/deprecation"
