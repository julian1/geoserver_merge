
# http://rubydoc.info/gems/pg/0.10.0/frames

require 'pg'
require 'rexml/document'
require 'rexml/xpath'

conn = PG::Connection.open(:host => 'localhost', :port => 15432, :dbname => 'geonetwork', :user => 'postgres', :password => 'postgres' )

#res = conn.exec("SELECT * from metadata where uuid = 'ada98f4d-5489-4db5-98dd-6dc52d0fadf6' ;")
res = conn.exec("SELECT * from metadata;")


res.each do |row| 

  puts "-----------"

  row.each do |col|
    next if col.first == 'data'
    puts "#{col} "  
  end

  puts row['data']

  node = REXML::Document.new row['data']

  #REXML::XPath.each( node, "//gmd:CI_OnlineResource/gmd:name/gco:CharacterString" ) do |what|
  REXML::XPath.each( node, "//gmd:onLine/gmd:CI_OnlineResource/" ) do |what|
   
    puts "-----"
 
    name = REXML::XPath.first( what , "gmd:name/gco:CharacterString" ) 
    puts "name #{name.text}" if name

    link = REXML::XPath.first( what , "gmd:linkage/gmd:URL" ) 
    puts "link #{link.text}" if link

    desc = REXML::XPath.first( what , "gmd:description/gco:CharacterString" ) 
    puts "desc #{desc.text}" if desc

  end

#  
#   oid = REXML::XPath.first( node, "//gmd:fileIdentifier/gco:CharacterString" )
#   puts "identifier #{oid.text}" if oid
#   puts "missing identifier" unless oid
# 

end 

#puts res[2]['data']

#    <gmd:fileIdentifier>
#     <gco:CharacterString xmlns:srv="http://www.isotc211.org/2005/srv">053b7f20-972d-11dc-893b-00188b4c0af8</gco:CharacterString>
# 

#x = []
#puts "res.length #{x.count}"
 

#res = conn.exec_params('SELECT 1;')
# require "postgres"
# conn = PGconn.connect("localhost", 5432, "", "", "test1" )
# 

