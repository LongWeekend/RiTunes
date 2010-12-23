##################################################
# RiTunes 0.5
##################################################

#
# Copyright 2010 Long Weekend LLC
# Written by paul [a.] t longwwekendmobile.com
# Please read see the README file
#

require 'rubygems'
require 'rake'

require 'mechanize'
require 'json'
require 'nokogiri'
require 'active_record'
require 'ruby-debug'

load File.dirname(__FILE__) + "/_ritunes-helpers.rb"

namespace :ritunes do

  include DatabaseHelpers
  include ImporterHelpers
  include RiHelpers

  ###
  ### This is where the magic happens
  ###
  desc "Run search against iTunes Search API"
  task :search do
    
    configure_ritunes
 
    # empty storage tables
    empty_logging_tables if get_cli_attrib('empty')

    # confirgure search params
    domain_keyword = ""
    keyword_stack = []
    keyword_stack_no_domain_kw = []

    src_file = get_cli_source_file
    if src_file != ""
      # Load param file from CLI
      load File.dirname(__FILE__) + "/" + src_file
      prt "Found source file #{src_file}"
    else
      # Default example search
      domain_keyword = "reader"
      keyword_stack = ["news", "rss", "blog", "newspaper", "magazine", "google"]
      keyword_stack_no_domain_kw = ["pulse", "flipboard"]
    end

    # load list of significant iTunes countries, add yours if not here
    country_arr = get_itunes_countries
   
    country_arr.each do |geo|

      # search and buffer
      results_array = []

      # get first x in keyword domain 
      results_array << search_itunes_public({ :term => domain_keyword, :country => geo, :limit => $options[:itunes_max_recs]  })

      # get first x in education
      results_array << search_itunes_public({ :term => "Education", :attribute => "genreTerm", :country => geo, :limit => $options[:itunes_max_recs] })

      #-------------------------------------
      # domain keyword + keyword from stack
      #-------------------------------------
      keyword_stack.each do |kw|

        # collect keywords
        kw_arr = []
        kw_arr << domain_keyword
        kw_arr << kw
        kw = get_mechanized_keywords_array(kw_arr)

        # search and buffer
        results_array << search_itunes_public({ :term =>kw, :country => geo, :limit => 1000})

      end

      #-------------------------------
      # non-domain keyword searches
      #-------------------------------
      keyword_stack_no_domain_kw.each do |kw|

        # search and buffer
        results_array << search_itunes_public({ :term =>kw, :country => geo, :limit => 1000})

      end

    end

  end


  ### The format returned by the Private API is intended for consumption by the iTunes binary only.
  ### The XML data is a bit of a helter-skelter mix of XML data, embedded HTML, etc... all very custom!
  ### Feel free to build your own parser and contribute it back to RiTunes.
  desc "Run search against iTunes Search API"
  task :search_private do
    
    configure_ritunes
    prt search_itunes_private({ :term => "Education", :genreIndex => 4, :limit => 100 })

  end

  ### You shouldn't need to call this very frequently!
  desc "Empty keyword_index table and re-inserts each keyword from past searches [Warning: Can Be Slow!]"
  task :reindex_keywords do
    configure_ritunes
    connect_db
    bulkSQL = BulkSQLRunner.new(0, 50000)
    $cn.execute('TRUNCATE TABLE keyword_index')
    $cn.execute("SELECT r.app_id, s.search_id, REPLACE(REPLACE(s.search_string, 'attribute=&entity=software&term=', ''), '+', ' ') AS keywords FROM searches s, rankings r WHERE r.search_id = s.search_id AND search_string NOT LIKE '%genreTerm%'").each do |app_id, search_id, keywords|
      keywords.split(" ").each do |kw|
        bulkSQL.add("INSERT IGNORE INTO keyword_index (app_id, keyword) VALUES (#{app_id}, '#{mysql_escape_str(kw)}');")
      end
    end
    bulkSQL.flush
    
  end

end