d = `pwd`.chomp
file_cache_path '/tmp/chef-solo'
cookbook_path   "#{d}/cookbooks"
data_bag_path   "#{d}/data_bags"
role_path       "#{d}/roles"
node_name       `hostname -s`.chomp
ssl_verify_mode :verify_peer
verbose_logging false
