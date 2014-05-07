
# require 'chef/mixin/shell_out'
require 'find'
require 'fileutils'
#include Chef::Mixin::ShellOut

require 'nokogiri'

tmp_dir="/home/meteo/imos/projects/geoserver-config/" 

Find.find(tmp_dir) do |path|

	# skip directories
	next unless FileTest.file?(path)
	# skip any path that doesn't have a .xml extension
	next unless File.extname(path) == '.xml'

	# decode to xml
	xml = Nokogiri::XML(File.open(path))

	layers = {} 

	# layer objects
	layer_id = xml.at_xpath("/layer/id")
	if layer_id
		name = xml.at_xpath("/layer/name")
		raise "layer missing id" unless name
		feature_id = xml.at_xpath("/layer/resource/id")
		raise "layer missing feature id" unless feature_id

		puts "layer -> #{name.inner_html}, id #{layer_id.inner_html}, feature_id #{feature_id.inner_html}"
	end

	feature_id = xml.at_xpath("/featureType/id")
	if feature_id 
 		name = xml.at_xpath("/featureType/name")
 		raise "feature missing name" unless name

		puts "feature #{feature_id.inner_html}, name #{name.inner_html}"
	end


#	//xpath_object = load_xml_file(path) #xml_file).at_xpath(path)
# 	layer_name = Chef::Recipe::XMLHelper::get_xml_value(file, "layer/name")
# 	if( layer_name)
#         #next unless layer_name
# 	end
#	puts path 


end
