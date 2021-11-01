require 'json'
require 'zinzout'

# {"id":"mdp.39015070574192","most_recent_appearance":202110,"appearances":[{"id":1046,"dt":200808,"json_class":"IDDate"}],"json_class":"HTIDHistory"}

filename = ARGV.shift

# Here we don't bother to load in the whole data structure; we can do what we need with just the raw JSON
Zinzout.zin(filename).each do |line|
  h = JSON.parse(line)
  next unless h['json_class'.freeze] == 'HTIDHistory'.freeze
  puts h['id'.freeze] unless h['most_recent_appearance'.freeze] == 202110
end
