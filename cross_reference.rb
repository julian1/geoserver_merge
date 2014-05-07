
require 'find'
require 'fileutils'
require 'nokogiri'

tmp_dir="/home/meteo/imos/projects/geoserver-config/" 

layers = {} 
features = {} 
namespaces = {} 

Find.find(tmp_dir) do |path|

	# skip directories
	next unless FileTest.file?(path)
	# skip any path that doesn't have a .xml extension
	next unless File.extname(path) == '.xml'

	# decode to xml
	xml = Nokogiri::XML(File.open(path))

	# extract geoserver objects
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
 		namespace_id = xml.at_xpath("/featureType/namespace/id")
 		raise "feature missing namespace" unless namespace_id
		# puts "feature #{feature_id.inner_html}, name #{name.inner_html}, namespace #{namespace.inner_html}"
		features[feature_id.inner_html] = { name: name.inner_html, namespace_id: namespace_id.inner_html } 
	end

	# namespaces
	namespace_id = xml.at_xpath("/namespace/id")
	if namespace_id 
 		prefix = xml.at_xpath("/namespace/prefix")
 		raise "namespace missing prefix " unless prefix
		# puts "namespace #{namespace_id.inner_html}, name #{name.inner_html}"
		namespaces[namespace_id.inner_html] = { prefix: prefix.inner_html } 
	end
end


# denormalize layers
layers.each() do |layer_id,layer|

	feature = features[layer[:feature_id]]
	raise "no feature for layer #{layer[:name]}" unless feature

	namespace = namespaces[feature[:namespace_id]]
	raise "no namespace for feature #{layer[:name]}" unless feature

	puts "#{namespace[:prefix]} #{layer[:name]}  enabled #{layer[:enabled]}"

# 		puts " feature #{feature.name}"
end
#


