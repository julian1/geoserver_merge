
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
    # next unless File.extname(path) == '.xml' or File.extname(path) == '.sld' 
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


## we may want to keep a hash through the recursion to keep track of
## whether we've already looked at a node.


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


### would it make sense to return the list of objects
### we are interested in scanning from rather than
### everything.

def begin_trace_from_layer_info( oids, &block )

	# start tracing from the layer root keys
	oids.keys.each() do |oid|
	  next unless ( oid =~ /LayerInfoImpl.*/ )
	  trace_oid( oids, oid, 0, &block)
	end
end


def trace_specific_layer( oids, name, &block )

	# loop all keys 
	oids.keys.each() do |oid|
    next unless ( oid =~ /LayerInfoImpl.*/ )
    # loop all objects associated with each key
    oids[ oid].each() do |object|
      # try to extract a layername
      layer_name = REXML::XPath.first( object[:doc], "/layer/name" )
      # puts "layer name -> '#{layer_name.text}',  name ->  '#{name}'"

      if layer_name && layer_name.text == name
        # got a match, so use recusive scan
        puts "found match for '#{layer_name.text}'!"
        trace_oid( oids, oid, 0, &block)
      end
    end
	end
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


def format_object_node( node, fields )
  print "{"
  g = []
  fields.each do |x|
    subnode = REXML::XPath.first( node, "//#{x}" )
    if subnode
      g << "#{x}->#{REXML::XPath.first( node, "//#{x}" ).text}"
    else
      g << "MISSING"
    end
  end
  print g.join( ", ")
  print "}"
end


def format_object_tree( object, depth)

  # format some common object types for pretty printing
  # pad recursion depth
  pad = ''
  depth.times do 
    pad += '  '
  end

  print "#{pad} #{object[:path]} "
  node = object[:doc]
  if REXML::XPath.first( node, "/layer" )
    format_object_node( node, ['name', 'type', 'enabled'] )
  elsif REXML::XPath.first( node, "/featureType" )
    format_object_node( node, ['title', 'enabled'] )
  elsif REXML::XPath.first( node, "/namespace" )
    format_object_node( node, ['prefix'] )
  elsif REXML::XPath.first( node, "/dataStore" )
    format_object_node( node, ['name','type'] ) 
    print "{"
    g = []
    REXML::XPath.each( node, "/dataStore/connectionParameters/*" ) do |p|
      if [ 'jndiReferenceName', 'schema'].include? ( p.attributes['key'] ) 
        g << "#{p.attributes['key']}->#{p.text}"
      end
    end
    print g.join( ", ")
    print "}"
  end

  puts ""
end


def format_object_one_line( object, depth)

  # format some common object types for pretty printing
  # pad recursion depth
  node = object[:doc]
  if REXML::XPath.first( node, "/layer" )
    puts ""
    format_object_node( node, ['name', 'type', 'enabled'])
  elsif REXML::XPath.first( node, "/featureType" )
    format_object_node( node, ['title', 'enabled'] ) 
  elsif REXML::XPath.first( node, "/namespace" )
    format_object_node( node, ['prefix'] ) 
  elsif REXML::XPath.first( node, "/dataStore" )
    format_object_node( node, ['name','type'] ) 
    print "{"
    g = []
    REXML::XPath.each( node, "/dataStore/connectionParameters/*" ) do |p|
      if [ 'jndiReferenceName', 'schema'].include? ( p.attributes['key'] ) 
        g << "#{p.attributes['key']}->#{p.text}"
      end
    end
    print g.join( ", ")
    print "}"
  end
end





### alright we should be passing the formatting or operation that we
### want to perform into the recursion.


require 'optparse'

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-d', '--directory NAME', 'Geoserver config directory to scan') { |v| options[:dir] = v }
  opts.on('-l', '--layer NAME', 'dump specific layer name') { |v| options[:layer] = v }
  opts.on("-v", "--[no-]verbose", "Dump paths recursively") { |v| options[:verbose] = v } 
end.parse!

if options[:layer]

  puts "looking for layer '#{options[:layer]}'" 

  trace_specific_layer( create_oid_mappings( options[:dir] ), options[:layer]) do |object, depth|
    if options[:verbose]
        format_object_tree( object, depth)
    else
        format_object_one_line( object, depth)
    end
  end
else 

  begin_trace_from_layer_info( create_oid_mappings( options[:dir] ) ) do |object, depth|
    if options[:verbose]
      format_object_tree( object, depth)
    else
      format_object_one_line( object, depth)
    end
  end
end
   

puts ""

