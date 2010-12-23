#------------------------------------------------------------------------------------------------------------#
#  888    888          888                                    
#  888    888          888                                    
#  888    888          888                                    
#  8888888888  .d88b.  888 88888b.   .d88b.  888d888 .d8888b  
#  888    888 d8P  Y8b 888 888 "88b d8P  Y8b 888P"   88K      
#  888    888 88888888 888 888  888 88888888 888     "Y8888b. 
#  888    888 Y8b.     888 888 d88P Y8b.     888          X88 
#  888    888  "Y8888  888 88888P"   "Y8888  888      88888P' 
#                          888                                
#                          888                                
#                          888                                
#------------------------------------------------------------------------------------------------------------#

#
# Copyright 2010 Long Weekend LLC
# Written by paul [a.] t longwwekendmobile.com
# Please read the README file
#

#### Core RiTune Methods ####
module RiHelpers

  def configure_ritunes
    # Call inside task to override rails defaults
    $options = {}
    $options[:default_break_point] = 0
    $options[:verbose] = true
    $options[:force_utf8] = false
    $options[:cache_fu_on] = false
    $options[:mysql_port] = 3306
    $options[:mysql_name] = "ritunes"
    $options[:mysql_host] = "localhost"
    $options[:mysql_username] ="root"
    $options[:mysql_password] = ""
    $options[:itunes_max_recs] = 500
    
    # Create storage tables if they don't exist!
    create_ritunes_tables(nil, true)
  end

  # create validation token iTunes Store will accept using md5 hash
  def get_validation_seed(url, user_agent)
    require 'base64'
    require 'digest/md5'
    random_str  = "%04X04X" % [(rand * 0x10000), (rand * 0x10000)]
    static = Base64.decode64("ROkjAaKid4EUF5kGtTNn3Q==")
    matches = url.scan(/.*\/.*\/.*(\/.+)$/)
    url_end = (matches.size > 0 ? matches[0] : '?')
    digest  = Digest::MD5.hexdigest([url_end, user_agent, static, random_str].join("") )
    return random_str + '-' + digest.to_s.upcase
  end
  
  def get_itunes_headers(url, store_front=nil, user_agent=nil)
    store_front = "143457" if store_front.nil?
    user_agent = "iTunes/9.2 (Macintosh; Intel Mac OS X 10.6.4) AppleWebKit/533.16" if user_agent.nil?
    return {
      "X-Apple-Tz" => "7200",
      "X-Apple-Store-Front" => store_front,
      "Accept-Language" => "en-us, en;q=0.50",
      "X-Apple-Validation" => get_validation_seed(url, user_agent),
      "Accept-Encoding" => "gzip, x-aes-cbc",
      "Connection" => "close",
      "Host" => "ax.phobos.apple.com.edgesuite.net"
    }
  end

  # List of significant iTunes stores, add yours if not here
  def get_itunes_countries
    ["us", "gb", "jp", "au", "ca", "kr", "de", "fr"]
  end

  # method for searching itunes using the private api, for educational use only, blah blah blah
  def search_itunes_private(options_hash, dump=false)

    private_base_url = "http://ax.search.itunes.apple.com/WebObjects/MZSearch.woa/wa/advancedSearch?"
    private_api_query_str = "media=software&softwareTerm=#{options_hash[:term]}&softwareDeveloper=&genreIndex=#{options_hash[:genreIndex]}&deviceTerm=AllDevices"
    search_url = private_base_url + private_api_query_str

    search_url = "http://ax.search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?submit=seeAllLockups&term=japanese+study+app+cards&entity=software&restrict=true&media=all"
    
    bot = Mechanize.new do |agent| 
      agent.pre_connect_hooks << lambda do |params|
        get_itunes_headers(search_url).each { |k,v| params[:request][k] = v }
      end
    end

    doc = nil
    bot.get(search_url) do |page|
      # doc = Nokogiri::XML(page.body, nil,'UTF-8')
      doc = page.body
    end
    return doc

  end

  # method for searching the itunes public api
  def search_itunes_public(options_hash, dump=false)

    # Lookup URL
    # http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStoreServices.woa/wa/wsLookup?id=296430281

    # Searches that work ...
    # ?attribute=genreTerm&entity=software&term=Education
    # ?attribute=keywordsTerm&entity=software&term=japanese+app
    # ?attribute=keywordsTerm&entity=software&term=japanese+app

    public_base_url_str  = "http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStoreServices.woa/wa/wsSearch?"
    country_codes_array = get_itunes_countries
    search_options_hash = { 
      :term => "term",
      :output => "output", 
      :lang => "lang",
      :offset => "offset",
      :output => "output",
      :entity => "entity"
    }
    recs_per_page = 500
    limit = options_hash[:limit].to_i if options_hash.has_key?(:limit)

    # Order sensitive criteria
    options_hash[:entity]    = "software" if !options_hash.has_key?(:entity)
    ## NOT NEEDED ## options_hash[:attribute] = "keywordsTerm" if !options_hash.has_key?(:attribute)
    param_str = "attribute=#{options_hash[:attribute]}&entity=#{options_hash[:entity]}"

    if options_hash[:attribute] == "keywordsTerm"
      keywords = options_hash[:term]
    else
      keywords = ""
    end

    # remove processed items from hash
    options_hash.delete(:entity)
    options_hash.delete(:attribute)

    # Process other options
    search_options_hash.each do |key, attrib|
      param_str = param_str + "&#{attrib}=#{options_hash[key]}" if options_hash.has_key?(key) and !options_hash[key].nil? and options_hash[key].size > 0
    end

    # Order matters, append these!
    param_str = param_str + "&limit=#{recs_per_page}"
    param_str = param_str + "&country=#{options_hash[:country]}" if options_hash.has_key?(:country) && country_codes_array.index(options_hash[:country])
    result_array = process_paged_search(public_base_url_str, param_str, keywords, recs_per_page, limit, dump)
    return result_array
  end

  def process_paged_search(search_url, search_params, keywords, recs_per_page=500, limit=0, dump=false)
    if limit > recs_per_page
      pages = (limit - (limit % recs_per_page)) / recs_per_page + (limit % recs_per_page == 0 ? 0 : 0)
    else
      pages = 1
    end

    rank = 0
    for page_no in 1..pages
      search_url= search_url + search_params + "&offset=#{page_no*recs_per_page - recs_per_page+1}"
      result_array = []
      prt "\n" + search_url + "\n"

      bot = Mechanize.new do |agent| 
        agent.user_agent_alias = 'Mac Safari' 
      end
  
      bot.get(search_url) do |page|
        result_array = get_result_array(page)
      end
  
      if result_array and result_array.size > 0
        # log results to mysql
        connect_db
        search_id  = get_sql_log_search(search_params)
        bulkSQL = BulkSQLRunner.new(0, 10000)
        rank = (page_no-1)*recs_per_page

        result_array.each do |rec|
          rank += 1
          get_sql_log_publisher( rec )
          bulkSQL.add( get_sql_log_app(rec) )
          bulkSQL.add( get_sql_log_publisher(rec) )
          bulkSQL.add( get_sql_log_keywords(rec['trackId'], keywords) )
          bulkSQL.add( get_sql_log_metadata(rec) )
          bulkSQL.add( get_sql_log_rankings(rank, rec['trackId'], search_id) )
        end
        bulkSQL.flush

        if dump
          # show details
          dump_search(options_hash[:term], result_array)
        else
          # report highlights
          prt "Retrieved: #{result_array.size} recs for '#{search_params}'"
        end
    
        # Get outta here if we're done!
        prt "-----------------"
        prt rank
        prt (recs_per_page*page_no)
      end
      break if rank < (recs_per_page*page_no)
    end
    return result_array
  end

  def empty_logging_tables
    connect_db
    prt "trunacting logging tables!"
    $cn.execute('TRUNCATE TABLE apps')
    $cn.execute('TRUNCATE TABLE keyword_index')
    $cn.execute('TRUNCATE TABLE metadata')
    $cn.execute('TRUNCATE TABLE rankings')
    $cn.execute('TRUNCATE TABLE publishers')
    $cn.execute('TRUNCATE TABLE searches')
  end

  def get_sql_log_app(rec)
    return "INSERT IGNORE INTO apps (app_id, publisher_id, name) VALUES (#{rec['trackId']}, #{rec['artistId']}, '#{mysql_escape_str(rec['trackName'])}');"
  end

  def get_sql_log_publisher(rec)
    return "INSERT IGNORE INTO publishers (publisher_id, name) VALUES (#{rec['artistId']}, '#{mysql_escape_str(rec['artistName'])}');"
  end

  def get_sql_log_search(search_string)
    connect_db
    tmp = []
    country = "WW"
    search_string.split('&').sort.each do |a|
      country = a.split('=')[1].upcase if a.index("country=")
      tmp << a if a.index("limit=").nil? and a.index("country=").nil? # do not include country or limit
    end

    search_string = tmp.join('&')
    existing_search_id = 0
    $cn.execute("SELECT search_id FROM searches WHERE search_string = '#{search_string}' AND country = '#{country}'").each do |search_id|
      existing_search_id = search_id
    end

    if existing_search_id != 0
      return existing_search_id
    else
      return $cn.insert("INSERT IGNORE INTO searches (search_string, country) VALUES ('#{search_string}', '#{country}')")
    end
  end
  
  def get_sql_log_rankings(rank, app_id, search_id)
    return "INSERT INTO rankings (app_id, search_id, rank, date) VALUES (#{app_id}, #{search_id}, #{rank}, '#{Time.now.to_s(:db)}');"
  end

  def get_sql_log_keywords(app_id, keywords)
    sql = []
    keywords.gsub('+',' ').split(' ').each do |kw|
      sql << "INSERT IGNORE INTO keyword_index (app_id, keyword) VALUES (#{app_id}, '#{mysql_escape_str(kw)}');"
    end
    return sql.join("\n")
  end
  
  def get_sql_log_metadata(rec)
    return "INSERT INTO metadata (app_id, price, date) VALUES (#{rec['trackId']}, '#{rec['price'].to_i}', '#{Time.now.to_s(:db)}');"
  end

  def dump_search(kw, result_array)
    kw = "[BLANK]" if kw.nil?
    prt "KEYWORDS: #{get_humanized_keywords(kw)}"
    prt "------------------------------------------------\n"
    count=0
    result_array.each do |r|
      count+=1
      prt "#{count}\t#{r["trackName"]}\t#{r["trackId"]}\t#{r["price"]}\t#{r[:version]}\t#{r[:releaseDate]}"
    end
  end
  
  def itunes_result_keys
    return ["price",
     "trackViewUrl",
     "genreIds",
     "sellerName",
     "artistId",
     "artworkUrl100",
     "trackName",
     "wrapperType",
     "screenshotUrls",
     "primaryGenreName",
     "artworkUrl60",
     "trackContentRating",
     "supportedDevices",
     "contentAdvisoryRating",
     "releaseDate",
     "version",
     "fileSizeBytes",
     "sellerUrl",
     "artistName",
     "artistViewUrl",
     "description",
     "languageCodesISO2A",
     "primaryGenreId",
     "ipadScreenshotUrls",
     "genres",
     "trackCensoredName",
     "trackId"]
  end

  def observation_price_high?(price)
    (price.to_i > 10)
  end

  def observation_name_overlong?(name)
    (name.size > 40)
  end

  def get_results(page)
    page.body["results"]
  end

  def get_results_count(page)
    page.body["results"].size
  end

  def get_mechanized_keywords_array(kw_arr)
    kw_arr.join("+").gsub(" ", "+")
  end
  
  def get_humanized_keywords(kw_str)
    kw_str.gsub("+", " ")
  end

  def get_result_array(page)
    JSON.parse(page.body)["results"]
  end

  def create_ritunes_tables(tables_arr=[], create_all=false)

    create_statements ={}
    create_statements["searches"] ="\
    CREATE TABLE `searches` (\
      `search_id` int(11) NOT NULL AUTO_INCREMENT,\
      `search_string` varchar(255) NOT NULL,\
      `country` varchar(2) DEFAULT NULL,\
      PRIMARY KEY (`search_id`),\
      UNIQUE KEY `search_string` (`search_string`),\
      KEY `search_string_2` (`search_string`)\
    ) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;"
    
    create_statements["rankings"] ="\
    CREATE TABLE `rankings` (\
      `search_id` int(11) NOT NULL,\
      `app_id` int(11) NOT NULL,\
      `rank` int(11) DEFAULT '0',\
      `date` datetime NOT NULL,\
      KEY `search_id` (`search_id`)\
    ) ENGINE=MyISAM DEFAULT CHARSET=utf8;"
    
    create_statements["publishers"] ="\
    CREATE TABLE `publishers` (\
      `publisher_id` int(11) NOT NULL,\
      `name` varchar(255) DEFAULT NULL,\
      PRIMARY KEY (`publisher_id`)\
    ) ENGINE=MyISAM DEFAULT CHARSET=utf8;"
    
    create_statements["metadata"] ="\
    CREATE TABLE `metadata` (\
      `id` int(11) NOT NULL AUTO_INCREMENT,\
      `app_id` int(11) DEFAULT NULL,\
      `price` int(11) DEFAULT NULL,\
      `date` datetime DEFAULT NULL,\
      PRIMARY KEY (`id`)\
    ) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;"
    
    create_statements["keyword_index"] ="\
    CREATE TABLE `keyword_index` (\
      `id` int(11) NOT NULL AUTO_INCREMENT,\
      `app_id` int(11) DEFAULT NULL,\
      `keyword` varchar(255) DEFAULT NULL,\
      PRIMARY KEY (`id`),\
      UNIQUE KEY `app_id` (`app_id`,`keyword`)\
    ) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;"
    
    create_statements["apps"] ="
    CREATE TABLE `apps` (\
      `app_id` int(11) NOT NULL,\
      `publisher_id` int(11) NOT NULL,\
      `name` varchar(255) NOT NULL,\
      PRIMARY KEY (`app_id`)\
    ) ENGINE=MyISAM DEFAULT CHARSET=utf8;"
    connect_db

    # Create tables we are told to make
    tables_arr = create_statements.keys.collect {|i| i} if create_all
    tables_arr.each do |table_nm|
      if tables_arr.index(table_nm) and !mysql_table_exists(table_nm)
        prt "Creating table: #{table_nm}"
        $cn.execute(create_statements[table_nm])
      end
    end

  end

end


#### BULK SQL RUNNER ####
#### Adds support for bulk inserting SQL at command line ####
class BulkSQLRunner
  
  def initialize(max_records=0, sql_buffer_size=1000, sql_debug=false)
    @sql_buffer_size = sql_buffer_size # buffer size 0 means manual flush expected
    @max_records = max_records
    @loop_count = 0
    @sql_line_count = 0
    @sql_execution_count = 0
    @sql_debug = sql_debug
    @buffered_sql_array = []
  end 
  
  # Add SQL commands to buffer
  def add(*args)
    @loop_count = @loop_count+1
    @sql_line_count = @sql_line_count+1
    @buffered_sql_array << args.to_s
    if @loop_count == @max_records || @sql_line_count == @sql_buffer_size && @sql_buffer_size != 0
      flush
    end
  end
  
  # Execute buffered SQL commands 
  def flush(sql_debug=false)
    @sql_execution_count = @sql_execution_count +1
    prt "Inserting #{@sql_execution_count * @sql_buffer_size - @sql_buffer_size + (@loop_count==@max_records?0:1)} ~ #{@loop_count} of #{(@max_records > @loop_count ? @max_records : @loop_count)}"
    if !sql_debug && !@sql_debug
     mysql_run_query_via_cli(@buffered_sql_array.join("\n"))
    else
      prt @buffered_sql_array.join("\n")
    end
    @buffered_sql_array = []
    @sql_line_count = 0
  end
end

#### DATABASE HELPER MODULE #####
module DatabaseHelpers

  # Create connection to DB in instance scope
  def connect_db
    if !$cn
      ActiveRecord::Base.establish_connection(
         :adapter  => "mysql",
         :database => $options[:mysql_name],
         :port     => $options[:mysql_port],
         :host     => $options[:mysql_host],
         :encoding => "utf8",
         :username => $options[:mysql_username],
         :password => $options[:mysql_password]
       )
       $cn = ActiveRecord::Base.connection()
    end
  end
  
  def get_random_filename
    # Create a random file name
    s = ""
    7.times { s << (65 + rand(26))  }
    "tedi3_" + s + ".sql"
  end

  def write_text_to_tmp_file(txt_blob)
    sql_tmp_fn = get_random_filename
    sql_tmp_file = File.open(sql_tmp_fn, 'w')
    sql_tmp_file.write(txt_blob)
    sql_tmp_file.close
    return sql_tmp_fn
  end

  def mysql_escape_str(txt)
    txt.gsub("'" , '\\\\\'')
  end
  
  # Return serialized object 
  def mysql_serialise_ruby_object(obj)
    return Base64.encode64(Marshal.dump(obj))
  end

  # Return original object 
  def mysql_deserialise_ruby_object(obj)
    return Marshal.load(Base64.decode64(obj))
  end

  def mysql_run_query_via_cli(txt_blob, db=$options[:mysql_name], username=$options[:mysql_username], pw=$options[:mysql_password])
    sql_tmp_fn = write_text_to_tmp_file(txt_blob)

    pw = (pw.size > 1 ? "-p #{pw} " : "")
    if username.nil?
      username = "-u root "
    else
      username = "-u #{username} "
    end

    # Run mysql from command line!
    prt "==== Opening Command Line ====\n" if $options[:verbose]
    cmd = "mysql -h localhost #{username} #{pw}--default_character_set utf8 #{db} < #{sql_tmp_fn}"
    prt "Executing: #{cmd}"
    if (!system(cmd))
      # Throw an exception here
      raise "MySQL returned an error message, I am throwing an exception"
    else
      # Delete tmp file
      File.delete(sql_tmp_fn)
    end

    prt "\n\n"
  end
  
  # Write text to file and run mysql from command line!
  def sqlite_run_query_via_cli(text_blob, dbfilepath)
    sql_tmp_fn = write_text_to_tmp_file(text_blob)
    sqlite_run_file_via_cli(sql_tmp_fn, dbfilepath)
    File.delete(sql_tmp_fn) # Delete tmp file
  end

  # Run existing sql file from command line!
  def sqlite_run_file_via_cli(filename, dbfilepath)
     prt "==== Opening Command Line ====\n" if $options[:verbose]
     cmd =  "#{$options[:sqlite_bin]} \"#{dbfilepath}\" < #{filename}"
     prt "Executing: #{cmd}"
     system(cmd)
     prt "\n\n"
  end
  
  # REINDEX
  def sqlite_reindex_tables(table_name_arr, dbfilepath)
    prt "==== Opening Command Line ====\n" if $options[:verbose]
    table_name_arr.each do |table|
      `#{$options[:sqlite_bin]} "#{dbfilepath}" 'REINDEX #{table};'`
    end
  end

  # VACUUM
  def sqlite_vacuum(dbfilepath)
    prt "==== Opening Command Line ====\n" if $options[:verbose]
    `#{$options[:sqlite_bin]} "#{dbfilepath}" 'VACUUM;'`
  end

  #
  # mysql_table_exists
  #
  def mysql_table_exists(table)
    return !$cn.select_one("SHOW TABLES LIKE '#{table}'").nil?
  end

  #
  # mysql_col_exists
  #
  def mysql_col_exists(table_col_str)
    tmp = table_col_str.split('.')
    table = tmp[0]
    col = tmp[1]
    return !$cn.select_one("SHOW COLUMNS FROM #{table} WHERE Field = '#{col}'").nil?
  end

  #
  # mysql_dump_tables_via_cli
  #
  def mysql_dump_tables_via_cli(table_array, tmp_outfile_sql, dbname)
    `mysqldump -uroot --compact --complete-insert --skip-quote-names --skip-extended-insert --no-create-info #{dbname} #{table_array.join(' ')} > #{tmp_outfile_sql}`
  end

  #
  # mysql_to_sqlite_converter
  #
  def mysql_to_sqlite_converter(filename)
    # Converts mysql escaped single quotes to sqlite escape single quotes using SED
    system!("sed \"s/\\\\\\'/\\'\\'/g\" #{filename} > #{filename}.2")
    system!("sed \'s/\\\\\\\"/\"/g\' #{filename}.2 > #{filename}.3")
    `cp #{filename}.3 #{filename}`
    File.delete("#{filename}.2")
    File.delete("#{filename}.3")
  end

  def delete_incomplete(table)
    connect_db
    $cn.execute("DELETE FROM #{table} WHERE import_status <> #{$options[:statuses]["completed"]} and import_status <> #{$options[:statuses]["not_imported"]}")
    prt "Deleted incomplete import items from #{table}" if $options[:verbose]
    return true
  end

  def disable_keys(table)
    connect_db
    $cn.execute("ALTER TABLE #{table} DISABLE KEYS")
    return true
  end

  def enable_keys(table)
    connect_db
    $cn.execute("ALTER TABLE #{table} DISABLE KEYS")
  end

  def commit_imported_recs(table, import_id)
    $cn.execute("UPDATE #{table} SET import_status = #{$options[:statuses]["completed"]} WHERE import_status = #{$options[:statuses]["inserted"]} AND import_batch_id = #{import_id}")
  end

end

#### IMPORTER HELPER MODULE #####
module ImporterHelpers

  def prt_dotted_line(txt="")
    prt "---------------------------------------------------------------------#{txt}"
  end
  
  # <cf_style>Rockin it!</cf_style> - count run time of  bounded block and output it
  def tickcount(id="", verbose=$options[:verbose], tracking=false)
    from = Time.now
    prt "\nSTART: " + (id =="" ? "Anonymous Block" : id) + "\n" if verbose
    yield
    to = Time.now
    # track time stats?
    if tracking
      $ticks = {} if !$ticks
      if !$ticks[id]
        $ticks[id] = {}
        $ticks[id][:times] = 1
        $ticks[id][:total] = Float(to-from)
      else
        $ticks[id][:times] = $ticks[id][:times] + 1
        $ticks[id][:total] = ( ($ticks[id][:total] + Float(to-from)) / $ticks[id][:times] )
      end
      $ticks[id][:last] = {:from => from, :to => to}
    end
    if verbose
      prt "END: " + (id =="" ? "Anonymous Block" : id) + " time taken: #{(to-from).to_s} s"
      prt_dotted_line
    end
    return true
  end
  
  # Sourced from ThinkingSphinx pluing by Pat Allan (http://freelancing-god.github.com)
  # A fail-fast and helpful version of "system"
  def system!(cmd)
    unless system(cmd)
      raise <<-SYSTEM_CALL_FAILED
  The following command failed:
    #{cmd}

  This could be caused by a PATH issue in the environment of Ruby.
  Your current PATH:
    #{ENV['PATH']}
SYSTEM_CALL_FAILED
    end
  end

  ## Append text to file using sed
  def append_text_to_file(text, filename)
    `sed -e '$a\\
#{text}' #{filename} > #{filename}.tmptmp`
    `cp #{filename}.tmptmp #{filename}` # CP to original file
    File.delete("#{filename}.tmptmp") # Delete temporary file
  end

  ## Prepend text to file using sed
  def prepend_text_to_file(text, filename)
    `sed -e '1i\\
#{text}' #{filename} > #{filename}.tmptmp`
    `cp #{filename}.tmptmp #{filename}` # CP to original file
    File.delete("#{filename}.tmptmp") # Delete temporary file
  end

  # "puts" clone that outputs nothing when verbose mode is false!
  def prt(str)
    puts(str) if $options[:verbose]
  end

  # exit quickly
  def ex
    exit
  end
  
  # Removes string and any duplicate spaces
  def replace_no_gaps(str, replace, with)
    return str.gsub(replace, with).gsub(/ +/, ' ').strip
  end

  def exit_with_error(error, dump_me=nil)
    puts "ERROR! " + error
    pp dump_me if dump_me
    exit
  end
  
  # Fetch "to" command line or set to default
  def get_cli_break_point
    if ENV.include?("to") && ENV['to'] && ENV['to'].to_i > 0
      return ENV['to'].to_i
    else
      return $options[:default_break_point]
    end
  end

  # Empty tables or not
  def get_cli_empty_tables
    return ( ENV.include?("kill") && ENV['kill'] )
  end

  # Silent or Not
  def get_silent
    return ( ENV.include?("silent") && ENV['silent'] )
  end

  # Fetch "start" from command line or set to default
  def get_cli_start_point
    if ENV.include?("from") && ENV['from'] && ENV['from'].to_i > 0
      return ENV['from'].to_i
    else
      return 1
    end
  end

  # Fetch "type" from command line or set to default
  def get_cli_type
    if ENV.include?("type") && ENV['type']
      return ENV['type'].to_s
    else
      return ""
    end
  end

  # Fetch "force" command from or set default
  def get_cli_forced
    if ENV.include?("force") && ENV['force']
      return true
    else
      return false
    end
  end

  # Fetch regex from command line or set to default
  def get_cli_regex
    if ENV.include?("rex")
      if ENV['rex'].scan(/\/.+\//)
        rex = Regexp.new ENV['rex'].scan(/\/(.+)\//).to_s
      else
        rex = ENV['rex']
      end
    else
      rex = $regexes[:antonym]
    end
    return rex
  end

  # Get debug directive from command line
  def get_cli_debug
    if ENV.include?("debug")
      if ENV["debug"] == "false" || ENV["debug"] == "0"
        $options[:verbose] = false
      else
        $options[:verbose] = true
      end
    else
      # default is on!
      $options[:verbose] = true
    end
  end

  # Get card type from command line
  def get_cli_card_type
    if ENV.include?("card_type") && ENV['card_type']
      card_type = $options[:card_types][ENV['card_type'].upcase]
      if card_type.nil?
        puts "Error, card type not recognised! See source for valid card types."
        exit
      end
    else
      card_type = $options[:card_types]['DICTIONARY']
    end
    return card_type.to_i
  end

  # Get extra tags specified at the command line
  def get_cli_tags
    if ENV.include?("add_tags") && ENV['add_tags']
      return ENV['add_tags'].downcase.split(',').collect {|s| s.strip }
    else
      return nil
    end
  end
  
  # Loop counter to count aloud for you!
  def noisy_loop_counter(count, max=0, every=1000, item_name="records", atomicity=1)
    count +=1
    if count % every == 0 || (max > 0 && count == max)
      prt "Looped #{count/atomicity} #{item_name}" if count%atomicity == 0 ## display count based on atomicity
    end
    return count
  end

  # Returns source file name specified at CLI or dies with error
  def get_cli_source_file
    if !ENV.include?("src") || ENV['src'].size < 1
      exit_with_error("Source file not found.", ENV)
    else
      return ENV['src'].to_s
    end
  end

  # Returns specified attrib from command, dies with error if fail_if_undefined == true
  def get_cli_attrib(attrib, fail_if_undefined=false, bool=false)
    if ENV.include?(attrib)
      if bool
        return (ENV[attrib] ==0 || ENV[attrib] == "true" ? true : false)
      else
        return ENV[attrib]
      end
    elsif fail_if_undefined
      exit_with_error("Command line attribute not found #{attrib} !", ENV) if fail_if_undefined
    end
  end

end