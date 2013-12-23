
# Script to trace out the references of a geoserver configuration directory 
# and output useful configuration data


require 'rexml/document'
require 'rexml/xpath'
require 'find'


require 'optparse'
require 'yaml'


def create_oid_mappings( geoserver_config_dir )

  # scan the directory and create a set of mappings from object references
  # to their paths and xml structure 

  # the list of geoserver object identifiers 
  oids = {} 

  Find.find( geoserver_config_dir  ) do |path|

    # only take xml files
    next unless FileTest.file?(path)
  #  next unless File.extname(path) == '.xml' or File.extname(path) == '.sld' 
    next unless File.extname(path) == '.xml'

    # puts "file #{path}"

    # get the id of the object represented by the file
    # this oid will be the first in the file
    file = File.new( path )
    doc = REXML::Document.new file
    oid = REXML::XPath.first( doc, "/*/id" )
    next unless oid 

    # puts " oid is #{oid.text}"

    # there are cases where same id will have several associated files 
    # eg. he gwc-layer id corresponds with the layer.xml file
    # so use a list
    if oids[ oid.text].nil? 
      oids[ oid.text ] = [ { doc: doc, path: path } ]
    else
      oids[ oid.text ] << { doc: doc, path: path }
    end
  end

  oids
end


def simple_format_object( object, depth)

  # format some common object types for pretty printing

  # pad recursion depth
  pad = ''
  depth.times do 
    pad  += '  '
  end

  puts "#{pad} #{object[:path]}"
end


def format_object( object, depth)

  # format some common object types for pretty printing

  # pad recursion depth
  pad = ''
  depth.times do 
    pad  += '  '
  end

  puts "#{pad} #{object[:path]}"

  if REXML::XPath.first( object[:doc], "/featureType" )
    ['title', 'enabled'].each do |x|
      puts "  #{pad} #{x} -> #{REXML::XPath.first( object[:doc], "//#{x}" ).text}"
    end
  end

  if REXML::XPath.first( object[:doc], "/layer" )
    ['name', 'type', 'enabled'].each do |x|
      puts "  #{pad} #{x} -> #{REXML::XPath.first( object[:doc], "//#{x}" ).text}"
    end
  end

  if REXML::XPath.first( object[:doc], "/namespace" )
    ['prefix'].each do |x|
      puts "  #{pad} #{x} -> #{REXML::XPath.first( object[:doc], "//#{x}" ).text}"
    end
  end

  if REXML::XPath.first( object[:doc], "/dataStore" )
    ['name','type'].each do |x|
      puts "  #{pad} #{x} -> #{REXML::XPath.first( object[:doc], "//#{x}" ).text}"
    end

    REXML::XPath.each( object[:doc], "/dataStore/connectionParameters/*" ) do |p|
      
      puts "  #{pad} #{p.text}"
    end
  end
end


def trace_oid( oids, oid, depth, &block )

  # recursively trace out the objects 
  # there may be more than one file that has the same id (eg layer.xml and gwc-layer) 
  oids[ oid].each() do |object|

    # call our block to perform the processing
    #yield object, depth
    block.call object, depth 

    # find the sub objects this doc refers to
    # and process them
    REXML::XPath.each( object[:doc], "/*/*/id" ) do |e|
      trace_oid( oids, e.text , depth + 1, &block )
    end
  end
end


def begin_trace_from_layer_info( oids, &block )

	# start tracing from the layer root keys
	oids.keys.each() do |oid|
	  next unless ( oid =~ /LayerInfoImpl.*/ )
	  trace_oid( oids, oid, 0, &block)
	end
end


### alright we should be passing the formatting or operation that we
### want to perform into the recursion.


dir = nil 
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-d', '--directory NAME', 'Directory name') { |v| dir = v }
  #opts.on('-h', '--sourcehost HOST', 'Source host') { |v| options[:source_host] = v }
end.parse!



begin_trace_from_layer_info( create_oid_mappings( dir ) ) do |object, depth|

  format_object( object, depth)
end

abort('finished') 





# file = File.new( "./geoserver-config/gwc-layers/LayerInfoImpl-6c033aa5_1407b759987_431a.xml" )
# doc = REXML::Document.new file
# 
# # this oid will be the first in the file
# oid = REXML::XPath.first( doc, "//*/id" ).text
# puts "oid is #{oid}"
# 
# puts "----------"
# 
# REXML::XPath.each( doc, "//GeoServerTileLayer/*") do  |e| 
#   puts "here #{e.name}" 
# 
# end 
# puts "finished"
# 


############ OLD

# Dir.foreach('./geoserver-config') do |item|
#   next if item == '.' or item == '..'
#   # do work on real items
# 
#   puts "item #{item}"
# 
#   if File.file?(item)
#     puts "  file"
#   end
# 
# end
# 

#oid = REXML::XPath.first( doc, "//GeoServerTileLayer/id" ).text

#REXML::XPath.each ( doc, "//GeoServerTileLayer" ) do |e| 

# REXML::XPath.each ( x, '//GeoServerTileLayer' ) do |e| 
# 
#   puts "e is #{e}"
# end
# 


# puts doc.elements["GeoServerTileLayer"].attributes["id"].text

# doc.elements.each('GeoServerTileLayer/*') do |ele|
#   puts "name -> #{ele.name}"
#   puts "  text -> #{ele.text}" unless ele.text.nil?
# end
# 


# require 'net/http'
# 
# # Web search for "madonna"
# url = 'http://api.search.yahoo.com/WebSearchService/V1/webSearch?appid=YahooDemo&query=madonna&results=2'
# 
# # get the XML data as a string
# xml_data = Net::HTTP.get_response(URI.parse(url)).body
# 
# # extract event information
# doc = REXML::Document.new(xml_data)
#
# doc.elements.each('ResultSet/Result/Url') do |ele|
#    links << ele.text
# end
# 
# # print all events
# titles.each_with_index do |title, idx|
#    print "#{title} => #{links[idx]}\n"
# end
# 


