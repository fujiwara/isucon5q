user "songmu" do
  home "/home/songmu"
  supports :manage_home => true
  shell "/bin/bash"
end

directory "/home/songmu/.ssh" do
  mode 0700
  owner "songmu"
end

remote_file "/home/songmu/.ssh/authorized_keys" do
  mode 0600
  owner "songmu"
  source "https://github.com/songmu.keys"
  action :create_if_missing
end
