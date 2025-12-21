#!/usr/bin/env ruby
# Setup or teardown MSSQL test databases
#
# Environment variables:
#   ARELX_DB_ACTION  - 'create' or 'drop'
#   ARELX_DB_NAME    - Database name to create/drop
#   RUBY_VERSION     - Ruby version (used for adapter selection)
#   RAILS_VERSION    - Rails version (used for dependency selection)

require 'logger'
require 'active_record'
require_relative 'config_loader'

begin
  action = ENV.fetch('ARELX_DB_ACTION', 'create')
  db_name = ENV.fetch('ARELX_DB_NAME')
  ruby_version = ENV.fetch('RUBY_VERSION', '')
  rails_version = ENV.fetch('RAILS_VERSION', '')

  # Determine which extra requirement to load based on Ruby/Rails combination
  extra_req =
    if ruby_version.match?(/\Ajruby-9.2/) && rails_version == '5_2'
      'activerecord-jdbcsqlserver-adapter'
    elsif ruby_version.match?(/\Ajruby/)
      nil
    else
      'activerecord-sqlserver-adapter'
    end

  # Load the extra requirement if needed
  require extra_req if extra_req

  operation = action == 'create' ? :create_database : :drop_database

  config = ConfigLoader.load('test/database.yml')['mssql'].dup
  # Connect to 'master' admin database for create/drop operations
  config['database'] = 'master'

  ActiveRecord::Base.establish_connection(config)
  ActiveRecord::Base.connection.send(operation, db_name)
  puts "#{action.capitalize} database '#{db_name}' successful"
rescue => e
  puts "DB Operation failed: #{e.message}", '', e.backtrace
  exit(1)
end
