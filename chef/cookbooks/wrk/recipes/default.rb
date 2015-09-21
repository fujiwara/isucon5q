#
# Cookbook Name:: wrk
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

git '/tmp/wrk' do
  repository 'https://github.com/wg/wrk.git'
  not_if 'test -e /usr/local/bin/wrk'
  notifies :run, 'bash[install wrk]'
end

bash 'install wrk' do
  cwd '/tmp/wrk'
  code <<END
make
install wrk /usr/local/bin/wrk
END
  action :nothing
end
