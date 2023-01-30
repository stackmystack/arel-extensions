# frozen_string_literal: true

module ArelExtensions
  module Comparators
    def >(other)
      Arel::Nodes::GreaterThan.new self, Arel.quoted(other, self)
    end

    def >=(other)
      Arel::Nodes::GreaterThanOrEqual.new self, Arel.quoted(other, self)
    end

    def <(other)
      Arel::Nodes::LessThan.new self, Arel.quoted(other, self)
    end

    def <=(other)
      Arel::Nodes::LessThanOrEqual.new self, Arel.quoted(other, self)
    end

    # REGEXP function
    # Pattern matching using regular expressions
    def =~(other)
      Arel::Nodes::Regexp.new self, regexp_operand(other)
    end

    alias regex_matches =~

    # NOT_REGEXP function
    # Negation of Regexp
    def !~(other)
      Arel::Nodes::NotRegexp.new self, regexp_operand(other)
    end

    private

    # A String pattern is quoted as-is: it is taken to be already written in
    # the target database's regex dialect. A Ruby Regexp is wrapped so the
    # visitor can adapt its syntax to the database it targets (see
    # ArelExtensions::Nodes::RegexpLiteral).
    def regexp_operand(other)
      case other
      when ::Regexp then ArelExtensions::Nodes::RegexpLiteral.new(other)
      else Arel.quoted(other, self)
      end
    end
  end
end
