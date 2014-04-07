# replay apache logsat a server

require 'open-uri'
require 'thread'

file="/home/meteo/imos/projects/geoserver_crash/geoserver-123-11-nsp-mel.aodn.org.au-access.log.crash"
# file="test.crash" 
server = "geoserver-123-12-nsp-mel.aodn.org.au"
# server = "geoserver-rc.aodn.org.au"
worker_threads = 10

# worker queue
queue = Queue.new


# read the apache log file and create a set of jobs
File.open( file, "r").each_line do |line|
	matches = /([^ ]*).*\[(.*)\].*GET (.*)\sHTTP/.match( line ).captures
	ip = matches[ 0] 
	date = matches[ 1] 
	url = matches[2]
#	puts "'#{ip}' '#{date}' '#{url}'"
  request = "http://#{server}/#{url}"
  queue << request
end

# create a thread group to process the queue
threads = []
worker_threads.times do |i|
  t = Thread.new do
    until queue.empty?
      # pop with the non-blocking flag set, this raises
      # an exception if the queue is empty, in which case
      # work_unit will be set to nil
      request = queue.pop(true) rescue nil
      if request
        # queue len is approx only
        puts "#{queue.length} thread #{i}, #{request}"
        begin
          contents = URI.parse( request ).read
        rescue Timeout::Error
          puts 'That took too long, exiting...'
        rescue OpenURI::HTTPError
          puts 'Http error' 
        end
        puts "finish #{i}"
      end
    end
    puts "exiting #{i}"
  end
  threads << t
end

# wait for threads to finish
threads.each() do |t|
  t.join()
end




