#!/usr/bin/env ruby
# frozen_string_literal: true

require 'etc'
require 'json'
require 'logger'
require 'optparse'
require 'pp'

# ANSI color code mappings
COLORS = {
  red: 31,
  green: 32,
  yellow: 33,
  cyan: 36,
  white: 37,
  default: 0
}.freeze

# String color extensions for terminal output
class String
  def red
    colorize(COLORS[:red])
  end

  def green
    colorize(COLORS[:green])
  end

  def yellow
    colorize(COLORS[:yellow])
  end

  def cyan
    colorize(COLORS[:cyan])
  end

  def white
    colorize(COLORS[:white])
  end

  def colorize(code)
    "\e[#{code}m#{self}\e[0m"
  end
end

def in_container? = File.exist?('/.dockerenv') || File.exist?('/run/.containerenv')

def container_exec(args: ARGV, container: 'arelx', log: setup_logger, prog: "bin/#{File.basename($0)}")
  log.msg 'Detected Host OS. Running in container…'

  env = ENV.slice('LOG').map { |k, v| "#{k}=#{v}" }

  cmd = %w[compose -f dev/compose.yaml exec]
  cmd += ['-e', *env] if !env.empty?
  cmd += [container, prog, *args]

  log.debug "relaying to `docker #{cmd}`"

  exec 'docker', *cmd
end

def setup_logger
  logger = Logger.new($stdout, progname: File.basename($0))
  logger.formatter = SimpleFormatter.new
  level =
    case ENV.fetch('LOG', 'INFO').upcase
    when 'DEBUG' then Logger::DEBUG
    when 'ERROR' then Logger::ERROR
    when 'FATAL' then Logger::FATAL
    when 'INFO'  then Logger::INFO
    when 'UNKNOWN' then Logger::UNKNOWN
    when 'WARN'  then Logger::WARN
    else Logger::INFO
    end

  logger.level = level
  logger
end

# Simple formatter for clean logging output
class SimpleFormatter < Logger::Formatter
  def call(severity, datetime, progname, msg)
    hostname = "[#{Etc.uname[:nodename]}]"
    hostname = "🐋 #{hostname}" if in_container?
    "[#{progname}] #{hostname} #{msg}\n"
  end
end

class ExecLogger
  attr_reader :log

  def initialize(log: nil)
    @log = log || setup_logger
  end

  def error(text) = log.error(text)
  def debug(text) = log.debug(text)
  def info(text) = log.info(text)
  def msg(text) = log.info(text.cyan)
  def trace(text) = log.trace(text)
  def warn(text) = log.warn(text)

  # Log job result
  #
  # @param job [Hash] job hash
  # @param ok [Boolean] whether job succeeded
  # @param output [String] command output
  # @return [void]
  def job(job, ok, output)
    config = job.map { |key, value| "#{key}:#{value}" }.join(' ')
    if ok
      log.info("#{'✓'.green} #{config}")
      log.debug(output)
    else
      log.error("#{'×'.red} #{config.red}\n#{output}\n#{'-' * 40}")
    end
  end
end

# Determine the database adapter key based on task and Ruby version.
#
# @param task [String] task name (e.g., "test:sqlite", "test:mysql")
# @param ruby [String] Ruby version (e.g., "3.2", "jruby-9.4")
# @return [String] adapter key from database.yml
def database_yaml_adapter_key(task:, ruby:)
  db_type = task.sub('test:', '')
  is_jruby = ruby.start_with?('jruby')

  case db_type
  in 'sqlite'
    is_jruby ? 'jdbc-sqlite' : 'sqlite'
  in 'mysql'
    is_jruby ? 'jdbc-mysql' : 'mysql'
  in 'postgresql'
    is_jruby ? 'jdbc-postgresql' : 'postgresql'
  in 'mssql'
    'mssql'
  end
end

# Generate inline Ruby code to execute SQL and print results.
#
# The generated code:
# 1. Loads necessary dependencies
# 2. Reads database configuration from test/database.yml
# 3. Establishes a database connection
# 4. Executes the provided SQL statement
# 5. Prints the results
#
# @param adapter [String] adapter key from database.yml
# @return [String] Ruby code to be executed with ruby -e
def exec_sql_rb(adapter)
  <<~RUBY
    require 'logger'
    require 'active_record'
    require 'erb'
    require 'yaml'

    # Load database configuration
    yaml_content = ERB.new(File.read('test/database.yml')).result
    config = YAML.load(yaml_content)['#{adapter}']

    # Establish connection
    ActiveRecord::Base.establish_connection(config)

    # Execute SQL
    result = ActiveRecord::Base.connection.execute(#{@sql.inspect})

    # Print results
    if result.is_a?(Integer)
      puts "Rows affected: \#{result}"
    elsif result.respond_to?(:each)
      result.each do |row|
        puts row.inspect
      end
    else
      puts result.inspect
    end
  RUBY
end

# Handles version range matching with support for prefix matching, ranges, and negation.
#
# Supports the following syntax:
# - "3.2"       - Exact match
# - "3:"        - Prefix match (all versions starting with 3)
# - "3:3.3"     - Range match (from 3 to 3.3, inclusive)
# - "!3.2"      - Negated exact match (not 3.2)
# - "!3:"       - Negated prefix match (not starting with 3)
# - "!3:3.3"    - Negated range match (not between 3 and 3.3)
#
# @example Usage
#   VersionRange.predicate("3.2").call("3.2")       # => true
module VersionRange
  # Parse a version specification and return a predicate function.
  #
  # @param spec [String] version specification (e.g., "3.2", "3:", "3:3.3", "!3.2")
  # @return [Proc] predicate function that takes a version string
  def self.predicate(spec)
    negated = spec.start_with?('!')
    spec = spec[1..-1] if negated

    # Determine the type of match and create the predicate
    predicate =
      case spec
      in /:\z/ # ends with colon -> prefix match
        prefix = spec.chomp(':')
        ->(v) { v.start_with?(prefix) }
      in /:/ # contains colon -> range match
        from, to = spec.split(':', 2)
        ->(v) { between?(from, v, to) }
      else # no special syntax -> exact match
        ->(v) { v == spec }
      end

    # Apply negation if needed
    negated ? ->(v) { !predicate.call(v) } : predicate
  end

  private

  # Check if a version falls within a range (inclusive on both ends).
  #
  # @param lower [String] the lower bound (inclusive)
  # @param value [String] the version to check
  # @param upper [String] the upper bound (inclusive)
  # @return [Boolean] true if version is in range
  def self.between?(lower, value, upper)
    l, o, u = [lower, value, upper].map {
      Gem::Version.new(it.sub(/\Ajruby-/, ''))
    }
    l <= o && o <= u
  end
end

# Parses filter strings and generates predicate functions for job filtering.
#
# Supports exact matching on all fields with special normalizations:
# - jruby:X is normalized to ruby:jruby-X
# - task:to_sql is normalized to task:test:to_sql
# - test:to_sql is normalized to task:test:to_sql
#
# @example Usage
#   predicates = FilterParser.parse("ruby:3.2 rails:8")
#   job = { ruby: "3.2", rails: "8", arelx: 2, task: "test:sqlite" }
#   predicates.all? { |p| p.call(job) }  # => true
class FilterParser
  TASK_ALIASES = {
    'pg' => 'postgresql',
    'postgres' => 'postgresql',
    'my' => 'mysql'
  }.freeze

  # Parse filter tokens into an array of predicate functions.
  #
  # Accepts an array of filter tokens where each can contain space-separated filters.
  # Flattens all tokens and converts them to predicates.
  # Special cases:
  # - jruby:9.2 is normalized to ruby:jruby-9.2
  # - task:to_sql is normalized to task:test:to_sql
  # - test:to_sql is normalized to task:test:to_sql
  #
  # @param tokens [Array<String>, String, nil] filter tokens or a single string
  # @return [Array<Proc>] array of predicate functions that take a job hash
  #
  # @example Single filter as string
  #   FilterParser.parse("ruby:3.2")
  #
  # @example Array with space-separated tokens
  #   FilterParser.parse(["ruby:3.2 rails:8", "task:postgresql"])
  def self.parse(tokens)
    if tokens.is_a?(String)
      tokens = tokens.empty? ? [] : tokens.split(/\s+/)
    end

    return [] if tokens.nil? || tokens.empty?

    tokens.flat_map { it.split(/\s+/).map { filter(it) } }
  end

  # Parse a single filter token into a predicate function.
  #
  # Normalizes:
  # - jruby:X to ruby:jruby-X
  # - task:to_sql to task:test:to_sql
  # - test:to_sql to task:test:to_sql
  #
  # Supports version range syntax for ruby, rails, and arelx:
  # - "3.2"       - Exact match
  # - "3:"        - Prefix match (all versions starting with 3)
  # - "3:3.3"     - Range match (from 3 to 3.3, inclusive)
  # - "!3.2"      - Negated exact match (not 3.2)
  # - "!3:"       - Negated prefix match (not starting with 3)
  # - "!3:3.3"    - Negated range match (not between 3 and 3.3)
  #
  # Support some handy aliases for tasks:
  # - "test:pg" = "test:postgres" = "test:postgresql"
  # - "test:my" = "test:mysql"
  #
  # @param token [String] single filter token (e.g., "ruby:3.2", "task:test:mssql", "jruby:9.4", "ruby:!3:")
  # @return [Proc] predicate function that takes a job hash
  def self.filter(token)
    # Split only on first colon to handle multi-segment values like "task:test:mssql"
    key, value =
      case token.split(':', 2)
      in ['jruby', v]
        [:ruby, normalize(v, 'jruby-')]
      in ['test' | 'task', v]
        [:task, normalize(v, 'test:')]
      in [k, v]
        [k.to_sym, v]
      end

    if %i[ruby rails arelx].include?(key) && value.match?(/:|!/)
      ->(job) { VersionRange.predicate(value).call(job[key].to_s) }
    elsif value.start_with?('!')
      ->(job) { job[key].to_s != value.delete_prefix('!') }
    else
      ->(job) { job[key].to_s == value }
    end
  end

  # Normalize a filter value by handling negation markers and prefixes.
  #
  # Extracts any leading negation marker (!), ensures the value has the required prefix,
  # and restores the negation marker at the front of the final result. This ensures that
  # negation is always positioned at the start where VersionRange.predicate expects it.
  #
  # @param value [String] the value to normalize (e.g., "!9.4", "postgresql", "!to_sql")
  # @param prefix [String] the prefix to prepend if not already present (e.g., "jruby-", "test:")
  # @return [String] the normalized value with negation marker (if present) at the front
  # @private
  def self.normalize(value, prefix)
    value.match(/\A(?<neg>!?)(?<target>.*)/) in { neg:, target: }
    target = TASK_ALIASES[target] || target if prefix == 'test:'
    "#{neg}#{prefix}#{target}"
  end

  private_class_method :filter
  private_class_method :normalize
end

# Matrix generates the test job matrix for arel-extensions.
#
# @example As a library
#   require_relative 'test-matrix'
#   jobs = Matrix.jobs(filter: "3.2")
#   jobs.each { |job| puts "#{job[:ruby]} #{job[:rails]} #{job[:task]}" }
module Matrix
  # Matrix of Ruby versions to Rails/ArelExtensions version combinations
  MATRIX =
    {
      '3.4' => %w[8.1 8 7.2 7.1 7 6.1],
      '3.3' => %w[8.1 8 7.2 7.1 7 6.1],
      '3.2' => %w[8.1 8 7.2 7.1 7 6.1 6],
      '3.1' => %w[7.2 7.1 7 6.1 6],
      '3.0' => %w[7.1 7 6.1 6],
      '2.7' => %w[7.1 7 6.1 6 5.2],
      'jruby-9.4' => %w[7.1 7],
      'jruby-9.3'  => %w[6.1 6 5.2],
      'jruby-9.2' => %w[6.1 6 5.2],
    }
    .transform_values { |rails|
      rails.map { |r| { rails: r, arelx: (r == '5.2' ? 1 : 2) } }
    }
    .freeze

  # JRuby + MSSQL allowlist for compatible combinations
  JRUBY_MSSQL_ALLOWED =
    {
      'jruby-9.2' => %w[5.2],
      'jruby-9.3' => %w[],
      'jruby-9.4' => %w[7 7.1],
    }.freeze

  # Available test tasks
  TASKS = %w[test:to_sql test:sqlite test:mysql test:postgresql test:mssql].freeze

  # Generate all test jobs, optionally filtered by exact matching.
  #
  # @param filter [String, nil] filter string (e.g., "ruby:3.2 rails:8")
  # @return [Array<Hash>] array of job hashes with keys :ruby, :rails, :arelx, :task
  #
  # @example Get all jobs
  #   Matrix.jobs  # => [{ ruby: "3.4", rails: "8.1", arelx: 2, task: "test:sqlite" }, ...]
  #
  # @example Filter by Ruby version
  #   Matrix.jobs(filter: "ruby:3.2")  # => Only jobs for Ruby 3.2.x
  def self.jobs(filter: nil)
    predicates = FilterParser.parse(filter)

    res = []
    MATRIX.keys.each do |ruby|
      MATRIX[ruby].each do |config|
        TASKS.each do |task|
          next if skip_job?(ruby, config[:rails], task)

          job = config.merge(ruby:, task:)

          next if !predicates.all? { it.call(job) }

          res << job
        end
      end
    end

    res
  end

  # Check if a job should be skipped based on compatibility rules.
  #
  # Currently only enforces JRuby + MSSQL allowlist.
  #
  # @param ruby [String] Ruby version
  # @param rails [String] Rails version
  # @param task [String] Task name
  # @return [Boolean] true if job should be skipped
  def self.skip_job?(ruby, rails, task)
    task =~ /mssql/ \
      && (allow = JRUBY_MSSQL_ALLOWED[ruby]) \
      && allow.none? { it == rails }
  end

  private_class_method :skip_job?
end

if __FILE__ == $PROGRAM_NAME
  require "minitest/autorun"
  require "minitest/spec"

  describe "VersionRange" do
    # [Spec,        [Matching Versions],  [Non-Matching Versions]]
    [
      ["3.2",        %w[3.2],             %w[3.3 3.2.1]],
      ["3:",         %w[3.0 3.2 3.9],     %w[2.9 4.0]],
      ["3.1:3.3",    %w[3.1 3.2 3.3],     %w[3.0 3.4]],
      ["!3.2",       %w[3.1 3.3],         %w[3.2]],
      ["!3:",        %w[2.9 4.0],         %w[3.0 3.9]],
      ["!3.1:3.3",   %w[3.0 3.4],         %w[3.1 3.2 3.3]],
      ["jruby-9.2",  %w[jruby-9.2],       %w[jruby-9.3]],
      ["9.2:9.4",    %w[jruby-9.3],       %w[jruby-9.1]],
      ["!jruby-9:",  %w[3.2],             %w[jruby-9.2]],
    ].each do |spec, matches, non_matches|
      it "handles '#{spec}' correctly" do
        pred = VersionRange.predicate(spec)
        matches.each { assert pred.call(it), "Expected #{spec} to match #{it}" }
        non_matches.each { refute pred.call(it), "Expected #{spec} NOT to match #{it}" }
      end
    end
  end

  describe "FilterParser" do
    describe "Normalization" do
      let(:defaults) { { ruby: "3.2", rails: "8", task: "test:sqlite", arelx: 2 } }
      # [Filter String,     Matching Task,                      Non-Matching Task]
      [
        # Standard fields
        ["ruby:3.2",        {},                                { ruby: "3.3" }],
        ["rails:8",         {},                                { rails: "7.0" }],

        # Ranges and Prefixes
        ["ruby:3.1:3.3",    { ruby: "3.2" },                   { ruby: "3.4" }],
        ["rails:7:",        { rails: "7.1" },                  { rails: "6.1" }],

        # Negated Ranges and Prefixes
        ["ruby:!3.1:3.3",   { ruby: "3.0" },                   { ruby: "3.2" }],
        ["rails:!7:",       { rails: "6.1" },                  { rails: "7.0" }],

        # JRuby Normalization: "jruby:X" -> ruby:jruby-X
        ["jruby:9.4",       { ruby: "jruby-9.4" },             { ruby: "3.2" }],
        ["jruby:!9.4",      { ruby: "jruby-9.3" },             { ruby: "jruby-9.4" }],

        # Task Normalization: "task:foo" -> task:test:foo, "test:foo" -> task:test:foo
        ["task:mssql",      { task: "test:mssql" },            { task: "test:sqlite" }],
        ["test:mssql",      { task: "test:mssql" },            { task: "test:sqlite" }],

        # Negation combined with normalization
        ["ruby:!3.2",       { ruby: "3.1" },                   { ruby: "3.2" }],
        ["task:!sqlite",    { task: "test:mysql" },            { task: "test:sqlite" }],
        ["test:!sqlite",    { task: "test:mysql" },            { task: "test:sqlite" }],

        # Task aliases
        ["task:pg",         { task: "test:postgresql" },       { task: "test:sqlite" }],
        ["task:postgres",   { task: "test:postgresql" },       { task: "test:sqlite" }],
        ["test:my",         { task: "test:mysql" },            { task: "test:sqlite" }],
        ["task:!pg",        { task: "test:sqlite" },           { task: "test:postgresql" }],
        ["task:!postgres",  { task: "test:sqlite" },           { task: "test:postgresql" }],
        ["test:!my",        { task: "test:sqlite" },           { task: "test:mysql" }],
      ].each do |filter, match, no_match|
        it "filters '#{filter}'" do
          preds = FilterParser.parse(filter)
          assert preds.all? { it.call(defaults.merge(match)) }
          refute preds.all? { it.call(defaults.merge(no_match)) }
        end
      end
    end

    describe "Input Formats" do
      let(:job) { { ruby: "3.2", rails: "8" } }

      [
        ["array",  ["ruby:3.2", "rails:8"]],
        ["string", "ruby:3.2 rails:8"],
        ["mixed",  ["ruby:3.2", "rails:8"]]
      ].each do |desc, input|
        it "parses #{desc}" do
          assert FilterParser.parse(input).all? { it.call(job) }
        end
      end
    end
  end

  describe "Matrix" do
    it "skips invalid JRuby+MSSQL" do
      assert_empty Matrix.jobs(filter: "jruby:9.4 rails:6.1 task:mssql")
      refute_empty Matrix.jobs(filter: "jruby:9.4 rails:7.1 task:mssql")
    end
  end
end
