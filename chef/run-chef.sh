#!/bin/sh

chef-solo -c config/solo.rb -j nodes/localhost.json
