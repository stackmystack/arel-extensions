require 'date'

module ArelExtensions
  module Nodes
    class DateDiff < Function #difference entre colonne date et date string/date
      attr_accessor :date_type

      def initialize(expr)
        col = expr.first
        case col
        when Arel::Nodes::Node
          @date_type = Arel::Table.engine.connection.schema_cache.columns_hash(col.relation.table_name)[col.name.to_s].type
        when Date
          @date_type = :date
        when DateTime, Time
          @date_type = :datetime
        end
        super [convert_to_date_node(col), convert_to_date_node(expr[1])]
      end
    end

    class DateAdd < Function
      attr_accessor :date_type

      def initialize expr
        col = expr.first
        @date_type = Arel::Table.engine.connection.schema_cache.columns_hash(col.relation.table_name)[col.name.to_s].type
        tab = expr.map do |arg|
          convert(arg)
        end
        return super(tab)
      end

      def sqlite_value
        v = self.expressions.last
        if defined?(ActiveSupport::Duration) && ActiveSupport::Duration === v
          if @date_type == :date
            return Arel::Nodes.build_quoted((v.value >= 0 ? '+' : '-') + v.inspect)
          elsif @date_type == :datetime
            return Arel::Nodes.build_quoted((v.value >= 0 ? '+' : '-') + v.inspect)
          end
        else
          return v
        end
      end

      def mysql_value(v = nil)
        v ||= self.expressions.last
        if defined?(ActiveSupport::Duration) && ActiveSupport::Duration === v
          if @date_type == :date
            Arel.sql((v.value >= 0 ? 'INTERVAL ' : 'INTERVAL -') + v.inspect.sub(/s\Z/, ''))
          elsif @date_type == :datetime
            Arel.sql((v.value >= 0 ? 'INTERVAL ' : 'INTERVAL -') + v.inspect.sub(/s\Z/, ''))
          end
        else
          v
        end
      end

      def postgresql_value(v = nil)
        v ||= self.expressions.last
        if defined?(ActiveSupport::Duration) && ActiveSupport::Duration === v
          if @date_type == :date
            Arel.sql("INTERVAL '%s'"  + v.inspect.sub(/s\Z/, '').upcase)
          elsif @date_type == :datetime
            Arel.sql("INTERVAL '%s'"  + v.inspect.sub(/s\Z/, '').upcase)
          end
        else
          return v
        end
      end

      private
      def convert(object)
        case object
        when Arel::Attributes::Attribute, Arel::Nodes::Node, ActiveSupport::Duration
          object
        when Fixnum, Integer
          object.days
        when DateTime, Time, Date
          raise(ArgumentError, "#{object.class} can not be converted to Fixnum")
        when String
          Arel::Nodes.build_quoted(object)
        else
          raise(ArgumentError, "#{object.class} can not be converted to Fixnum")
        end
      end
    end

    class DateSub < Arel::Nodes::Node #difference entre colonne date et date string/date
      include Arel::Predications
      include Arel::WindowPredications
      include Arel::OrderPredications
      include Arel::AliasPredication

      attr_accessor :left, :right

      def initialize(left, right, aliaz = nil)
        super()
        @left = left
        @right = convert_number(right)
      end

      def convert_number(object)
        case object
        when Arel::Attributes::Attribute, Arel::Nodes::Node, Fixnum, Integer
          object
        when String
          object.to_i
        else
          raise(ArgumentError, "#{object.class} can not be converted to Number")
        end
      end

    end

  end
end