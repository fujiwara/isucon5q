#
# Cookbook Name:: http_load
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

remote_file '/tmp/http_load-14aug2014.tar.gz' do
  source 'http://www.acme.com/software/http_load/http_load-14aug2014.tar.gz'
  notifies :run, 'bash[install http_load]'
  not_if 'test -e /usr/local/bin/http_load'
end

bash 'install http_load' do
  cwd '/tmp'
  code <<END
tar xvf http_load-14aug2014.tar.gz
cd http_load-14aug2014
make
make install
END
  action :nothing
end
