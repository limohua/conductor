require 'yaml'
require 'rest_client'
require 'nokogiri'

module Aeolus
  module Image
    #This will house some methods that multiple Command classes need to use.
    class BaseCommand
      attr_accessor :options

      def initialize(opts={}, logger=nil)
        logger(logger)
        @options = opts
        @config = load_config
      end

      protected
      def logger(logger=nil)
        @logger ||= logger
        unless @logger
          @logger = Logger.new(STDOUT)
          @logger.level = Logger::INFO
          @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
        end
        return @logger
      end

      def iwhd
        create_resource('iwhd')
      end

      def conductor
        create_resource('conductor')
      end

      def read_file(path)
        begin
          full_path = File.expand_path(path)
          if File.exist?(full_path) && !File.directory?(full_path)
            File.read(full_path)
          else
            return nil
          end
        rescue
          nil
        end
      end

      def quit(code)
        exit(code)
      end

      private
      def load_config
        begin
          @config_location = ENV['HOME'] + "/.aeolus-cli"
          YAML::load(File.open(@config_location))
        rescue Errno::ENOENT
          #TODO: Create a custom exception to wrap CLI Exceptions
          raise "Unable to locate configuration file: \"" + @config_location + "\""
        end
      end

      def create_resource(resource_name)
        # Check to see if config has a resource with this name
        if !@config.has_key?(resource_name)
          raise "Unable to determine resource: " + resource_name + " from configuration file.  Please check: " + @config_location
          return
        end

        #Use command line arguments for username/password
        if @options.has_key?('username')
          if @options.has_key?('password')
            RestClient::Resource.new(@config[resource_name]['url'], :user => @options['username'], :password => @options['password'])
          else
            #TODO: Create a custom exception to wrap CLI Exceptions
            raise "Password not found for user: " + @options['username']
          end

        #Use config for username/password
        elsif @config[resource_name].has_key?('username')
          if @config[resource_name].has_key?('password')
            RestClient::Resource.new(@config[resource_name]['url'], :user => @config[resource_name]['username'], :password => @config[resource_name]['password'])
          else
            #TODO: Create a custom exception to wrap CLI Exceptions
            raise "Password not found for user: " + @config[resource_name]['username']
          end

        # Do not use authentication
        else
          RestClient::Resource.new(@config[resource_name]['url'])
        end
      end
    end
  end
end