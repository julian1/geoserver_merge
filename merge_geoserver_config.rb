#!/usr/bin/ruby

# tool to print, merge and patch geoserver layers

# Examples:
#
# print all layers 
# ./merge_geoserver_config.rb  -p -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/
#
# print layer 'JBmeteorological_data'
# ./merge_geoserver_config.rb  -p -l JBmeteorological_data -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/ 
#
# merge layer srs_occ into tmp
# ./merge_geoserver_config.rb -l srs_occ  -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/ -d tmp/
#
# merge layer srs_occ into tmp changing jndi reference
# ./merge_geoserver_config.rb -l srs_occ -j java:comp/env/jdbc/legacy    -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/ -d tmp/
#
# SRC=~/imos/services/imos_geoserver_config/geoserver.imos.org.au_data_dir/
# DEST=/home/meteo/imos/projects/chef/geoserver-123/
# LAYER=soop_sst_1min_vw
# ./merge_geoserver_config.rb -p -l $LAYER  -s $SRC
# ./merge_geoserver_config.rb -l $LAYER -s $SRC  -d $DEST -j java:comp/env/jdbc/legacy_read   -w WorkspaceInfoImpl-5f0a648d:1428d0d11a9:-8000 -n NamespaceInfoImpl-5f0a648d:1428d0d11a9:-7fff  
#
# Note this doesn't copy the workspace level ftl

# TODO 
# set the namespace and workspace from the destination directory 
# perhaps ability to change schema
# perhaps, should read the target namespace and target workspaces and use those entries by default.

# ok, we got comthing working 

require 'rexml/document'
require 'rexml/xpath'
require 'find'
require 'optparse'
require 'yaml'
require 'fileutils'


def relative_path( path, dir )
  # subtract dir from path to give relative path
  # TODO must be a better way!
  path1 = File.expand_path( path)
  dir = File.expand_path( dir )
  path1[dir.length, 1000000 ]
end


def maybe_abort( msg, options )
  abort( msg) unless options[:print]
  puts msg
end


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

      path2 = oids[ oid.text ].first[:path] 
      puts "duplicate object id #{relative_path(path, options[:source_dir])} (#{relative_path(path2, options[:source_dir])})" 

      oids[ oid.text ] << { xml: xml, path: path }
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
    elsif REXML::XPath.first( node, "/featureType" )
      files['featureType'] = object 
    elsif REXML::XPath.first( node, "/namespace" )
      files['namespace'] = object 
    elsif REXML::XPath.first( node, "/workspace" )
      files['workspace'] = object 
    elsif REXML::XPath.first( node, "/coverage" )
      files['coverage'] = object 

    elsif REXML::XPath.first( node, "/layer" )
      files['layer'] = object 

      # pick up ftl files in this dir 
      Dir["#{File.dirname( path)}/*.ftl"].each do |fullpath|
          other_files << fullpath
      end

    elsif REXML::XPath.first( node, "/dataStore" )
      files['dataStore'] = object 
 
      # a dataStore with a reference to a shapefile or other geometry
      url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)

          # glob other shapefiles that match the basename  eg. .shx, .dbf
          if File.extname( fullpath) == '.shp'
            fname = fullpath.chomp(File.extname(fullpath ) ) 
            # puts "***** it's a shapefile  basename #{fname} "
            Dir["#{fname}*"].each do |shapefile|
              other_files << shapefile
            end

          else
            # other file types
            other_files << fullpath
          end	

        end
      end

    elsif REXML::XPath.first( node, "/style" )
      files['style'] = object

      # if it's a style with a ref to a stylefile 
      style_file = REXML::XPath.first( node, "/style/filename" )
      if style_file
        fullpath = "#{File.dirname( object[:path] )}/#{style_file.text}"
        # print "#{pad(depth + 1)} +STYLEFILE #{fullpath}" 
        maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)
        other_files << fullpath

        # we also need to pick up any other resources used by the sld
        node = REXML::Document.new( File.new( fullpath )) 

        REXML::XPath.each( node, "//OnlineResource" ) do |e|
          resource_file = e.attributes["xlink:href"]
          fullpath = "#{options[:source_dir]}/styles/#{resource_file}"
          maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)
        	# puts "adding new resource #{fullpath}" 
          other_files << fullpath
        end
      end
    
    elsif REXML::XPath.first( node, "/coverageStore" )
      files['coverageStore'] = object

      url = REXML::XPath.first( node, "/coverageStore/url" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)
          other_files << fullpath
        end
      end

    else 
        maybe_abort( "ERROR: #{pad(depth+1)} +UNKNOWN element #{path}", options)
    end

    # find the sub objects this doc refers to
    # and process them
    REXML::XPath.each( object[:xml], "/*/*/id" ) do |e|
      trace_oid( oids, e.text , depth + 1, options, files, other_files )
    end
  end
end




## we really need to factor this into a block

def begin_trace_oids( oids, options )

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


    yield files, other_files

  end
end


def print_layer( options, files, other_files )

  # dump layer useful layer info to stdout

  name = REXML::XPath.first( files['layer'][:xml], '/layer/name')
  print "#{name.text}" if name

  namespace = REXML::XPath.first( files['namespace'][:xml], '/namespace/prefix')
  print ", ns->#{namespace.text}" if namespace

  workspace = REXML::XPath.first( files['workspace'][:xml], '/workspace/name')
  print ", ws->#{workspace.text}" if workspace

  if files['style'][:xml]
    node = files['style'][:xml]
    style = REXML::XPath.first( node, '/style/name')
    style_file = REXML::XPath.first( node, "/style/filename" )
    print ", style->#{style.text}" if style
#    print ", stylefile->#{style_file.text}" if style_file
  end

  if files['dataStore']
    node = files['dataStore'][:xml]

    jndi = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='jndiReferenceName']") 
    print ", jndiref->#{jndi.text}" if jndi

    schema = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='schema']") 
    print ", schema->#{schema.text}" if schema

    url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
    print ", url->#{url.text}" if url
  end

  if files['coverageStore']
    node = files['coverageStore'][:xml]

    url = REXML::XPath.first( node, "/coverageStore/url" )
    print ", coverage_url->#{url.text}" if url
  end

  print ", files: #{files.length} others: #{other_files.length}"
  puts
end



def copy_layer( options, files, other_files )

  puts "--------------"
  print_layer( options, files, other_files )

  # loop the main xml files associated with layer
  files.keys.each() do |key|

    src = files[key][:path]
    node = files[key][:xml]
    rel_src = relative_path( src, options[:source_dir] )
    dest = options[:dest_dir] + rel_src

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
        puts "change jndi_reference -> #{jndi.text}"
      end  

      # patch workspace ref
      workspace_id = REXML::XPath.first( node, "//workspace/id") 
      if workspace_id and options[:workspace_id]
        workspace_id.text = options[:workspace_id]
        puts "change workspace_id -> #{workspace_id.text}"
      end  

      # patch namespace ref
      namespace_id = REXML::XPath.first( node, "//namespace/id") 
      if namespace_id and options[:namespace_id]
        namespace_id.text = options[:namespace_id]
        puts "change namespace_id -> #{namespace_id.text}"
      end  

      puts "writing xml #{rel_src} -> #{dest}"

      FileUtils.mkdir_p(File.dirname(dest ))    

      File.open( dest,"w") do |data|
         data << node
      end
    end
  end


  # copy other support files
  other_files.each() do |path|
    src = path 
    rel_src = relative_path( src, options[:source_dir] )
    dest = options[:dest_dir] + rel_src

    if File.exists?( dest)
      puts "already exists #{dest}"
    else
      puts "copying #{rel_src} -> #{dest}"
      FileUtils.mkdir_p(File.dirname(dest ))    
      FileUtils.cp_r(src,dest)
    end
  end
end



def create_monitoring_databag( options, files, other_files )

  # dump layer useful layer info to stdout

  # it would probably be good to sort this alphabetically. 

  # and it would be nice to use join() to generate the comma list 
  # 

  namespace = REXML::XPath.first( files['namespace'][:xml], '/namespace/prefix')
  abort( "missing namespace" ) unless namespace

  name = REXML::XPath.first( files['layer'][:xml], '/layer/name')
  abort( "missing name" ) unless name

  type = /_data$/.match( name.text ) ? "wfs" : "wms"

  # Just use EOS to create the string, then use join()
 
  pad = "    " 

  bag = <<-EOS
      #{pad}{
      #{pad}"namespace": "#{namespace.text}"
      #{pad}"name": "#{name.text}"
      #{pad}"type": "#{type}" 
      #{pad}},
  EOS

  puts bag

# we could spec

 
#   if files['coverageStore']
#     node = files['coverageStore'][:xml]
# 
#     url = REXML::XPath.first( node, "/coverageStore/url" )
#     print ", coverage_url->#{url.text}" if url
#   end
# 

# we should pass the files in then sort by type, and then name. 
# to keep ordering. 
# or have two methods/functions to implement this.



end




options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-s', '--src_directory NAME', 'source dir') { |v| options[:source_dir] = v }
  opts.on('-d', '--dest_directory NAME', 'destination to copy to') { |v| options[:dest_dir] = v }
  opts.on('-l', '--layer NAME', 'specific layer - otherwise all layers') { |v| options[:layer] = v }
  opts.on('-j', '--jndirref NAME', 'change jndi ref') { |v| options[:jndi_reference] = v }
  opts.on('-w', '--workspace NAME', 'change workspace id') { |v| options[:workspace_id] = v }
  opts.on('-n', '--namespace NAME', 'change namespace id') { |v| options[:namespace_id] = v }

# we want this thing to be a boolean ...
  opts.on('-p', '', 'print to stdout') { |v| options[:print] = true }
  opts.on('-b', '', 'create databag to stdout') { |v| options[:bag] = true }
end.parse!


layers = []

begin_trace_oids( create_oid_mappings( options ), options ) do  |files, other_files|

  ## ok, a simple list is sufficient -
  ## and then a predicate sorting operation ... 

  # extract some common fields common to all layers
  namespace = REXML::XPath.first( files['namespace'][:xml], '/namespace/prefix')
  abort( "missing namespace" ) unless namespace

  name = REXML::XPath.first( files['layer'][:xml], '/layer/name')
  abort( "missing name" ) unless name

  type = /_data$/.match( name.text ) ? "wfs" : "wms"

  layers << {   
    name: name.text,
    namespace: namespace.text,
    type: type,
    files: files, 
    other_files: other_files 
  }

end 



if options[:bag]

  layers.sort! do |a,b| 
    # put wms before wfs else sort by name
    if a[:type] != b[:type] 
      b[:type] <=> a[:type] 
    else
      a[:name].downcase <=> b[:name].downcase 
    end
  end

  # ok, now I think that we want the main loop inside the creation
  # function so that we can output more easily.
  layers.each() do |layer|

    create_monitoring_databag( options, layer[:files], layer[:other_files] )
  end
end







