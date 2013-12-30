#!/usr/bin/ruby

# copy geoserver configuration from one directory to another, with support to 
# change a few important configuration options


require 'rexml/document'
require 'rexml/xpath'
require 'find'
require 'optparse'
require 'yaml'
require 'fileutils'



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


def trace_oid( oids, oid, depth, options, files, other_files )

  # recursively trace out the objects 
  # there may be more than one file that has the same id (eg layer.xml and gwc-layer) 
  oids[ oid].each() do |object|

    node = object[:xml]
    path = object[:path]

    if REXML::XPath.first( node, "/GeoServerTileLayer" )
      files['GeoServerTileLayer'] = object 
    elsif REXML::XPath.first( node, "/layer" )
      files['layer'] = object 
      # check for a content ftl file...

    elsif REXML::XPath.first( node, "/featureType" )
      files['featureType'] = object 
    elsif REXML::XPath.first( node, "/namespace" )
      files['namespace'] = object 
    elsif REXML::XPath.first( node, "/workspace" )
      files['workspace'] = object 
    elsif REXML::XPath.first( node, "/coverage" )
      files['coverage'] = object 
    elsif REXML::XPath.first( node, "/dataStore" )
      files['dataStore'] = object 
 
      # a dataStore with a reference to a shapefile or other geometry
      url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          abort( "missing file #{fullpath}") unless File.exists?( fullpath)
          # other files
          other_files << fullpath
        end
      end

    elsif REXML::XPath.first( node, "/style" )
      files['style'] = object

      # if it's a style with a ref to a stylefile 
      style_file = REXML::XPath.first( node, "/style/filename" )
      if style_file
        fullpath = "#{File.dirname( object[:path] )}/#{style_file.text}"
        # print "#{pad(depth + 1)} +STYLEFILE #{fullpath}" 
        abort( "missing file #{fullpath}") unless File.exists?( fullpath)

        other_files << fullpath
      end
    
    elsif REXML::XPath.first( node, "/coverageStore" )
      files['coverageStore'] = object

      url = REXML::XPath.first( node, "/coverageStore/url" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          abort( "missing file #{fullpath}") unless File.exists?( fullpath)
          other_files << fullpath
        end
      end

    else 
        abort( "#{pad(depth+1)} +UNKNOWN element #{path}"  )
    end

    # find the sub objects this doc refers to
    # and process them
    REXML::XPath.each( object[:xml], "/*/*/id" ) do |e|
      trace_oid( oids, e.text , depth + 1, options, files, other_files )
    end
  end
end


def relative_path( path, dir )
  # subtract dir from path to give relative path
  # TODO must be a better way!
  path1 = File.expand_path( path)
  dir = File.expand_path( dir )
  path1[dir.length, 1000000 ]
end


def begin_trace_from_layer_info( oids, options )

  # start tracing from the layer root keys
  oids.keys.each() do |oid|

    # only concerned with tracing from a layer
    next unless ( oid =~ /LayerInfoImpl.*/ )

    # limit scan to specific layer if specified in options
    if options[:layer]
      found = false
      oids[ oid].each() do |object|
        layer_name = REXML::XPath.first( object[:xml], "/layer/name" )
        found = layer_name && layer_name.text == options[:layer]
      end
      next unless found
    end


    # do the scan
    files = {} 
    other_files = []
    trace_oid( oids, oid, 0, options, files, other_files )

    puts "--------------"

    puts "layer name-> #{REXML::XPath.first( files['layer'][:xml], '/layer/name').text}    files: #{files.length}"


    # process the main xml files
    files.keys.each() do |key|

      src = files[key][:path]
      node = files[key][:xml]
      dest = options[:dest_dir] + relative_path( src, options[:source_dir] )

      # puts "#{key}->    #{src} -> #{dest}"

      ## Ensure we never overwrite a file in the target directory
      if File.exists?( dest)
        puts "already exists #{dest}"
      else

        # we make the conversion irrespective of the actual file names

        # patch jndi entry
        jndi = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='jndiReferenceName']") 
        if jndi and options[:jndi_reference]
          jndi.text = options[:jndi_reference]
          puts "jndi_reference now -> #{jndi.text}"
        end  

        # change workspace ref
        workspace_id = REXML::XPath.first( node, "//workspace/id") 
        if workspace_id and options[:workspace_id]
          workspace_id.text = options[:workspace_id]
          puts "workspace_id now -> #{workspace_id.text}"
        end  

        # change namespace ref
        namespace_id = REXML::XPath.first( node, "//namespace/id") 
        if namespace_id and options[:namespace_id]
          namespace_id.text = options[:namespace_id]
          puts "namespace_id now -> #{namespace_id.text}"
        end  

        puts "writing new xml #{src} -> #{dest}"

        FileUtils.mkdir_p(File.dirname(dest ))    

        File.open( dest,"w") do |data|
           data << node
        end
      end
    end


    # other support files
    other_files.each() do |path|
      src = path 
      dest = options[:dest_dir] + relative_path( src, options[:source_dir] )

      if File.exists?( dest)
        puts "already exists #{dest}"
      else
        puts "copying #{src} -> #{dest}"
        FileUtils.mkdir_p(File.dirname(dest ))    
        FileUtils.cp_r(src,dest)
      end
  end

  end
end




options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-s', '--directory NAME', 'source dir') { |v| options[:source_dir] = v }
  opts.on('-d', '--directory NAME', 'destination to copy to') { |v| options[:dest_dir] = v }
  opts.on('-l', '--directory NAME', 'layer') { |v| options[:layer] = v }
  opts.on('-j', '--directory NAME', 'jndi ref') { |v| options[:jndi_reference] = v }
  opts.on('-w', '--directory NAME', 'workspace id') { |v| options[:workspace_id] = v }
  opts.on('-n', '--directory NAME', 'namespace id') { |v| options[:namespace_id] = v }
end.parse!


begin_trace_from_layer_info( create_oid_mappings( options ), options ) 


