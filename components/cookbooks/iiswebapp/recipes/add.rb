oo_local_vars = node['workorder']['payLoad']['OO_LOCAL_VARS'] if node.workorder.payLoad.has_key?(:OO_LOCAL_VARS)

Array(oo_local_vars).each do |var|
  node.set['workorder']['rfcCi']['ciAttributes']['physical_path'] = "#{var[:ciAttributes][:value]}" if var[:ciName] == "app_directory"
end

include_recipe 'artifact::install_nuget_package'
include_recipe 'iiswebapp::web_application'
