
SRC=/home/meteo/imos/projects/chef/geoserver

# everything except argo_profile_layer 

for i in argo_float argo_float_abos_vw argo_float_oxygen_vw argo_platform_metadata \
argo_platform_nominal_cycle argo_platform_sensor argo_profile_download argo_profile_download_old \
argo_profile_general argo_profile_history argo_profile_measurements \
argo_profile_param_calibration argo_profile_params ; do 

	echo $i; 
 
	./merge_geoserver_config.rb  -s $SRC  -l "$i" -r "$i""_data"

done

