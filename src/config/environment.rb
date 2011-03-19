# 
# Copyright (C) 2009 Red Hat, Inc.
# Written by Scott Seago <sseago@redhat.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.

# Be sure to restart your web server when you modify this file.

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '>= 2.3.2' unless defined? RAILS_GEM_VERSION

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')
require 'util/condormatic'


Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence over those specified here
  # Application configuration should go into files in config/initializers
  # -- all .rb files in that directory are automatically loaded.
  # See Rails::Configuration for more options.

  # Skip frameworks you're not going to use. To use Rails without a database
  # you must remove the Active Record framework.
  # config.frameworks -= [ :active_record, :active_resource, :action_mailer ]

  # Specify gems that this application depends on.
  # They can then be installed with "rake gems:install" on new installations.
  # config.gem "bj"
  # config.gem "hpricot", :version => '0.6', :source => "http://code.whytheluckystiff.net"
  # config.gem "aws-s3", :lib => "aws/s3"
  config.gem "authlogic"
  config.gem "deltacloud-client", :lib => "deltacloud", :version => ">= 0.0.9.8"
  config.gem "haml"
  config.gem "will_paginate"
  config.gem "nokogiri", :version => ">= 1.4.0"
  config.gem "compass", :version => ">= 0.10.2"
  config.gem "compass-960-plugin", :lib => "ninesixty"
  config.gem "simple-navigation"
  config.gem "typhoeus"
  config.gem 'rest-client', :version => '>= 1.6.1'
  config.gem "rb-inotify"
  config.gem 'rack-restful_submit', :version => '1.1.2'
  config.gem 'sunspot_rails', :lib => 'sunspot/rails'
  config.gem 'delayed_job', :version => '~>2.0.4'
  config.gem 'net-scp', :lib => 'net/scp'
  config.gem 'uuidtools'

  config.middleware.swap Rack::MethodOverride, 'Rack::RestfulSubmit'

  config.active_record.observers = :instance_observer, :task_observer, :provider_account_observer
  # Only load the plugins named here, in the order given. By default, all plugins
  # in vendor/plugins are loaded in alphabetical order.
  # :all can be used as a placeholder for all plugins not explicitly named
  # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

  # Add additional load paths for your own custom dirs
  # config.load_paths += %W( #{RAILS_ROOT}/extras )

  # Force all environments to use the same logger level
  # (by default production uses :info, the others :debug)
  # config.log_level = :debug

  # Make Time.zone default to the specified zone, and make Active Record store time values
  # in the database in UTC, and return them converted to the specified local zone.
  # Run "rake -D time" for a list of tasks for finding time zone names. Uncomment to use default local time.
  config.time_zone = 'UTC'

  # Use SQL instead of Active Record's schema dumper when creating the test database.
  # This is necessary if your schema can't be completely dumped by the schema dumper,
  # like if you have constraints or database-specific column types
  # config.active_record.schema_format = :sql

  # Activate observers that should always be running
  # config.active_record.observers = :cacher, :garbage_collector

  # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
  # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}')]
  # config.i18n.default_locale = :de

  config.after_initialize do
    Haml::Template.options[:format] = :html5
    begin
      # This pulls all the possible classad matches from the database and puts
      # them on condor on startup.  Note that this can fail because this is run on startup
      # even for rake db:migrate etc. which won't work since the database doesn't exist
      # yet.
      kick_condor
    rescue Exception => ex
    end
  end
end
