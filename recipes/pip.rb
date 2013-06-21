#
# Author:: Seth Chisamore <schisamo@opscode.com>
# Cookbook Name:: python
# Recipe:: pip
#
# Copyright 2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

if platform_family?("rhel") and node['python']['install_method'] == 'package'
  pip_binary = "/usr/bin/pip"
elsif platform_family?("debian") and node['python']['install_method'] == 'package'
  # pip_binary = "/usr/bin/pip"
  # In knewton, /usr/local/bin/pip is better
  pip_binary = "/usr/local/bin/pip"
elsif platform_family?("smartos")
  pip_binary = "/opt/local/bin/pip"
else
  # Test: make sure that pip_binary points to an actual pip that's installed.
    # XXX Confirm this is the behavior
    # distribute_setup.py wil put this into /usr/local/bin the way
    # it's invoked in the execute[install-pip] resource below
  pip_binary = "/usr/local/bin/pip"
end

# Ubuntu's python-setuptools, python-pip and python-virtualenv packages
# are broken...this feels like Rubygems!
# http://stackoverflow.com/questions/4324558/whats-the-proper-way-to-install-pip-virtualenv-and-distribute-for-python
# https://github.com/pypa/pip/issues/6
remote_file "#{Chef::Config[:file_cache_path]}/distribute_setup.py" do
  source node['python']['distribute_script_url']
  mode "0644"
  not_if { ::File.exists?(pip_binary) }
end

execute "install-pip" do
  cwd Chef::Config[:file_cache_path]
  command <<-EOF
  #{node['python']['binary']} distribute_setup.py --download-base=#{node['python']['distribute_option']['download_base']}
  #{::File.dirname(pip_binary)}/easy_install pip
  EOF
  not_if { ::File.exists?(pip_binary) }
end
