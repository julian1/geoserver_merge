
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

	# decode to xml once
	@xml = Nokogiri::XML(File.open(path))


	# layer objects
	layer = @xml.at_xpath("/layer/name")
	if layer
		id = @xml.at_xpath("/layer/id")
		raise "missing id" unless id
		# assert have id
		puts "layer -> #{layer.inner_html}, id #{id.inner_html}"
		# need to get the id...
		
	end

#	<featureType>
#  <id>FeatureTypeInfoImpl-2d23ec69:126d477e611:-7e38</id>
	feature_type = @xml.at_xpath("/featureType/name")
	if feature_type
#		puts feature_type.inner_html
	end


#	//xpath_object = load_xml_file(path) #xml_file).at_xpath(path)

# 	layer_name = Chef::Recipe::XMLHelper::get_xml_value(file, "layer/name")
# 	if( layer_name)
#         #next unless layer_name
# 
# 	end

#	puts path 


end
