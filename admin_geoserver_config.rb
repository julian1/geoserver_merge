#!/usr/bin/ruby
#
# Tool to print, merge, and generate chef/nagios databags for geoserver layers
#
# Examples:
#
# SRC=~/imos/services/imos_geoserver_config/geoserver.imos.org.au_data_dir/
# DEST=/home/meteo/imos/projects/chef/geoserver-123/
# LAYER=soop_sst_1min_vw
#
# print all layers
# ./admin_geoserver_config.rb -s $SRC -p
#
# print layer 'JBmeteorological_data' (MAY WANT TO REMOVE AND JUST USE GREP or OPTION SPECIFIC_
# ./admin_geoserver_config.rb -s $SRC -p -l JBmeteorological_data
#
# rename a layer leaving schema, source table etc unchanged
# ./admin_geoserver_config.rb -s $SRC -r xbt_realtime,zzz
#
# merge layer srs_occ into directory tmp
# ./admin_geoserver_config.rb -m -l srs_occ -s $SRC -d tmp/
#
# merge layer srs_occ into tmp changing jndi reference
# ./admin_geoserver_config.rb -m -l srs_occ -j java:comp/env/jdbc/legacy  -s $SRC -d tmp/
#
# merge changing workspace ids to match Dest workspace ids
# ./admin_geoserver_config.rb -m -l $LAYER -s $SRC  -d $DEST -j java:comp/env/jdbc/legacy_read   -w 1234 -n 5678 
#
# Note merging doesn't copy the workspace level ftl
#




# TODO

# should rename gsobjects to objects. because they are not really gsobjects but aggregated xml 

# - Suppress printing of duplicate oids when it's the gwc and the layer.
  # dump duplicate objects to stderr to avoid corrupting databag

# - change name geoserver_config_tool
# - see if we can make the -rename take two arguments
# - tidy documentation


# - read the namespace and workspace from the destination directory - to allow text overide
# - ability to ignore if the layer is disabled
# - perhaps ability to change schema
# - perhaps, should read the target namespace and target workspaces and use those entries by default.


require 'rexml/document'
require 'rexml/xpath'
require 'find'
require 'optparse'
require 'yaml'
require 'fileutils'


def relative_path( path, subpath )
  # subtract subpath from path to give relative path
  # TODO must be a better way!
  path = File.expand_path( path)
  subpath = File.expand_path( subpath )
  abort( "subpath isn't in path") unless path.index( subpath) == 0
  path[subpath.length, 10000000]
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

    # only take normal regular xml gsobjects
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
    # may be multiple gsobjects with same id. eg. gwc-layer and layer 
    if oids[ oid.text].nil?
      oids[ oid.text ] = [ { xml: xml, path: path } ]
    else
      oids[ oid.text ] << { xml: xml, path: path }
    end
  end
  oids
end


def print_duplicate_oids( oids, options)

  # select oids with more than one file
  oids_with_multiple_files = oids.keys.select() do |oid|
    oids[ oid].length > 1
  end

  # ignore duplicates between global web cache, and layer which are expected to match. 
  oids_with_multiple_files = oids_with_multiple_files.delete_if() do |oid|
      oids[ oid].length == 2 \
      and \
      (REXML::XPath.first( oids[ oid].at( 0)[:xml], "/layer" )\
        and REXML::XPath.first( oids[ oid].at( 1)[:xml], "/GeoServerTileLayer" )) or\
      (REXML::XPath.first( oids[ oid].at( 1)[:xml], "/layer" )\
        and REXML::XPath.first( oids[ oid].at( 0)[:xml], "/GeoServerTileLayer" ))
  end

  # print them
  oids_with_multiple_files.each() do |oid|
    print "Dupliate id #{oid} "
    oids[ oid].each() do |object|
      print " #{relative_path( object[:path], options[:source_dir])} "
    end
    puts
  end
end


def trace_oid( oids, oid, depth, options, gsobjects, other_gsobjects )

  # recursively trace out the objects
  # there may be more than one file that has the same id (eg layer.xml and gwc-layer)
  oids[ oid].each() do |object|

    node = object[:xml]
    path = object[:path]

    if REXML::XPath.first( node, "/GeoServerTileLayer" )
      gsobjects['GeoServerTileLayer'] = object
    elsif REXML::XPath.first( node, "/featureType" )
      gsobjects['featureType'] = object
    elsif REXML::XPath.first( node, "/namespace" )
      gsobjects['namespace'] = object
    elsif REXML::XPath.first( node, "/workspace" )
      gsobjects['workspace'] = object
    elsif REXML::XPath.first( node, "/coverage" )
      gsobjects['coverage'] = object
    elsif REXML::XPath.first( node, "/layer" )
      gsobjects['layer'] = object
      # pick up ftl gsobjects in this dir
      Dir["#{File.dirname( path)}/*.ftl"].each do |fullpath|
          other_gsobjects << fullpath
      end
    elsif REXML::XPath.first( node, "/dataStore" )
      gsobjects['dataStore'] = object
      # a dataStore with a reference to a shapefile or other geometry
      url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ )
        if not x.empty?
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)

          # glob other shapegsobjects that match the basename  eg. .shx, .dbf
          if File.extname( fullpath) == '.shp'
            fname = fullpath.chomp(File.extname(fullpath ) )
            # puts "***** it's a shapefile  basename #{fname} "
            Dir["#{fname}*"].each do |shapefile|
              other_gsobjects << shapefile
            end
          else
            # other file types
            other_gsobjects << fullpath
          end
        end
      end
    elsif REXML::XPath.first( node, "/style" )
      gsobjects['style'] = object
      # if it's a style with a ref to a stylefile
      style_file = REXML::XPath.first( node, "/style/filename" )
      if style_file
        fullpath = "#{File.dirname( object[:path] )}/#{style_file.text}"
        # print "#{pad(depth + 1)} +STYLEFILE #{fullpath}"
        maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)
        other_gsobjects << fullpath

        # we also need to pick up any other resources used by the sld
        node = REXML::Document.new( File.new( fullpath ))

        REXML::XPath.each( node, "//OnlineResource" ) do |e|
          resource_file = e.attributes["xlink:href"]
          fullpath = "#{options[:source_dir]}/styles/#{resource_file}"
          maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)
        	# puts "adding new resource #{fullpath}"
          other_gsobjects << fullpath
        end
      end
    elsif REXML::XPath.first( node, "/coverageStore" )
      gsobjects['coverageStore'] = object

      url = REXML::XPath.first( node, "/coverageStore/url" )
      if url
        # print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ )
        if not x.empty?
          fullpath = "#{options[:source_dir]}/#{x.first().first() }"
          maybe_abort( "ERROR: missing file #{fullpath}", options) unless File.exists?( fullpath)
          other_gsobjects << fullpath
        end
      end
    else
        maybe_abort( "ERROR: #{pad(depth+1)} +UNKNOWN element #{path}", options)
    end

    # find the sub objects this doc refers to
    # and process them
    REXML::XPath.each( object[:xml], "/*/*/id" ) do |e|
      trace_oid( oids, e.text , depth + 1, options, gsobjects, other_gsobjects )
    end
  end
end


def trace_layer_oids( oids, options )

  # find the set of objects that are layers
  layer_keys = oids.keys.select() do |oid|
    # Predicate - Is one of the objects/gsobjects associated with the oid a layer? 
    oids[ oid].select() do |object|
      layer_name = REXML::XPath.first( object[:xml], "/layer/name" )
    end .any?
  end

  # and recursively scan out the dependencies following the id refs
  layer_keys.each() do | oid |
    gsobjects = {}
    other_gsobjects = []
    trace_oid( oids, oid, 0, options, gsobjects, other_gsobjects )
    yield gsobjects, other_gsobjects
  end
end

### rather than have other_gsobjects, why not just add the array list to the the 
### main. Because the structure is completely different.  gsobjects have :xml and :path 
###  and this would prevent iterating/selecting the main objects easily

def print_layer( options, gsobjects, other_gsobjects )

  # dump layer useful layer info to stdout
  name = REXML::XPath.first( gsobjects['layer'][:xml], '/layer/name')
  print "#{name.text}" if name
  namespace = REXML::XPath.first( gsobjects['namespace'][:xml], '/namespace/prefix')
  print ", ns->#{namespace.text}" if namespace
  workspace = REXML::XPath.first( gsobjects['workspace'][:xml], '/workspace/name')
  print ", ws->#{workspace.text}" if workspace

  # no style for wfs
  if gsobjects['style'] and gsobjects['style'][:xml]
    node = gsobjects['style'][:xml]
    style = REXML::XPath.first( node, '/style/name')
    style_file = REXML::XPath.first( node, "/style/filename" )
    print ", style->#{style.text}" if style
#    print ", stylefile->#{style_file.text}" if style_file
  end

  nativeName = REXML::XPath.first( gsobjects['featureType'][:xml], '/featureType/nativeName')
  print ", nativeName->#{nativeName.text}" if nativeName

  if gsobjects['dataStore']
    node = gsobjects['dataStore'][:xml]
    jndi = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='jndiReferenceName']")
    print ", jndiref->#{jndi.text}" if jndi
    schema = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='schema']")
    print ", schema->#{schema.text}" if schema
    url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
    print ", url->#{url.text}" if url
  end

  if gsobjects['coverageStore']
    node = gsobjects['coverageStore'][:xml]
    url = REXML::XPath.first( node, "/coverageStore/url" )
    print ", coverage_url->#{url.text}" if url
  end

  print ", gsobjects: #{gsobjects.length} others: #{other_gsobjects.length}"
  puts
end


def print_layer2( options, gsobjects, other_gsobjects )

  # dump layer useful layer info to stdout
  namespace = REXML::XPath.first( gsobjects['namespace'][:xml], '/namespace/prefix')
  print "#{namespace.text}:" if namespace
  name = REXML::XPath.first( gsobjects['layer'][:xml], '/layer/name')
  print "#{name.text}" if name
  workspace = REXML::XPath.first( gsobjects['workspace'][:xml], '/workspace/name')
  print ", #{workspace.text}" if workspace
  nativeName = REXML::XPath.first( gsobjects['featureType'][:xml], '/featureType/nativeName')
  print ", #{nativeName.text}" if nativeName

  if gsobjects['dataStore']
    node = gsobjects['dataStore'][:xml]
    jndi = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='jndiReferenceName']")
    print ", jndiref->#{jndi.text}" if jndi
    schema = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='schema']")
    print ", schema->#{schema.text}" if schema
    url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
    print ", url->#{url.text}" if url
  end

  if gsobjects['coverageStore']
    node = gsobjects['coverageStore'][:xml]
    url = REXML::XPath.first( node, "/coverageStore/url" )
    print ", coverage_url->#{url.text}" if url
  end
#  print ", gsobjects: #{gsobjects.length} others: #{other_gsobjects.length}"
  puts
end


def merge_layer( options, gsobjects, other_gsobjects )

  # Merge a layer from one config into another updating references
  puts "--------------"
  print_layer( options, gsobjects, other_gsobjects )

  # loop the main xml gsobjects associated with layer
  gsobjects.keys.each() do |key|

    src = gsobjects[key][:path]
    node = gsobjects[key][:xml]
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

      # write the new file
      puts "writing xml #{rel_src} -> #{dest}"
      FileUtils.mkdir_p(File.dirname(dest ))
      File.open( dest,"w") do |data|
         data << node
      end
    end
  end

  # copy support gsobjects like styles etc.
  other_gsobjects.each() do |path|
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

  # Generate a chef json databag for nagios monitoring of geoserver layers.
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
    "layers":
    [
#{items.join( ",\n")}
    ]
}
  EOS
  puts databag
end


def rename_layer( options, layers )

	puts "rename!! #{options[:rename]} -> #{options[:rename_target]}" 

  # find the layer
  layer = layers.select() do |candidate|
    candidate[:name] == options[:rename]
  end .first()
  abort( "cannot find layer #{options[:rename]}" ) unless layer
  gsobjects = layer[:gsobjects]

  # remove a layer and featureType - leave the nativeName which refers to the schema
  layer_name = REXML::XPath.first( gsobjects['layer'][:xml], '//layer/name')
  abort( ) unless layer_name
  featureType_name = REXML::XPath.first( gsobjects['featureType'][:xml], '//featureType/name')
  abort( ) unless featureType_name
  featureType_title = REXML::XPath.first( gsobjects['featureType'][:xml], '//featureType/title')
  abort( ) unless featureType_title

  # we have to be careful with the order of these operations.
  #  puts "title text '#{featureType_title.text}' layer name '#{layer_name.text}'"
  if featureType_title.text == layer_name.text
    puts "Updating title text from '#{featureType_title.text}' to name '#{options[:rename_target]}'"
    featureType_title.text = options[:rename_target]
  else
    puts "Leaving title as '#{featureType_title.text}'"
  end

  layer_name.text = options[:rename_target]
  featureType_name.text = options[:rename_target]

  # update the layer and featureType gsobjects
  File.open( gsobjects['featureType'][:path], "w") do |data|
    data << gsobjects['featureType'][:xml]
  end
  File.open( gsobjects['layer'][:path], "w") do |data|
    data << gsobjects['layer'][:xml]
  end
end


def remove_layer( options, layers )

  # the tricky bit is to avoid removing gsobjects when
  # they are referenced by other objects. Eg. multiple layers using a common dataStores

  puts "remove layer #{options[:remove]}"

  # build a a record of file counts
  counts = {}
  layers.each() do |layer|
    # gsobjects traced by oids
    layer[:gsobjects].each() do |key,val|
      path = val[:path]
      # puts "path #{path}"
      counts[path] = 0 if counts[path] == nil
      counts[path] += 1
    end
    # other gsobjects
    layer[:other_gsobjects].each() do |path|
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

  # collect up removal candidate gsobjects for the layer
  candidates = []
  layer[:gsobjects].each() do |key,val|
    candidates << val[:path]
  end
  layer[:other_gsobjects].each() do |path|
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
  # actions
  opts.on('-p', 'print to stdout') { |v| options[:print] = true }
  opts.on('-2', 'print to stdout with shorter format') { |v| options[:print2] = true }
  opts.on('-b', 'create databag') { |v| options[:databag] = true }
  opts.on('-m', 'merge geoserver config') { |v| options[:merge] = true }

  # opts.on( '-l', '--list a,b,c', Array, "List of parameters" ) do|l|
  opts.on('-r', '--rename NAME,NAME', Array) { |v| options[:rename] = v.at( 0); options[:rename_target] = v.at( 1) }

  # arg must look like this -r u1,u2 
  opts.on('-x', '--remove NAME') { |v| options[:remove] = v }
  # directories
  opts.on('-s', '--src_directory NAME', 'source dir') { |v| options[:source_dir] = v }
  opts.on('-d', '--dest_directory NAME', 'destination to copy to') { |v| options[:dest_dir] = v }
  # other control
  ## opts.on('-f', '--layer NAME', 'get layers to process from a list') { |v| options[:layer] = v }
  opts.on('-j', '--jndirref NAME', 'change jndi ref') { |v| options[:jndi_reference] = v }
  opts.on('-w', '--workspace NAME', 'change workspace id') { |v| options[:workspace_id] = v }
  opts.on('-n', '--namespace NAME', 'change namespace id') { |v| options[:namespace_id] = v }
end.parse!


oids = create_oid_mappings( options )

print_duplicate_oids( oids, options)

layers = []
trace_layer_oids( oids, options ) do  |gsobjects, other_gsobjects|

  # Gather up a list of layers with their resources to ease processing

  # validate we have the expected gsobjects
  # this logic needs to be improved
	abort( "missing namespace file") unless gsobjects['namespace']
	abort( "missing layer file") unless gsobjects['layer']
	abort( "missing featureType or coverage file") unless gsobjects['featureType'] or gsobjects['coverage']
	abort( "missing dataStore file") unless gsobjects['dataStore']
	abort( "missing workspace file") unless gsobjects['workspace']
#    elsif REXML::XPath.first( node, "/workspace" )
#    elsif REXML::XPath.first( node, "/coverage" )
  # extract some common fields common to all layers
  namespace = REXML::XPath.first( gsobjects['namespace'][:xml], '/namespace/prefix')
  name = REXML::XPath.first( gsobjects['layer'][:xml], '/layer/name')

  # Following Imos naming convention
  type = /_data|_url$/.match( name.text ) ? "wfs" : "wms"

  layers << {
    name: name.text,
    namespace: namespace.text,
    type: type,
    gsobjects: gsobjects,
    other_gsobjects: other_gsobjects
  }
end


if options[:databag]
  create_monitoring_databag( options, layers )

elsif options[:rename]
  rename_layer( options, layers )

elsif options[:remove]
  remove_layer( options, layers )

elsif options[:print] or options[:print2]
  # sort
  layers.sort! do |a,b|
    a[:name].downcase <=> b[:name].downcase
  end
  # and print to stdout
  layers.each() do |layer|
    print_layer( options, layer[:gsobjects], layer[:other_gsobjects] ) if options[:print]
    print_layer2( options, layer[:gsobjects], layer[:other_gsobjects] ) if options[:print2]
  end

elsif options[:merge]
  layers.each() do |layer|
    merge_layer( options, layer[:gsobjects], layer[:other_gsobjects] )
  end
end


