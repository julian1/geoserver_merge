#!/usr/bin/ruby

# tool to print, merge, and generate chef/nagios databags for geoserver layers

# Examples:
#
# print all layers 
# ./merge_geoserver_config.rb  -p -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/
#
# print layer 'JBmeteorological_data'
# ./merge_geoserver_config.rb  -p -l JBmeteorological_data -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/ 
#
# rename a layer leaving schema name unchanged
# ./merge_geoserver_config.rb  -s $SRC  -l argo_platform_nominal_cycle -r argo_platform_nominal_cycle_data
#
# merge layer srs_occ into tmp
# ./merge_geoserver_config.rb -m -l srs_occ  -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/ -d tmp/
#
# merge layer srs_occ into tmp changing jndi reference
# ./merge_geoserver_config.rb -m -l srs_occ -j java:comp/env/jdbc/legacy    -s ../imos_geoserver_config/geoserver.imos.org.au_data_dir/ -d tmp/
#
# SRC=~/imos/services/imos_geoserver_config/geoserver.imos.org.au_data_dir/
# DEST=/home/meteo/imos/projects/chef/geoserver-123/
# LAYER=soop_sst_1min_vw
# ./merge_geoserver_config.rb -p -l $LAYER -s $SRC
# ./merge_geoserver_config.rb -m -l $LAYER -s $SRC  -d $DEST -j java:comp/env/jdbc/legacy_read   -w WorkspaceInfoImpl-5f0a648d:1428d0d11a9:-8000 -n NamespaceInfoImpl-5f0a648d:1428d0d11a9:-7fff  
#
# Note this doesn't copy the workspace level ftl




# TODO 

# change name geoserver_config_tool
# remove the layer selection from the scanning of oids
# see if we can make the -rename take two arguments 
# tidy documentation


# dump duplicate objects to stderr to avoid corrupting databag

# read the namespace and workspace from the destination directory - to allow text overide 
# ability to ignore if the layer is disabled
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

  nativeName = REXML::XPath.first( files['featureType'][:xml], '/featureType/nativeName')
  print ", nativeName->#{nativeName.text}" if nativeName

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


def print_short_layer( options, files, other_files )

  # dump layer useful layer info to stdout
  name = REXML::XPath.first( files['layer'][:xml], '/layer/name')
  print "#{name.text}" if name

  namespace = REXML::XPath.first( files['namespace'][:xml], '/namespace/prefix')
  print ", #{namespace.text}" if namespace

  workspace = REXML::XPath.first( files['workspace'][:xml], '/workspace/name')
  print ", #{workspace.text}" if workspace

  nativeName = REXML::XPath.first( files['featureType'][:xml], '/featureType/nativeName')
  print ", #{nativeName.text}" if nativeName

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

#  print ", files: #{files.length} others: #{other_files.length}"
  puts
end




def merge_layer( options, files, other_files )

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




def create_monitoring_databag( options, layers )
  
  # Generate a json databag for nagios monitoring of geoserver layers.

  layers.sort! do |a,b| 
    # put wms before wfs and sort by name
    if a[:type] != b[:type] 
      b[:type] <=> a[:type] 
    else
      a[:name].downcase <=> b[:name].downcase 
    end
  end

  # Generate the text for each layer
  items = []
  layers.each() do |layer|
    item = <<-EOS
        {
            "type": "#{layer[:type]}",
            "namespace": "#{layer[:namespace]}",
            "name": "#{layer[:name]}",
            "crit_timeout": 12,
            "warn_timeout": 6
        }
    EOS
    item = item.chomp
    items << item
  end

  databag = <<-EOS
{
    "id": "geoserver_rc",
    "url": "http://geoserver-rc.aodn.org.au/geoserver",
    "layers":
    [
#{items.join( ",\n")}
    ]
}   
  EOS
  puts databag
end




def rename_layer( options, files, other_files )

  puts "--------------"
  # remove a layer and featureType - leave the nativeName which refers to the schema

  layer_name = REXML::XPath.first( files['layer'][:xml], '//layer/name')
  abort( ) unless layer_name
  puts "rename #{layer_name.text} to #{options[:rename]}"

  featureType_name = REXML::XPath.first( files['featureType'][:xml], '//featureType/name')
  abort( ) unless featureType_name 
  featureType_title = REXML::XPath.first( files['featureType'][:xml], '//featureType/title')
  abort( ) unless featureType_title

  # we have to be careful with the order of these operations.
#  puts "title text '#{featureType_title.text}' layer name '#{layer_name.text}'" 

  if featureType_title.text == layer_name.text 
    puts "Updating title text from '#{featureType_title.text}' to name '#{options[:rename]}'" 
    featureType_title.text = options[:rename]
  else
    puts "Leaving title as '#{featureType_title.text}'" 
  end

  layer_name.text = options[:rename]
  featureType_name.text = options[:rename]



  File.open( files['featureType'][:path], "w") do |data|
    data << files['featureType'][:xml]
  end

  File.open( files['layer'][:path], "w") do |data|
    data << files['layer'][:xml]
  end
end



def remove_layer( options, layers )

  # the only tricky bit here is to avoid removing files when
  # they are referenced by more than one layer. eg. common dataStores
  # and style files 

  puts "remove layer #{options[:remove]}"
  abort( 'do not -x remove with use -l option') if options[:layer] 

  # build a a record of file counts
  counts = {}
  layers.each() do |layer|

    # do normal files
    layer[:files].each() do |key,val|
      path = val[:path]
      # puts "path #{path}"
      counts[path] = 0 if counts[path] == nil
      counts[path] += 1
    end
    # other files
    layer[:other_files].each() do |path|
      # puts "other file #{path}"
      counts[path] = 0 if counts[path] == nil
      counts[path] += 1
    end
  end

#   #
#   counts.each() do |file,count|
#     puts "#{count} #{file}"
#   end
# 
  # find the layer to remove
  layer = layers.select { |layer| layer[:name] == options[:remove] } .first 
  abort( "couldn't find layer #{options[:remove]}") if layer.nil?

  # collect up removal candidate files for the layer
  candidates = []
  layer[:files].each() do |key,val|
    candidates << val[:path]
  end  
  layer[:other_files].each() do |path|
    candidates << path
  end 

  # select where there's only one reference to the file
  to_remove = candidates.select { |path| counts[path] == 1 } 

  to_remove.each() do |path|
    puts "to remove #{path}"
  end

  FileUtils.rm( to_remove )

end


# process the options
options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
# we want this thing to be a boolean ...
  opts.on('-p', '', 'print to stdout') { |v| options[:print] = true }
  opts.on('-2', '', 'print with short format to stdout') { |v| options[:print2] = true }
  opts.on('-b', '', 'create databag to stdout') { |v| options[:databag] = true }
  opts.on('-m', '', 'merge geoserver config') { |v| options[:merge] = true }
  opts.on('-r', '', '--rename NAME') { |v| options[:rename] = v }
  opts.on('-x', '', '--remove NAME') { |v| options[:remove] = v }

  opts.on('-s', '--src_directory NAME', 'source dir') { |v| options[:source_dir] = v }
  opts.on('-d', '--dest_directory NAME', 'destination to copy to') { |v| options[:dest_dir] = v }

  opts.on('-l', '--layer NAME', 'specific layer - otherwise all layers') { |v| options[:layer] = v }
  ## opts.on('-f', '--layer NAME', 'get layers to process from a list') { |v| options[:layer] = v }

  opts.on('-j', '--jndirref NAME', 'change jndi ref') { |v| options[:jndi_reference] = v }
  opts.on('-w', '--workspace NAME', 'change workspace id') { |v| options[:workspace_id] = v }
  opts.on('-n', '--namespace NAME', 'change namespace id') { |v| options[:namespace_id] = v }

end.parse!


layers = []

begin_trace_oids( create_oid_mappings( options ), options ) do  |files, other_files|

  # Gather up a list of layers with their resources to ease processing

  # validate required files.
  # this logic needs to be improved. 
	abort( "missing namespace file") unless files['namespace']
	abort( "missing layer file") unless files['layer']
	abort( "missing featureType or coverage file") unless files['featureType'] or files['coverage'] 
	abort( "missing dataStore file") unless files['dataStore']
	abort( "missing workspace file") unless files['workspace']

#    elsif REXML::XPath.first( node, "/workspace" )
#    elsif REXML::XPath.first( node, "/coverage" )
#    elsif REXML::XPath.first( node, "/layer" )

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


if options[:databag]
  create_monitoring_databag( options, layers )

elsif options[:rename]
  abort( 'can only rename one layer at a time!!') unless layers.length == 1
  rename_layer( options, layers.first[:files], layers.first[:other_files] )

elsif options[:remove]
  remove_layer( options, layers ) 

elsif options[:print] or options[:print2]
  # sort 
  layers.sort! do |a,b| 
    a[:name].downcase <=> b[:name].downcase 
  end
  # and print to stdout
  layers.each() do |layer|
    print_layer( options, layer[:files], layer[:other_files] ) if options[:print]
    print_short_layer( options, layer[:files], layer[:other_files] ) if options[:print2]
  end

elsif options[:merge]
  layers.each() do |layer|
    merge_layer( options, layer[:files], layer[:other_files] )
  end
end


