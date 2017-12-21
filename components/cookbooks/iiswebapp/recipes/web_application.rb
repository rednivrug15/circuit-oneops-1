web_application = node['iiswebapp']
web_site_name = node['workorder']['box']['ciName']

name = web_application['package_name']
web_application_path = web_application['application_path']
physical_path = node['workorder']['rfcCi']['ciAttributes']['physical_path']
version = node['workorder']['rfcCi']['ciAttributes']['package_version']
web_application_physical_path = "#{physical_path}\\#{name}\\#{version}"
create_new_app_pool = web_application.create_new_application_pool.to_bool
web_application_pool = ( create_new_app_pool ? name : web_site_name )
identity_type = web_application["identity_type"]
application_action = ( node[:workorder][:rfcCi][:rfcAction] == 'add' ) ? :create : :update

iis_app_pool name do
  action  [:create, :update]
  managed_runtime_version         web_application["runtime_version"]
  process_model_identity_type     identity_type
  recycling_log_event_on_recycle  ["Time", "Requests", "Schedule", "Memory", "IsapiUnhealthy", "OnDemand", "ConfigChange", "PrivateMemory"]
  process_model_user_name         web_application.process_model_user_name if identity_type == 'SpecificUser'
  process_model_password          web_application.process_model_password if identity_type == 'SpecificUser'
  only_if { create_new_app_pool }
end

iiswebapp name do
  action                            application_action
  site_name                         web_site_name
  application_path                  web_application_path
  application_pool                  web_application_pool
  virtual_directory_physical_path   web_application_physical_path
end
