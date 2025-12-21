#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Setup or teardown PostgreSQL test databases
#
# Environment variables:
#   ARELX_DB_ACTION  - 'create' or 'drop'
#   ARELX_DB_NAME    - Database name to create/drop
#   RUBY_VERSION     - Ruby version (used to select jdbc-postgresql vs postgresql)

require 'logger'
require 'active_record'
require_relative 'config_loader'

begin
  action = ENV.fetch('ARELX_DB_ACTION', 'create')
  db_name = ENV.fetch('ARELX_DB_NAME')
  ruby_version = ENV.fetch('RUBY_VERSION', '')

  # Determine which adapter config to use based on Ruby version
  adapter_key = ruby_version.include?('jruby') ? 'jdbc-postgresql' : 'postgresql'

  operation = action == 'create' ? :create_database : :drop_database

  config = ConfigLoader.load('test/database.yml')[adapter_key].dup
  # Connect to 'postgres' admin database for create/drop operations
  config['database'] = 'postgres'

  ActiveRecord::Base.establish_connection(config)
  ActiveRecord::Base.connection.send(operation, db_name)
  puts "#{action.capitalize} database '#{db_name}' successful"
rescue => e
  puts "DB Operation failed: #{e.message}", '', e.backtrace
  exit(1)
end
