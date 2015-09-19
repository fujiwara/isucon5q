#
# Cookbook Name:: nginx-build
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

remote_file '/tmp/nginx-build-linux-amd64-0.4.4.tar.gz' do
  source "https://github.com/cubicdaiya/nginx-build/releases/download/v0.4.4/nginx-build-linux-amd64-0.4.4.tar.gz"
  not_if 'nginx-build -version | fgrep "nginx-build 0.4.4"'
  notifies :run, 'execute[install nginx-build]'
end

execute 'install nginx-build' do
  cwd '/tmp'
  user 'root'
  command 'tar xvf nginx-build-linux-amd64-0.4.4.tar.gz
install nginx-build /usr/local/bin'
  action :nothing
end
