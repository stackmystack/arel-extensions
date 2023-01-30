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


      # A map value of `nil` (as opposed to a key simply being absent) means
      # "this Ruby escape is known to have no safe equivalent here".
      #
      # Raises rather than passing the token through untranslated.
      def translate(map, in_class_map = {})
        scanner = StringScanner.new(source)
        res = +''
        in_class = false

        while !scanner.eos?
          if scanner.scan(/\\./m)
            token = scanner.matched
            active_map = in_class ? in_class_map : map
            if active_map.key?(token) && active_map[token].nil?
              raise ArgumentError, "#{token} has no equivalent#{' inside a character class' if in_class} " \
                                    "in this database's regex dialect: #{source.inspect}"
            end

            res << active_map.fetch(token, token)
          elsif !in_class && scanner.scan(%r{ \[ \^? \]? }x)
            in_class = true
            res << scanner.matched
          elsif in_class && scanner.scan(/\]/)
            in_class = false
            res << scanner.matched
          else
            # Eat everything up to the next backslash escape or class boundary in one shot.
            res << (scanner.scan(in_class ? /[^\\\]]+/ : /[^\\\[]+/) || scanner.getch)
          end
        end

        res
      end

    end
  end
end
