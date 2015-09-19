user "sugyan" do
  home "/home/sugyan"
  supports :manage_home => true
  shell "/bin/bash"
end

directory "/home/sugyan/.ssh" do
  mode 0700
  owner "sugyan"
end

remote_file "/home/sugyan/.ssh/authorized_keys" do
  mode 0600
  owner "sugyan"
  source "https://github.com/sugyan.keys"
  action :create_if_missing
end
