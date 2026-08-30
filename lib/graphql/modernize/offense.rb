# frozen_string_literal: true

module GraphQL
  module Modernize
    class Offense
      attr_reader :rule_id, :location, :message, :safety, :path
      attr_accessor :corrected

      def initialize(rule_id:, location:, message:, safety:, path:, correctable:)
        @rule_id = rule_id
        @location = location
        @message = message
        @safety = safety
        @path = path
        @correctable = correctable
        @corrected = false
      end

      def correctable?
        @correctable
      end

      def corrected?
        corrected
      end
    end
  end
end
