# MSSQL visitors for java and rails ≥ 7 are painful to work with:
# requiring the exact path to the visitor is needed even if the
# AR adapter was loaded. It's also needed exactly here because:
# 1. putting it inside the visitor or anywhere else will not
#    guarantee its actual loading.
# 2. it needs to load before arel_extensions/visitors.
if RUBY_PLATFORM == 'java' \
  && RUBY_ENGINE == 'jruby' \
  && (version = JRUBY_VERSION.split('.').map(&:to_i)) && version[0] == 9 && version[1] >= 4 \
  && Gem::Specification.find { |g| g.name == 'jdbc-mssql' }
  begin
    require 'arel/visitors/sqlserver'
  rescue LoadError
    warn 'arel/visitors/sqlserver not found: MSSQL might not work correctly.'
  end
elsif RUBY_PLATFORM != 'java' \
  && ArelExtensions::AREL_VERSION < ArelExtensions::V10 \
  && Gem::Specification.find { |g| g.name == 'activerecord-sqlserver-adapter' }
  begin
    require 'arel_sqlserver'
  rescue LoadError
    warn 'arel_sqlserver not found: SQLServer Visitor might not work correctly.'
  end
end

require 'arel_extensions/visitors/convert_format'
require 'arel_extensions/visitors/to_sql'
require 'arel_extensions/visitors/mysql'
require 'arel_extensions/visitors/mssql'
require 'arel_extensions/visitors/postgresql'
require 'arel_extensions/visitors/sqlite'

if defined?(Arel::Visitors::Oracle)
  require 'arel_extensions/visitors/oracle'
  require 'arel_extensions/visitors/oracle12'
end

if defined?(Arel::Visitors::SQLServer)
  class Arel::Visitors::SQLServer
    include ArelExtensions::Visitors::MSSQL
  end
end

if defined?(Arel::Visitors::DepthFirst)
  class Arel::Visitors::DepthFirst
    def visit_Arel_SelectManager(o)
      visit o.ast
    end
  end
end

if defined?(Arel::Visitors::MSSQL)
  class Arel::Visitors::MSSQL
    include ArelExtensions::Visitors::MSSQL

    alias old_visit_Arel_Nodes_SelectStatement visit_Arel_Nodes_SelectStatement
    def visit_Arel_Nodes_SelectStatement(o, collector)
      if !collector.value.blank? && o.limit.blank? && o.offset.blank?
        o = o.dup
        o.orders = []
      end
      old_visit_Arel_Nodes_SelectStatement(o, collector)
    end
  end
end

if defined?(Arel::Visitors::SQLServer)
  class Arel::Visitors::SQLServer
    include ArelExtensions::Visitors::MSSQL

    # There's a bug when working with jruby 9.4 that prevents us from
    # refactoring this and putting it in the main module, or even in a separate
    # module then including it.
    #
    # Reason: the line in this file that does:
    #
    #   require 'arel_extensions/visitors/mssql'
    #
    # The error could be seen by:
    #
    #   1. placing the visit_ inside the visitor, or placing it in a module
    #      then including it here.
    #   2. replacing the `rescue nil` from aliasing trick, and printing the
    #      error.
    #
    # It complains that the visit_ does not exist in the module, as if it's
    # evaluating the module eagerly, instead of lazily like in other versions
    # of ruby.
    #
    # It might be something different, but this is the first thing we should
    # investigate.

    alias old_visit_Arel_Nodes_SelectStatement visit_Arel_Nodes_SelectStatement rescue nil
    def visit_Arel_Nodes_SelectStatement(o, collector)
      if !collector.value.blank? && o.limit.blank? && o.offset.blank?
        o = o.dup
        o.orders = []
      end
      old_visit_Arel_Nodes_SelectStatement(o, collector)
    end

    # When a query has a limit/offset but no order, the SQL Server adapter tries
    # to add a deterministic ORDER BY on the primary key of the queried table
    # (make_Fetch_Possible_And_Deterministic -> table_From_Statement, upstream).
    #
    # When the query reads FROM a derived table (e.g. a UNION or a sub-select
    # alias, as produced by our union helpers) there is no physical table to look
    # up: upstream's table_From_Statement returns an Arel node that has no #name
    # and primary_Key_From_Table crashes while generating the SQL.
    #
    # Resolve the real Arel::Table when the alias just wraps one; otherwise return
    # nil so the adapter simply skips the primary-key ordering. A limit/offset
    # over a derived table then still needs an explicit .order(...) to run, since
    # SQL Server requires ORDER BY with OFFSET/FETCH.
    alias old_arelx_table_From_Statement table_From_Statement rescue nil
    def table_From_Statement(o)
      core = o.cores.first
      from = core && (core.from || (core.source.is_a?(Arel::Nodes::JoinSource) ? core.source.left : nil))

      if from.is_a?(Arel::Nodes::TableAlias) || from.is_a?(Arel::Nodes::As)
        rel = from.respond_to?(:relation) ? from.relation : from.left
        rel.is_a?(Arel::Table) ? rel : nil
      else
        old_arelx_table_From_Statement(o)
      end
    end
  end
end
