#
#   Copyright 2011 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

# == Schema Information
#
# Table name: instances
#
#  id                      :integer         not null, primary key
#  external_key            :string(255)
#  name                    :string(1024)    not null
#  hardware_profile_id     :integer         not null
#  frontend_realm_id       :integer
#  owner_id                :integer
#  pool_id                 :integer         not null
#  provider_account_id     :integer
#  instance_hwp_id         :integer
#  public_addresses        :string(255)
#  private_addresses       :string(255)
#  state                   :string(255)
#  last_error              :text
#  lock_version            :integer         default(0)
#  acc_pending_time        :integer         default(0)
#  acc_running_time        :integer         default(0)
#  acc_shutting_down_time  :integer         default(0)
#  acc_stopped_time        :integer         default(0)
#  time_last_pending       :datetime
#  time_last_running       :datetime
#  time_last_shutting_down :datetime
#  time_last_stopped       :datetime
#  created_at              :datetime
#  updated_at              :datetime
#  deployment_id           :integer
#  assembly_xml            :text
#  instance_config_xml     :text
#  image_uuid              :string(255)
#  image_build_uuid        :string(255)
#  provider_image_uuid     :string(255)
#  provider_instance_id    :string(255)
#  user_data               :string(255)
#  uuid                    :string(255)
#  secret                  :string(255)
#

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'util/deployable_xml'
require 'util/instance_config_xml'

class Instance < ActiveRecord::Base
  class << self
    include CommonFilterMethods
  end
  include PermissionedObject

  cattr_reader :per_page
  @@per_page = 15

  belongs_to :pool
  belongs_to :provider_account
  belongs_to :deployment

  belongs_to :hardware_profile
  belongs_to :frontend_realm
  belongs_to :owner, :class_name => "User", :foreign_key => "owner_id"
  belongs_to :instance_hwp

  has_one :instance_key, :dependent => :destroy
  has_many :permissions, :as => :permission_object, :dependent => :destroy,
           :include => [:role],
           :order => "permissions.id ASC"
  has_many :events, :as => :source, :dependent => :destroy
  has_many :instance_parameters, :dependent => :destroy
  after_create "assign_owner_roles(owner)"

  validates_presence_of :pool_id
  validates_presence_of :hardware_profile_id

  #validates_presence_of :external_key
  # TODO: can we do uniqueness validation on indirect association
  # -- pool.account.provider
  #validates_uniqueness_of :external_key, :scope => :provider_id

  validates_presence_of :name
  validates_uniqueness_of :name, :scope => :pool_id
  validates_length_of :name, :maximum => 1024

  before_create :generate_uuid

  STATE_NEW            = "new"
  STATE_PENDING        = "pending"
  STATE_RUNNING        = "running"
  STATE_SHUTTING_DOWN  = "shutting_down"
  STATE_STOPPED        = "stopped"
  STATE_CREATE_FAILED  = "create_failed"
  STATE_ERROR          = "error"

  STATES = [STATE_NEW, STATE_PENDING, STATE_RUNNING,
             STATE_SHUTTING_DOWN, STATE_STOPPED, STATE_CREATE_FAILED,
             STATE_ERROR]

  scope :deployed,  :conditions => { :state => [STATE_RUNNING, STATE_SHUTTING_DOWN] }
  # FIXME: "pending" is misleading as it doesn't just cover STATE_PENDING
  scope :pending,   :conditions => { :state => [STATE_NEW, STATE_PENDING] }
  # FIXME: "failed" is misleading too...
  scope :failed,    :conditions => { :state => [STATE_CREATE_FAILED, STATE_ERROR] }
  scope :stopable,    :conditions => { :state => [STATE_NEW, STATE_PENDING, STATE_RUNNING] }
  scope :ascending_by_name, :order => 'name ASC'


  SEARCHABLE_COLUMNS = %w(name state)

  validates_inclusion_of :state,
     :in => STATES

  validate :pool_and_account_enabled_validation, :on => :create

  before_destroy :destroyable?
  before_destroy :destroy_on_provider
  # A user should only be able to update certain attributes, but the API may permit other attributes to be
  # changed if called from another Aeolus component, so attr_protected isn't quite what we want:
  USER_MUTABLE_ATTRS = ['name']

  def object_list
    super + [pool, deployment]
  end
  class << self
    alias orig_list_for_user_include list_for_user_include
    alias orig_list_for_user_conditions list_for_user_conditions
  end

  def self.list_for_user_include
    includes = orig_list_for_user_include
    includes << { :pool => {:permissions => {:role => :privileges}},
                  :deployment => {:permissions => {:role => :privileges}}}
    includes
  end

  def self.list_for_user_conditions
    "(#{orig_list_for_user_conditions}) or
     (permissions_deployments.user_id=:user and
      privileges_roles.target_type=:target_type and
      privileges_roles.action=:action) or
     (permissions_pools.user_id=:user and
      privileges_roles_2.target_type=:target_type and
      privileges_roles_2.action=:action)"
  end

  def get_action_list(user=nil)
    # return empty list rather than nil
    # FIXME: not handling pending state now -- only current state
    return_val = InstanceTask.valid_actions_for_instance_state(state,
                                                               self,
                                                               user) || []
    # filter actions based on quota
    # FIXME: not doing quota filtering now
    return_val
  end

  def pool_and_account_enabled_validation
    errors.add(:pool, I18n.t('pools.errors.must_be_enabled')) unless pool and pool.enabled?
    errors.add(:pool, I18n.t('pools.errors.providers_disabled')) if pool and pool.pool_family.all_providers_disabled?
  end


  def image
    Aeolus::Image::Warehouse::Image.find(image_uuid) if image_uuid
  end

  def image_build
    Aeolus::Image::Warehouse::ImageBuild.find(image_build_uuid) if image_build_uuid
  end

  def build
    image_build || (image.nil? ? nil : image.latest_pushed_build)
  end

  def provider_images_for_match(provider_account)
    if (the_build = build)
      the_build.provider_images_by_provider_and_account(
       provider_account.provider.name, provider_account.warehouse_id)
    else
      []
    end
  end

  def assembly_xml
    @assembly_xml ||= AssemblyXML.new(self[:assembly_xml].to_s)
  end

  def instance_config_xml
    if not self[:instance_config_xml].nil?
      @instance_config_xml ||= InstanceConfigXML.new(self[:instance_config_xml].to_s)
    end
  end

  # Provide method to check if requested action exists, so caller can decide
  # if they want to throw an error of some sort before continuing
  # (ie in service api)
  def valid_action?(action)
    return get_action_list.include?(action) ? true : false
  end

  def queue_action(user, action, data = nil)
    return false unless get_action_list.include?(action)
    task = InstanceTask.new({ :user        => user,
                              :task_target => self,
                              :action      => action,
                              :args        => data})
    task.save!
    return task
  end

  # Returns the total time that this instance has been in the state
  def total_state_time(state)

    if !STATES.include?(state)
      return I18n.t('instances.errors.invalid_state')
    end

    case state
      when STATE_PENDING
        if self.state == STATE_PENDING
          return acc_pending_time + (Time.now - time_last_pending)
        else
          return acc_pending_time
        end

      when STATE_RUNNING
        if self.state == STATE_RUNNING
          return acc_running_time + (Time.now - time_last_running)
        else
          return acc_running_time
        end

      when STATE_SHUTTING_DOWN
        if self.state == STATE_SHUTTING_DOWN
          return acc_shutting_down_time + (Time.now - time_last_shutting_down)
        else
          return acc_shutting_down_time
        end

      when STATE_STOPPED
        if self.state == STATE_STOPPED
          return acc_stopped_time + (Time.now - time_last_stopped)
        else
          return acc_stopped_time
        end

      else
        return I18n.t('state_not_monitored')
    end
  end

  def create_auth_key
    raise "instance provider_account is not set" unless self.provider_account
    client = self.provider_account.connect
    return nil unless client && client.feature?(:instances, :authentication_key)
    if key = client.create_key(:name => key_name)
      self.instance_key = InstanceKey.create!(:pem => key.pem, :name => key.id, :instance => self)
      self.save!
    end
  end

  def self.get_user_instances_stats(user)
    stats = {
      :running_instances => 0,
      :stopped_instances => 0,
    }

    instances = []
    pools = Pool.list_for_user(user, Privilege::VIEW, Instance)
    pools.each{|pool| pool.instances.each {|i| instances << i}}
    instances.each do |i|
      if i.state == Instance::STATE_RUNNING
        stats[:running_instances] += 1
      elsif i.state == Instance::STATE_STOPPED
        stats[:stopped_instances] += 1
      end
    end
    stats[:total_instances] = instances.size
    return stats
  end

  USER_DATA_VERSION = "1"
  OAUTH_SECRET_SEED = [('a'..'z'),('A'..'Z'),(0..9)].map{|i| i.to_a}.flatten
  def self.generate_oauth_secret
    # generates a string of between 40 and 50 characters consisting of a
    # random selection of alphanumeric (upper and lower case) characters
    (0..(rand(10) + 40)).map { OAUTH_SECRET_SEED[rand(OAUTH_SECRET_SEED.length)] }.join
  end

  def self.generate_user_data(instance, config_server)
    ["#{USER_DATA_VERSION}|#{config_server.endpoint}|#{instance.uuid}|#{instance.secret}"].pack("m0").delete("\n")
  end

  def restartable?
    # TODO: we don't support stateful instances yet, so it's `false` for the time being.
    # In the meantime, we can use this method to write validation code for cases
    # where does matter whether an instance is stateful or stateless.
    false
  end

  def destroyable?
    (state == STATE_CREATE_FAILED) or (state == STATE_STOPPED and not restartable?)
  end

  def failed?
    state == Instance::STATE_CREATE_FAILED || state == Instance::STATE_ERROR
  end

  def requires_config_server?
    not instance_config_xml.nil? or assembly_xml.requires_config_server?
  end

  def self.list(order_field, order_dir)
    #Instance.all(:include => [ :owner ],
    #             :order => (order_field || 'name') +' '+ (order_dir || 'asc'))
    includes(:owner).order((order_field || 'name') +' '+ (order_dir || 'asc'))
  end

  class Match
    attr_reader :pool_family, :provider_account, :hwp, :provider_image, :realm

    def initialize(pool_family, provider_account, hwp, provider_image, realm)
      @pool_family = pool_family
      @provider_account = provider_account
      @hwp = hwp
      @provider_image = provider_image
      @realm = realm
    end

    def ==(other)
      self.pool_family == other.pool_family &&
        self.provider_account == other.provider_account &&
        self.hwp == other.hwp &&
        self.provider_image == other.provider_image &&
        self.realm == other.realm
    end
  end

  def image_arch
    # try to get architecture of the image associated with this instance
    # for imported images template is empty -> architecture is not set,
    # in this case we omit this check
    return Aeolus::Image::Warehouse::Image.find(build.image.uuid).os.arch
  rescue
    logger.warn "failed to get image architecture for instance '#{name}', skipping architecture check: #{$!}"
    logger.warn $!.backtrace.join("\n  ")
    nil
  end

  def matches
    errors = []
    if pool.pool_family.provider_accounts.empty?
      errors << I18n.t('instances.errors.no_provider_accounts')
    end
    errors << I18n.t('instances.errors.pool_quota_reached') if pool.quota.reached?
    errors << I18n.t('instances.errors.pool_family_quota_reached') if pool.pool_family.quota.reached?
    errors << I18n.t('instances.errors.user_quota_reached') if owner.quota.reached?
    errors << I18n.t('instances.errors.image_not_found', :b_uuid=> image_build_uuid, :i_uuid => image_uuid) if image_build.nil? and image.nil?
    arch = image_arch
    if arch.present? and hardware_profile.architecture and hardware_profile.architecture.value != arch
      errors << I18n.t('instances.errors.architecture_mismatch', :inst_arch => hardware_profile.architecture.value, :img_arch => arch)
    end
    return [[], errors] unless errors.empty?

    matched = []
    pool.pool_family.provider_accounts.each do |account|
      account.instance_matches(self, matched, errors)

    end

    [matched, errors]
  end

  def self.csv_export(instances)
    csv_string = FasterCSV.generate(:col_sep => ";", :row_sep => "\r\n") do |csv|
      event_attributes = Event.new.attributes.keys.reject {|key| key if key == "created_at" || key == "updated_at"}

      csv << event_attributes.map {|event| event.capitalize }

      events = instances.map{|i| i.events}.flatten!
      unless events.nil?
        events.each do |event|
          csv << event_attributes.map {|event_attribute| event[event_attribute] }
        end
      end
    end
    csv_string
  end

  scope :with_hardware_profile, lambda {
      {:include => :hardware_profile}
  }

  def as_json(options={})
    available_actions = get_action_list
    json = super(options).merge({
      :provider => provider_account ? provider_account.provider.name : '',
      :has_key => !(instance_key.nil?),
      :uptime => ApplicationHelper.count_uptime(uptime),
      :stop_enabled => available_actions.include?(InstanceTask::ACTION_STOP),
      :reboot_enabled => available_actions.include?(InstanceTask::ACTION_REBOOT),
      :is_failed => failed?
    })

    json[:owner] = owner.name if owner.present?

    json
  end

  def first_running?
    not deployment.instances.deployed.any? {|i| i != self}
  end

  # find the list of possibles that will accommodate all of the instances
  def self.matches(instances)
    matches = nil
    errors = []
    instances.each do |instance|
      m, e = instance.matches
      if matches.nil?
        matches = m.dup
      else
        matches.delete_if {|match| not m.include?(match) }
      end
      errors << e
    end
    # For now, this only checks the account's quota to see whether all the
    # instances can launch there
    # TODO:  Determine if there's more to check here
    matches.reject! do |match|
      rejected = false
      if !match.provider_account.quota.can_start? instances
        errors << I18n.t('instances.errors.provider_account_quota_too_low', :match_provider_account => match.provider_account)
        rejected = true
      end
      rejected
    end
    [matches, errors]
  end

  def stop
    do_operation('stop')
  end

  def reboot
    do_operation('reboot')
  end

  def deployed?
    [STATE_RUNNING, STATE_SHUTTING_DOWN].include?(state)
  end

  def uptime
    deployed? ? (Time.now - time_last_running) : 0
  end

  PRESET_FILTERS_OPTIONS = [
    {:title => I18n.t("instances.preset_filters.other_than_stopped"), :id => "other_than_stopped", :query => where("instances.state != ?", "stopped")},
    {:title => I18n.t("instances.preset_filters.create_failed"), :id => "create_failed", :query => where("instances.state" => "create_failed")},
    {:title => I18n.t("instances.preset_filters.stopped"), :id => "stopped", :query => where("instances.state" => "stopped")},
    {:title => I18n.t("instances.preset_filters.running"), :id => "running", :query => where("instances.state" => "running")},
    {:title => I18n.t("instances.preset_filters.pending"), :id => "pending", :query => where("instances.state" => "pending")}
  ]

  def destroy_on_provider
    if (provider_account.provider.provider_type.deltacloud_driver != "ec2" or
        provider_account.provider.provider_type.deltacloud_driver != "mock") and state != STATE_CREATE_FAILED
      retries = 0
      begin
        retries += 1
        @task = self.queue_action(self.owner, 'destroy')
        unless @task
          raise ActionError.new(t"instance.errors.cannot_destroy")
        end
        Taskomatic.destroy_instance(@task)
      rescue Exception => e
        if self.tasks.last.action != 'destroy' or retries < 500
          retry
        end
      end
    end
  end

  private

  def self.apply_search_filter(search)
    if search
      where("instances.name ILIKE :search OR instances.state ILIKE :search", :search => "%#{search}%")
    else
      scoped
    end
  end

  def key_name
    "#{self.name}_#{Time.now.to_i}_key_#{self.object_id}".gsub(/[^a-zA-Z0-9\.\-]/, '_')
  end

  def generate_uuid
    self[:uuid] = UUIDTools::UUID.timestamp_create.to_s
  end

  def do_operation(operation)
    @task = self.queue_action(@current_user, operation)
    unless @task
      raise ActionError.new(t("instances.errors.#{operation}_not_be_performed"))
    end
    Taskomatic.send("#{operation}_instance", @task)
  end

end
