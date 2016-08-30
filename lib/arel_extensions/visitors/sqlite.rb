module ArelExtensions
  module Visitors
    Arel::Visitors::SQLite.class_eval do

      # Date operations
      def visit_ArelExtensions_Nodes_DateAdd o, collector
        collector << "date("
        collector = visit o.expressions.first, collector
        collector << Arel::Visitors::ToSql::COMMA
        collector = visit o.sqlite_value, collector
        collector << ")"
        collector
      end

      def visit_ArelExtensions_Nodes_DateDiff o, collector
        collector << " julianday("
        collector = visit o.left, collector
        collector << ")- julianday("
        collector = visit o.right, collector
        collector << ")"
        collector
      end

      def visit_ArelExtensions_Nodes_Duration o, collector
        #visit left for period
        if(o.left == "d")
          collector << "strftime('%d',"
        elsif(o.left == "m")
          collector << "strftime('%m',"
        elsif (o.left == "w")
          collector << "strftime('%W',"
        elsif (o.left == "y")
          collector << "strftime('%Y',"
        end
        #visit right
        if(o.right.is_a?(Arel::Attributes::Attribute))
          collector = visit o.right, collector
        else
          collector << "#{o.right}"
        end
        collector << ")"
        collector
      end


      def visit_ArelExtensions_Nodes_Locate o, collector
        collector << "instr("
        collector = visit o.expr, collector
        collector << ","
        if(o.val.is_a?(Arel::Attributes::Attribute))
          collector = visit o.val, collector
        else
          collector << "'#{o.val}'"
        end
        collector << ")"
        collector
      end

      def visit_ArelExtensions_Nodes_Isnull o, collector
        collector << "ifnull("
        collector = visit o.left, collector
        collector << ","
        if(o.right.is_a?(Arel::Attributes::Attribute))
          collector = visit o.right, collector
        else
          collector << "'#{o.right}'"
        end
        collector << ")"
        collector
      end

      def visit_ArelExtensions_Nodes_Rand o, collector
        collector << "RANDOM("
        if(o.left != nil && o.right != nil)
          if(o.left.is_a?(Arel::Attributes::Attribute))
            collector = visit o.left, collector
          else
            collector << "'#{o.left}'"
          end
          collector << ","
          collector << "'#{o.right}'"
        end
        collector << ")"
        collector
      end


      def visit_ArelExtensions_Nodes_Replace o, collector
        collector << "REPLACE("
        collector = visit o.expr,collector
        collector << ","
        if(o.left.is_a?(Arel::Attributes::Attribute))
          collector = visit o.left, collector
        else
          collector << "'#{o.left}'"
        end
        collector << ","
        if(o.right.is_a?(Arel::Attributes::Attribute))
          collector = visit o.right, collector
        else
          collector << "'#{o.right}'"
        end
        collector << ")"
        collector
      end

      def visit_Arel_Nodes_Regexp o, collector
        collector = visit o.left, collector
        collector << " REGEXP '#{o.right}'"
        collector
      end

      def visit_Arel_Nodes_NotRegexp o, collector
        collector = visit o.left, collector
        collector << " NOT REGEXP "
        collector << "'#{o.right}'"
        collector
      end

      def visit_ArelExtensions_Nodes_Wday o, collector
        collector << "strftime('%w',"
        if((o.date).is_a?(Arel::Attributes::Attribute))
          collector = visit o.date, collector
        else
          collector << "'#{o.date}'"
        end
        collector << ")"
        collector
      end

    end
  end
end