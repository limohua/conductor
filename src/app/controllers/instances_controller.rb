#
# Copyright (C) 2009 Red Hat, Inc.
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

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'util/condormatic'

class InstancesController < ApplicationController
  before_filter :require_user, :get_nav_items
  before_filter :instance, :only => [:show, :key]
  layout :layout

  def section_id
    'runtime'
  end

  def layout
    return "aggregator" unless request.xhr?
  end

  def index
    @pools = Pool.list_for_user(@current_user, Privilege::INSTANCE_MODIFY)

    @order_dir = params[:order_dir] == 'desc' ? 'desc' : 'asc'
    @order_field = params[:order_field] || 'name'

    # we can't use pool.instances, because we need custom sorting
    @sorted_instances_by_pool = {}
    Instance.find(
      :all,
      :include => [:template, :hardware_profile, :owner, :pool],
      :order => @order_field + ' ' + @order_dir
    ).each do |inst|
      pool_id = inst.pool.id
      next unless @pools.find {|p| p.id == pool_id}
      (@sorted_instances_by_pool[pool_id] ||= []) << inst
    end
  end

  def show
  end

  def key
    unless @instance.instance_key.nil?
      send_data @instance.instance_key.pem,
                :filename => "#{@instance.instance_key.name}.pem",
                :type => "text/plain"
      return
    end
    flash[:warning] = "SSH Key not found for this Instance."
    redirect_to :action => "show", :id => @instance
  end

  def new
    @instance = Instance.new(params[:instance])
    require_privilege(Privilege::INSTANCE_MODIFY, @instance.pool) if @instance.pool
    # FIXME: we need to list only templates for particular user,
    # => TODO: add TEMPLATE_* permissions
    @templates = Template.paginate(
      :page => params[:page] || 1,
      :include => {:images => :replicated_images},
      :conditions => "replicated_images.uploaded = 't'"
    )
  end

  def configure
    @instance = Instance.new(params[:instance])
    require_privilege(Privilege::INSTANCE_MODIFY, @instance.pool)
    # FIXME: change template.architecture to match expected HWP arch strings
    if (@instance.template.architecture == "64-bit")
      arch_value = "x86_64"
    else
      arch_value = "i386"
    end
    @hardware_profiles = HardwareProfile.find(:all, :include => :architecture,
                                   :conditions => {:provider_id => nil,
                                   "hardware_profile_properties.value" => arch_value})
  end

  def create
    if params[:cancel]
      redirect_to :action => 'new', :instance => {:pool_id => params[:instance][:pool_id]}
      return
    end

    @instance = Instance.new(params[:instance])
    @instance.state = Instance::STATE_NEW
    @instance.owner = current_user

    require_privilege(Privilege::INSTANCE_MODIFY,
                      Pool.find(@instance.pool_id))
    #FIXME: This should probably be in a transaction
    if @instance.save!
        @task = InstanceTask.new({:user        => current_user,
                                  :task_target => @instance,
                                  :action      => InstanceTask::ACTION_CREATE})
        if @task.save
          condormatic_instance_create(@task)
          if Quota.can_start_instance?(@instance, nil)
            flash[:notice] = "Instance added."
          else
            flash[:warning] = "Quota Exceeded: Instance will not start until you have free quota"
          end
        else
          @pool = @instance.pool
          render :action => 'configure'
        end
      redirect_to :action => 'index'
    else
      @hardware_profiles = HardwareProfile.all
      render :action => 'configure'
    end
  end

  def instance_action
    params.keys.each do |param|
      if param =~ /^launch_instance_(\d+)$/
        redirect_to :action => 'new', 'instance[pool_id]' => $1
        return
      end
    end

    @instance = Instance.find((params[:id] || []).first)
    require_privilege(Privilege::INSTANCE_CONTROL,@instance.pool)

    if params[:instance_details]
      render :action => 'show'
      return
    end

    if params[:remove_failed]
      action = remove_failed
    else
      # action list will be longer (restart, start, stop..)
      action = if params[:shutdown]
                 'stop'
               #elsif params[:restart]
               #  'restart'
               end

      unless @instance.valid_action?(action)
        raise ActionError.new("'#{action}' is an invalid action.")
      end

      # not sure if task is used as everything goes through condor
      #permissons check here
      @task = @instance.queue_action(@current_user, action)
      unless @task
        raise ActionError.new("#{action} cannot be performed on this instance.")
      end

      case action
        when 'stop'
          condormatic_instance_stop(@task)
        when 'destroy'
          condormatic_instance_destroy(@task)
        when 'start'
          condormatic_instance_create(@task)
        else
          raise ActionError.new("Sorry, action '#{action}' is currently not supported by condor backend.")
      end
    end

    flash[:notice] = "#{@instance.name}: #{action} was successfully queued."
    redirect_to :action => 'index'
  end

  def delete
  end

  def remove_failed
    action ='remove failed'
    raise ActionError.new("#{action} cannot be performed on this instance.") unless
      @instance.state == Instance::STATE_ERROR
    condormatic_instance_reset_error(@instance)
    action
  end

  private

  def instance
    @instance = Instance.find(params[:id])
    require_privilege(Privilege::INSTANCE_VIEW, @instance.pool)
  end

end