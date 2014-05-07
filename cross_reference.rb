
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


	@xml = Nokogiri::XML(File.open(path))

#	 xml_node = @xml.at_xpath("#{xpath}/#{name}")

	layer_node = @xml.at_xpath("/layer/name")

	if layer_node 
		puts layer_node.inner_html
	end


#	//xpath_object = load_xml_file(path) #xml_file).at_xpath(path)

# 	layer_name = Chef::Recipe::XMLHelper::get_xml_value(file, "layer/name")
# 	if( layer_name)
#         #next unless layer_name
# 
# 	end

#	puts path 


end
