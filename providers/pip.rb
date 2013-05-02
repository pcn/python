#
# Author:: Seth Chisamore <schisamo@opscode.com>
# Cookbook Name:: python
# Provider:: pip
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
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

require 'chef/mixin/shell_out'
require 'chef/mixin/language'
include Chef::Mixin::ShellOut

def whyrun_supported?
  true
end

# the logic in all action methods mirror that of
# the Chef::Provider::Package which will make
# refactoring into core chef easy

action :install do
  # If we specified a version, and it's not the current version, move to the specified version
  if new_resource.version != nil && new_resource.version != current_resource.version
    install_version = new_resource.version
  # If it's not installed at all, install it
  elsif current_resource.version == nil
    install_version = candidate_version
  end

  if install_version
    description = "install package #{new_resource} version #{install_version}"
    converge_by(description) do
      Chef::Log.info("Installing #{new_resource} version #{install_version}")
      status = install_package(install_version)
      if status
        new_resource.updated_by_last_action(true)
      end
    end
  end
end

action :upgrade do
  Chef::Log.debug("current resource: #{current_resource.version}   candidate_version = #{candidate_version}")
  if current_resource.version != candidate_version
    orig_version = current_resource.version || "uninstalled"
    Chef::Log.debug("Current version of #{current_resource} is #{orig_version}")
    description = "upgrade #{current_resource} version from #{current_resource.version} to #{candidate_version}"
    converge_by(description) do
      Chef::Log.info("Upgrading #{new_resource} version from #{orig_version} to #{candidate_version}")
      status = upgrade_package(candidate_version)
      if status
        new_resource.updated_by_last_action(true)
      end
    end
  end
end

action :remove do
  if removing_package?
    description = "remove package #{new_resource}"
    converge_by(description) do
      Chef::Log.info("Removing #{new_resource}")
      remove_package(new_resource.version)
      new_resource.updated_by_last_action(true)
    end
  end
end

def removing_package?
  if current_resource.version.nil?
    false # nothing to remove
  elsif new_resource.version.nil?
    true # remove any version of a package
  elsif new_resource.version == current_resource.version
    true # remove the version we have
  else
    false # we don't have the version we want to remove
  end
end

# these methods are the required overrides of
# a provider that extends from Chef::Provider::Package
# so refactoring into core Chef should be easy

def load_current_resource
  @current_resource = Chef::Resource::PythonPip.new(new_resource.name)
  @current_resource.package_name(new_resource.package_name)
  @current_resource.version(nil)
  @normalized_name ||= \
  begin
    # This regex is based on the source code for pip's pip/util.rb, in
    # _normalize_name().  The _normalize_re that's used in the module,
    # however, would appear to turn e.g. "foo.bar" into "foo-bar".
    # However, if you have foo.bar installed, "pip freeze" or "pip
    # list" will show you "foo.bar" and not "foo-bar".  So "." is
    # being added to this regex.
    new_resource.name.downcase.gsub(/[^a-z.0-9]/, '-')
  end

  unless current_installed_version.nil?
    @current_resource.version(current_installed_version)
  end

  @current_resource
end

def current_installed_version
  @current_installed_version ||= begin
    delimeter = /==/

    version_check_cmd = "#{which_pip(new_resource)} freeze | grep -i '^#{@normalized_name}=='"
    # incase you upgrade pip with pip!
    if new_resource.package_name.eql?('pip')
      delimeter = /\s/
      version_check_cmd = "pip --version"
    end
    Chef::Log.debug("Checking with #{version_check_cmd}")
    result = shell_out(version_check_cmd)
    result_stdout = result.stdout
    
    Chef::Log.debug("Result of version_check_cmd:  #{result_stdout}") # 
    (result.exitstatus == 0) ? result_stdout.split(delimeter)[1].strip : nil
  end
end

def candidate_version
  @candidate_version ||= \
  begin
    # Using 'pip list' is inconsistently useful/useless and 
    # doesn't work in the older versions of pip.  This does.
    candidate_version_check_cmd = <<EOF
#{which_python(new_resource)} -c "
import sys
from pip.index import PackageFinder
from pip.req import InstallRequirement
req = InstallRequirement.from_line('#{new_resource.package_name}', None)
pf = PackageFinder(find_links=[], index_urls=['#{new_resource.pypi_index}'], mirrors=[])
sys.stdout.write(pf.find_requirement(req, False).splitext()[0].split('-')[-1])"
EOF
    Chef::Log.debug("The check_cmd is #{candidate_version_check_cmd}")
    result = shell_out(candidate_version_check_cmd)
    result_stdout = result.stdout
    return_this = 'latest'
    if (result.exitstatus == 0) 
      return_this = result_stdout
    end
    Chef::Log.debug("Result of candidate_version for #{new_resource.package_name} (#{@normalized_name}) is #{result_stdout}")
    return_this
  end
end

def install_package(version)
  # if a version isn't specified (latest), is a source archive (ex. http://my.package.repo/SomePackage-1.0.4.zip),
  # or from a VCS (ex. git+https://git.repo/some_pkg.git) then do not append a version as this will break the source link
  if version == 'latest' || new_resource.name.downcase.start_with?('http:', 'https:') || ['git', 'hg', 'svn'].include?(new_resource.name.downcase.split('+')[0])
    version = ''
  end
  pip_cmd('install', version)
end

def upgrade_package(version)
  new_resource.options "#{new_resource.options} --upgrade"
  install_package(version)
end

def remove_package(version)
  new_resource.options "#{new_resource.options} --yes"
  pip_cmd('uninstall')
end

def pip_cmd(subcommand, version='')
  options = { :timeout => new_resource.timeout, :user => new_resource.user, :group => new_resource.group }
  options[:environment] = { 'HOME' => ::File.expand_path("~#{new_resource.user}") } if new_resource.user
  if version != ''
    Chef::Log.debug("The subcommand + version passed into pip_cmd is #{subcommand} + #{version}")
    resource_name = "#{new_resource.name}==#{version}"
  else
    resource_name = "#{new_resource.name}"
  end

  pypi_index = "--index  #{new_resource.pypi_index}"
  # The following commands don't support the index option
  if ['uninstall', 'freeze', 'show', 'zip', 'unzip'].include?(subcommand) 
    pypi_index = ''
  end
  requirements = ''
  # The install command supports a requirements file.
  if ['install'].include?(subcommand) and new_resource.requirements != ''
    requirements = "-r  #{new_resource.requirements}"
  end
  shell_out!("#{which_pip(new_resource)} #{subcommand} #{pypi_index} #{requirements} #{new_resource.options} #{resource_name}", options)
end

# TODO remove when provider is moved into Chef core
# this allows PythonPip to work with Chef::Resource::Package
def which_pip(nr)
  if (nr.respond_to?("virtualenv") && nr.virtualenv)
    ::File.join(nr.virtualenv,'/bin/pip')
  elsif node['python']['install_method'].eql?("source")
    ::File.join(node['python']['prefix_dir'], "/bin/pip")
  else
    'pip'
  end
end

# Use the same rules as which_pip to find the corresponding python
def which_python(nr)
    if (new_resource.respond_to?("virtualenv") && new_resource.virtualenv)
      python = ::File.join(new_resource.virtualenv,'/bin/python')
    elsif node['python']['install_method'].eql?("source")
      python = ::File.join(node['python']['prefix_dir'], "/bin/python")
    else
      python = 'python'
    end
end

