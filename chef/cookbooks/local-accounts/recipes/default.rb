chef_gem 'ruby-shadow'

include_recipe 'local-accounts::fujiwara'
include_recipe 'local-accounts::sugyan'
include_recipe 'local-accounts::songmu'

group 'wheel' do
  members ['fujiwara', 'sugyan', 'songmu']
end
