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

      def assign_attributes_on_create attributes
        reload
        @web_site = @sites_collection.CreateNewElement("site")
        @application_collection = @web_site.Collection
        @web_site.Properties.Item("name").Value = @name
        assign_attributes_to_site(attributes)
        create_application attributes
        @sites_collection.AddElement(@web_site)
        @admin_manager.CommitChanges
      end

      def assign_attributes_on_update(attributes)
        reload
        assign_attributes_to_site(attributes)
        update_application(attributes)
        @admin_manager.CommitChanges
      end

      def assign_attributes_to_site(attributes)
        @web_site.Properties.Item("id").Value = attributes["id"] if attributes.has_key?("id")
        @web_site.Properties.Item("serverAutoStart").Value = attributes["server_auto_start"] if attributes.has_key?("serverAutoStart")
        assign_bindings(attributes["bindings"]) if attributes.has_key?("bindings")
      end

      def assign_bindings attributes
        bindings_collection = @website.childElements.Item("bindings").Collection
        bindings_collection.Clear
        attributes.each do |site_binding|
          binding_element = bindings_collection.CreateNewElement("binding")
          binding_element.Properties.Item("protocol").Value = site_binding["protocol"] if attributes.has_key?(site_binding["protocol"])
          binding_element.Properties.Item("bindingInformation").Value = site_binding["binding_information"] if attributes.has_key?(site_binding["binding_information"])
          bindings_collection.AddElement(binding_element)
          add_ssl_certificate(binding_element, attributes) if site_binding["protocol"] == 'https' && !attributes["certificate_hash"].empty?
        end
      end

      def add_ssl_certificate(binding_element, attributes)
        method_instance = binding_element.Methods.Item("AddSslCertificate").CreateInstance()
        method_instance.Input.Properties.Item("certificateHash").Value = attributes["certificate_hash"]
        method_instance.Input.Properties.Item("certificateStoreName").Value = attributes["certificate_store_name"];
        method_instance.Execute()
      end

      def get_site
        attributes = {}
        attributes
      end

      private: assign_bindings, add_ssl_certificate, assign_attributes_to_site
    end
  end
end
