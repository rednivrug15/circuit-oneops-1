require "ostruct"
require_relative "ext_kernel"
require_relative "iis_web_app"

module OO
  class IIS
    class WebSite

      class NullEntity < OpenStruct
        def nil?; true; end
        def Delete_(*attrs, &block); end
        def Count; 0; end
      end

      silence_warnings do
        APPHOST_PATH = "MACHINE/WEBROOT/APPHOST"
        SITE_SECTION = "system.applicationHost/sites"
        SITE = "Site"
      end

      def initialize(web_administration, name)
        @web_administration = web_administration
        @name = name
        reload
      end

      def reload
        @entity = @web_administration.find(SITE, @name) || NullEntity.new
        @admin_manager = WIN32OLE.new("Microsoft.ApplicationHost.WritableAdminManager")
        @admin_manager.CommitPath = APPHOST_PATH
        @sites_collection = @admin_manager.GetAdminSection(SITE_SECTION, APPHOST_PATH).Collection
        @web_site = find_site(@name) || NullEntity.new
        @application_collection = @web_site.Collection
      end

      def find_site(site_name)
        position = (0..(@sites_collection.Count-1)).find { |i| site_collection.Item(i).GetPropertyByName("name").Value == site_name }
        @sites_collection.Item(position)
      end

      def exists?
        not @entity.nil?
      end

      def start
        @entity.Start
      end

      def create(attributes)
        not exists? and @web_administration.perform { assign_attributes_on_create(attributes) }
      end

      def update(attributes)
        exists? and @web_administration.perform { assign_attributes_on_update(attributes) }
      end

      def delete
        @web_administration.delete(SITE, @name).tap { reload }
      end

      def get_application path
        application_element = @application_collection.Item(get_application_postion(path))
        WebApp.new(application_element).application_attributes
      end

      def application_exists? path
        !get_application_postion(path).nil?
      end

      def get_application_postion path
        (0..(@application_collection.Count-1)).find { |i| @application_collection.Item(i).Properties.Item("path").Value == path }
      end

      def create_application attributes
        application_element = @application_collection.CreateNewElement("application")
        WebApp.new(application_element).create(attributes)
        @application_collection.AddElement(application_element)
        @admin_manager.CommitChanges
      end

      def update_application attributes
        application_element = @application_collection.Item(get_application_postion(attributes["application_path"]))
        WebApp.new(application_element).update(attributes)
        @admin_manager.CommitChanges
      end

      def delete_application path
        @application_collection.DeleteElement(get_application_postion(application_path))
        @admin_manager.CommitChanges
      end

=begin
      def resource_needs_change(attributes)
        update_attributes = Hash.new({})
        bindings = []
        new_bindings = []
        @web_administration.readable_section_for(SITE_SECTION) do |section|
          collection = section.Collection
          position = (0..(collection.Count-1)).find { |i| collection.Item(i).GetPropertyByName("name").Value == @name }
          site = collection.Item(position)
          update_attributes["id"] = attributes["id"] unless site.Properties.Item("id").Value.equal?(attributes["id"])
          update_attributes["server_auto_start"] = attributes["server_auto_start"] unless site.Properties.Item("serverAutoStart").Value.equal?(attributes["server_auto_start"])

          bindings_collection = site.ChildElements.Item("bindings").Collection

          (0..(bindings_collection.Count-1)).each do |i|
            protocol_value = bindings_collection.Item(i).GetPropertyByName('protocol').Value
            binding_information_value = bindings_collection.Item(i).GetPropertyByName('bindingInformation').Value
            bindings = [{'protocol' => "#{protocol_value}", 'binding_information' => "#{binding_information_value}"}]
            if protocol_value == 'https'
              certificate_hash = bindings_collection.Item(i).GetPropertyByName('certificateHash').Value
              update_attributes["certificate_hash"] = attributes["certificate_hash"] if certificate_hash.downcase != attributes["certificate_hash"].downcase
            end
          end

          new_bindings = attributes["bindings"]
          update_attributes["bindings"] = attributes["bindings"] unless (bindings - new_bindings).empty?

          applications = site.Collection
          (0..(applications.Count-1)).each do |i|
            app_element = applications.Item(i)
            app_pool = app_element.GetPropertyByName("applicationPool").Value
            update_attributes["application_pool"] = attributes["application_pool"] if app_pool != attributes["application_pool"]
            virtual_dirs = app_element.Collection
            (0..(virtual_dirs.Count-1)).each do |i|
              virtual_directory = virtual_dirs.Item(i)
              virtual_directory_physical_path = virtual_directory.GetPropertyByName("physicalPath").Value
              update_attributes["virtual_directory_physical_path"] = attributes["virtual_directory_physical_path"] if virtual_directory_physical_path != attributes["virtual_directory_physical_path"]
            end
          end
        end
        update_attributes.empty?
      end
=end

      def assign_attributes_on_create attributes
        reload
        @web_site = @sites_collection.CreateNewElement("site")
        @web_site.Properties.Item("name").Value = @name
        @web_site.Properties.Item("id").Value = attributes["id"]
        @web_site.Properties.Item("serverAutoStart").Value = attributes["server_auto_start"]
        bindings_collection = site_element.ChildElements.Item("bindings").Collection
        attributes["bindings"].each do |site_binding|
          binding_element = bindings_collection.CreateNewElement("binding")
          binding_element.Properties.Item("protocol").Value = site_binding["protocol"]
          binding_element.Properties.Item("bindingInformation").Value = site_binding["binding_information"]
          bindings_collection.AddElement(binding_element)
          if site_binding["protocol"] == 'https' && !attributes["certificate_hash"].empty?
            add_ssl_certificate(binding_element, attributes)
          end
        end
        @application_collection = @web_site.Collection
        create_application attributes
        @sites_collection.AddElement(@web_site)
        @admin_manager.CommitChanges
      end

      def assign_attributes_on_update(attributes)
        reload
        @web_site.Properties.Item("id").Value = attributes["id"] if attributes.has_key?("id")
        @web_site.Properties.Item("serverAutoStart").Value = attributes["server_auto_start"] if attributes.has_key?("server_auto_start")
        if attributes.has_key?("bindings")
          bindings_collection = site.ChildElements.Item("bindings").Collection
          bindings_collection.Clear
          attributes["bindings"].each do |site_binding|
            binding_element = bindings_collection.CreateNewElement("binding")
            binding_element.Properties.Item("protocol").Value = site_binding["protocol"]
            binding_element.Properties.Item("bindingInformation").Value = site_binding["binding_information"]
            bindings_collection.AddElement(binding_element)
            if site_binding["protocol"] == 'https' && !attributes["certificate_hash"].empty?
              add_ssl_certificate(binding_element, attributes)
            end
          end
        end
        update_application attributes
        @admin_manager.CommitChanges
      end

      def add_ssl_certificate(binding_element, attributes)
        method_instance = binding_element.Methods.Item("AddSslCertificate").CreateInstance()
        method_instance.Input.Properties.Item("certificateHash").Value = attributes["certificate_hash"]
        method_instance.Input.Properties.Item("certificateStoreName").Value = attributes["certificate_store_name"];
        method_instance.Execute()
      end

    end
  end
end
