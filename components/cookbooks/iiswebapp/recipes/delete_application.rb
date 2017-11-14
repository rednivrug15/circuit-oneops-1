web_application = node['iis-webapp']
web_application_path = web_application['application_path']

web_application name do
  action                :delete
  application_path      web_application
end
