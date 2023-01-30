# frozen_string_literal: true

module ArelExtensions
  module Nodes
    # Right-hand side of `col =~ /regex/` / `col !~ /regex/` when the pattern is
    # a *Ruby* Regexp.
    #
    # The point of wrapping it (instead of quoting the source right away in the
    # comparator) is that the regex dialect depends on the target database, and
    # only the visitor knows which database it is generating SQL for .
    #
    # A plain String pattern is NOT wrapped in this node: it is assumed to be
    # written in the target engine's own dialect and is passed through verbatim.
    class RegexpLiteral < Arel::Nodes::Node
      attr_reader :source

      def initialize(regexp)
        super()
        @source = regexp.is_a?(::Regexp) ? regexp.source : regexp.to_s
      end

      # Fallback for the visitors that still string-interpolate the pattern.
      def to_s
        @source
      end
    end
  end
end
