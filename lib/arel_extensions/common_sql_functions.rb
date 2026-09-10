# frozen_string_literal: true

module ArelExtensions
  class CommonSqlFunctions
    # SQLite has a native SOUNDEX, but the sqlite3 gem is compiled without it and
    # I couldn't get it to work with system sqlite3, so I provided SOUNDEX in Ruby space.
    SOUNDEX_GROUPS = {
      1 => %w[B F P V],
      2 => %w[C G J K Q S X Z],
      3 => %w[D T],
      4 => %w[L],
      5 => %w[M N],
      6 => %w[R],
    }.freeze

    SOUNDEX_CODES =
      SOUNDEX_GROUPS
        .flat_map { |code, letters| letters.map { |l| [l, code.to_s] } }
        .to_h
        .freeze

    def initialize(cnx)
      @cnx = cnx
      if cnx && cnx.adapter_name =~ /sqlite/i && !$load_extension_disabled
        begin
          db = cnx.raw_connection
          db.enable_load_extension(1)
          db.load_extension('/usr/lib/sqlite3/pcre.so')
          db.load_extension('/usr/lib/sqlite3/extension-functions.so')
          db.enable_load_extension(0)
        rescue StandardError => e
          $load_extension_disabled = true
          puts "cannot load extensions #{e.inspect}"
        end
      end
    end

    def add_sqlite_functions
      db = @cnx.raw_connection
      db.create_function('find_in_set', 1) do |func, val, list|
        case list
        when String
          i = list.split(',').index(val.to_s)
          func.result = i ? (i + 1) : 0
        when NilClass
          func.result = nil
        else
          i = list.to_s.split(',').index(val.to_s)
          func.result = i ? (i + 1) : 0
        end
      end
      db.create_function('instr', 1) do |func, value1, value2|
        i = value1.to_s.index(value2.to_s)
        func.result = i ? (i + 1) : 0
      end rescue 'function instr already here (>= 3.8.5)'
      db.create_function('soundex', 1) do |func, val|
        func.result = val.nil? ? nil : soundex(val.to_s)
      end
    end

    # It's not really important to be absolutely correct. We just want to make sure it's called.
    def soundex(str)
      letters = str.upcase.gsub(/[^A-Z]/, '').chars
      return '' if letters.empty?

      first = letters.shift
      digits = +''
      last_code = SOUNDEX_CODES[first]
      letters.each do |ch|
        code = SOUNDEX_CODES[ch]
        if code
          digits << code if code != last_code
          last_code = code
        elsif ch != 'H' && ch != 'W'
          last_code = nil
        end
      end
      (first + digits).ljust(4, '0')[0, 4]
    end

    def add_sql_functions(env_db = nil)
      env_db ||= @cnx.adapter_name
      env_db = 'mysql' if /mysql/i.match?(env_db)
      if /sqlite/i.match?(env_db)
        begin
          add_sqlite_functions
        rescue StandardError => e
          puts "cannot add sqlite functions #{e.inspect}"
        end
      end
      if File.exist?("init/#{env_db}.sql")
        sql = File.read("init/#{env_db}.sql")
        if env_db == 'mssql'
          sql.split(/^GO\s*$/).each { |str|
            @cnx.execute(str.strip) unless str.blank?
          }
        elsif env_db == 'mysql'
          sql.split('$$')[1..-2].each { |str|
            @cnx.execute(str.strip) unless str.strip.blank?
          }
        else
          @cnx.execute(sql) unless sql.blank?
        end
      end
    end
  end
end
