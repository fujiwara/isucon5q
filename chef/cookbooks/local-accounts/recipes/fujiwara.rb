user "fujiwara" do
  password "$6$K0ZhMyG4$Feu6sh.kOMl2KMS6R4maLTkDRbbqceH22tFGVxwNNljB7bxj8jpZpksPlEXM3Q.8Yy18ljKSIl/x/4zVtzNca."
  home "/home/fujiwara"
  supports :manage_home => true
  shell "/bin/bash"
end

directory "/home/fujiwara/.ssh" do
  mode 0700
  owner "fujiwara"
end

remote_file "/home/fujiwara/.ssh/authorized_keys" do
  mode 0600
  owner "fujiwara"
  source "https://github.com/fujiwara.keys"
  action :create_if_missing
end

file "/home/fujiwara/.screenrc" do
  owner "fujiwara"
  mode 0644
  content "escape ^z^z\n"
end
