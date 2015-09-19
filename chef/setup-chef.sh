#!/bin/sh
# for Ubuntu

apt-get update
apt-get -y install ruby ruby-dev gcc make build-essential vim
wget https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/10.04/x86_64/chef_11.18.12-1_amd64.deb
dpkg -i ./chef_11.18.12-1_amd64.deb

echo "Host github.com" >> ~/.ssh/config
echo "  Compression yes" >> ~/.ssh/config
echo '%wheel	ALL=NOPASSWD:	ALL' >> /etc/sudoers

update-alternatives --config editor
