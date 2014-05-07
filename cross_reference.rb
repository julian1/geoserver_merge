
# require 'chef/mixin/shell_out'
require 'find'
require 'fileutils'
#include Chef::Mixin::ShellOut

require 'nokogiri'

tmp_dir="/home/meteo/imos/projects/geoserver-config/" 

layers = {} 
features = {} 
workspaces = {} 

Find.find(tmp_dir) do |path|

	# skip directories
	next unless FileTest.file?(path)
	# skip any path that doesn't have a .xml extension
	next unless File.extname(path) == '.xml'

	# decode to xml
	xml = Nokogiri::XML(File.open(path))

	# layers
	layer_id = xml.at_xpath("/layer/id")
	if layer_id
		name = xml.at_xpath("/layer/name")
		raise "layer missing id" unless name
		feature_id = xml.at_xpath("/layer/resource/id")
		raise "layer missing feature id" unless feature_id
		enabled_raw = xml.at_xpath("/layer/enabled")
		enabled = true
		if enabled_raw && enabled_raw.inner_html == "false"
			enabled = false
		end
		# puts "layer -> #{name.inner_html}, id #{layer_id.inner_html}, feature_id #{feature_id.inner_html}"
		layers[layer_id.inner_html] = { name: name.inner_html, feature_id: feature_id.inner_html, enabled: enabled } 
	end

	# feature types
	feature_id = xml.at_xpath("/featureType/id")
	if feature_id 
 		name = xml.at_xpath("/featureType/name")
 		raise "feature missing name" unless name
 		namespace = xml.at_xpath("/featureType/namespace/id")
 		raise "feature missing namespace" unless namespace
		# puts "feature #{feature_id.inner_html}, name #{name.inner_html}, namespace #{namespace.inner_html}"
		features[feature_id.inner_html] = { name: name.inner_html, namespace: namespace.inner_html } 
	end

	# workspaces
	workspace_id = xml.at_xpath("/workspace/id")
	if workspace_id 
 		name = xml.at_xpath("/workspace/name")
 		raise "workspace missing name" unless name
		# puts "workspace #{workspace_id.inner_html}, name #{name.inner_html}"
		workspaces[workspace_id.inner_html] = { name: name.inner_html } 
	end



#<workspace>
#  <id>
# <featureType>
#   <id>FeatureTypeInfoImpl-2d23ec69:126d477e611:-7e38</id>
#   <name>installation_summary</name>
#   <nativeName>installation_summary</nativeName>
#   <namespace>
#     <id>NamespaceInfoImpl-5f0a648d:1428d0d11a9:-7fff</id>
# 

#	//xpath_object = load_xml_file(path) #xml_file).at_xpath(path)
# 	layer_name = Chef::Recipe::XMLHelper::get_xml_value(file, "layer/name")
# 	if( layer_name)
#         #next unless layer_name
# 	end
#	puts path 


end

	layers.each() do |key,val|
		puts "layer #{key}, #{val}"
	end


	features.each() do |key,val|
		puts "feature #{key}, #{val}"
	end

	workspaces.each() do |key,val|
		puts "workspace #{key}, #{val}"
	end

