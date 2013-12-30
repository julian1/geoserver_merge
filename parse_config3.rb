#!/usr/bin/ruby

# Script to trace out the references of a geoserver configuration directory 
# and output useful configuration data

# This ought to make it easy to copy all needed files in one operation. 
# And to patch-up workspace and namespace references and jndi entries etc 

require 'rexml/document'
require 'rexml/xpath'
require 'find'


require 'optparse'
require 'yaml'


def create_oid_mappings( options)

  # scan the directory and create a set of mappings from object references
  # to their paths and xml structure 

  # the list of geoserver object identifiers 
  oids = {} 

  Find.find( options[:source_dir] ) do |path|

    # only take xml files
    next unless FileTest.file?(path)
    next unless File.extname(path) == '.xml'

    # puts "file #{path}"

    # get the id of the object represented by the file
    # this oid will be the first in the file
    file = File.new( path )
    xml = REXML::Document.new file
    oid = REXML::XPath.first( xml, "/*/id" )
    next unless oid 

    # puts " oid is #{oid.text}"

    # there are cases where same id will have several associated files 
    # eg. he gwc-layer id corresponds with the layer.xml file
    # so use a list
    if oids[ oid.text].nil? 
      oids[ oid.text ] = [ { xml: xml, path: path } ]
    else
      oids[ oid.text ] << { xml: xml, path: path }
      puts "duplicate object id #{path}   (#{oids[ oid.text ].first[:path]  })" 
    end
  end
  oids
end


def trace_oid( oids, oid, depth, options, lst )

  # recursively trace out the objects 
  # there may be more than one file that has the same id (eg layer.xml and gwc-layer) 
  oids[ oid].each() do |object|

    node = object[:xml]
    path = object[:path]

    if REXML::XPath.first( node, "/GeoServerTileLayer" )
      lst['GeoServerTileLayer'] = object 
    elsif REXML::XPath.first( node, "/layer" )
      lst['layer'] = object 
    elsif REXML::XPath.first( node, "/featureType" )
      lst['featureType'] = object 
    elsif REXML::XPath.first( node, "/namespace" )
      lst['namespace'] = object 
    elsif REXML::XPath.first( node, "/workspace" )
      lst['workspace'] = object 
    elsif REXML::XPath.first( node, "/coverage" )
      lst['coverage'] = object 
    elsif REXML::XPath.first( node, "/dataStore" )
      lst['dataStore'] = object 
 
      # a dataStore with a reference to a shapefile or other geometry
      url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          abort( "missing file #{fullpath}") unless File.exists?( fullpath)
          lst['dataStore:file'] = { path: fullpath } 
        end
      end

    elsif REXML::XPath.first( node, "/style" )
      lst['style'] = object

      # if it's a style with a ref to a stylefile 
      style_file = REXML::XPath.first( node, "/style/filename" )
      if style_file
        fullpath = "#{File.dirname( object[:path] )}/#{style_file.text}"
        # print "#{pad(depth + 1)} +STYLEFILE #{fullpath}" 
        abort( "missing file #{fullpath}") unless File.exists?( fullpath)
        lst['style:file'] = { path: fullpath }
      end
    
    elsif REXML::XPath.first( node, "/coverageStore" )
      lst['coverageStore'] = object

      url = REXML::XPath.first( node, "/coverageStore/url" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          abort( "missing file #{fullpath}") unless File.exists?( fullpath)
          lst['coverageStore:file'] = { path: fullpath } 
        end
      end

    else 
        abort( "#{pad(depth+1)} +UNKNOWN element #{path}"  )
    end

    # find the sub objects this doc refers to
    # and process them
    REXML::XPath.each( object[:xml], "/*/*/id" ) do |e|
      trace_oid( oids, e.text , depth + 1, options, lst )
    end
  end
end


### would it make sense to return the list of objects
### we are interested in scanning from rather than
### everything.

def begin_trace_from_layer_info( oids, options )

  # start tracing from the layer root keys
  oids.keys.each() do |oid|
    next unless ( oid =~ /LayerInfoImpl.*/ )
    lst = { } 
    trace_oid( oids, oid, 0, options, lst )

    print "--------------"
    print "files #{lst.length}, "

#     lst.keys.each() do |key|
#       print "#{key}->#{lst[key]}"
#     end
# 

    print "name-> #{REXML::XPath.first( lst['layer'][:xml], '/layer/name').text}, "

    # we want to consolidate this logic

    # this complicated stuff is because it's sometimes malformed
    if lst['dataStore'] 
      dataStoretype = REXML::XPath.first( lst['dataStore'][:xml], '/dataStore/type')
      if dataStoretype and dataStoretype.text == 'PostGIS (JNDI)'
        print "jndi type "
      else
        print "**NON jndi type "
      end
    end
    puts

    ### so we could actually edit everything here ... 
    ### changing the workspace,namespace, vector styles here.

    ## we would copy the files according to type ... 
    ### while editing the xml. 

  end
end



### alright we should be passing the formatting or operation that we
### want to perform into the recursion.



options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-s', '--directory NAME', 'source dir to scan') { |v| options[:source_dir] = v }
  opts.on('-d', '--directory NAME', 'destination dir') { |v| options[:dest_dir] = v }
end.parse!


begin_trace_from_layer_info( create_oid_mappings( options ), options ) 


puts ""

