#
# Cookbook Name:: sysstat
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

file '/etc/default/sysstat' do
  owner 'root'
  group 'root'
  mode 0644
  content 'ENABLED="true"
'
end

template '/etc/cron.d/sysstat' do
  owner 'root'
  group 'root'
  mode 0644
  source 'sysstat.cron.erb'
end
