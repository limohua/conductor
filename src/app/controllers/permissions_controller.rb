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

class PermissionsController < ApplicationController
  before_filter :require_user
  before_filter :set_permissions_header

  def index
    set_permission_object(Privilege::PERM_VIEW)
    @roles = Role.find_all_by_scope(@permission_object.class.name)
    respond_to do |format|
      format.html
      format.json { render :json => @permission_object.as_json }
      format.js { render :partial => 'permissions' }
    end
  end

  def new
    set_permission_object
    @users = User.all
    @roles = Role.find_all_by_scope(@permission_object.class.name)
    if @permission_object == BasePermissionObject.general_permission_scope
      @return_text = t("permissions.new.global_role_grants")
      @summary_text =  t("permissions.new.choose_global_role")
    else
      @return_text =  "#{@permission_object.name} #{@permission_object.class}"
      @summary_text = t('permissions.new.choose_roles')+ " #{@permission_object.class}"
    end
    load_headers
    load_users
    respond_to do |format|
      format.html
      format.js { render :partial => 'new' }
    end
  end

  def create
    set_permission_object
    added=[]
    not_added=[]
    params[:user_role_selected].each do |user_role|
      user_id,role_id = user_role.split(",")
      unless role_id.nil?
        permission = Permission.new(:user_id => user_id,
                                    :role_id => role_id,
                                    :permission_object => @permission_object)
        if permission.save
          added << t('permissions.flash.fragment.user_and_role', :user => permission.user.login,
                      :role => permission.role.name)
        else
          not_added << t('permissions.flash.fragment.user_and_role', :user => permission.user.login,
                          :role => permission.role.name)
        end
      end
    end
    unless added.empty?
      flash[:notice] = t('permissions.flash.notice.added', :list => added.to_sentence)
    end
    unless not_added.empty?
      flash[:error] = t('permissions.flash.error.not_added', :list => not_added.to_sentence)
    end
    if added.empty? and not_added.empty?
      flash[:error] = t "permissions.flash.error.no_users_selected"
    end
    respond_to do |format|
      format.html { redirect_to @return_path }
      format.js { render :partial => 'index',
                    :permission_object_type => @permission_object.class.name,
                    :permission_object_id => @permission_object.id }
    end
  end

  def multi_update
    set_permission_object
    modified=[]
    not_modified=[]
    params[:permission_role_selected].each do |permission_role|
      permission_id,role_id = permission_role.split(",")
      unless role_id.nil?
        permission = Permission.find(permission_id)
        role = Role.find(role_id)
        old_role = permission.role
        unless permission.role == role
          permission.role = role
          if permission.save
            modified << t('permissions.flash.fragment.user_and_role_change', :user => permission.user.login,
                            :old_role => old_role.name,
                            :role => permission.role.name)
          else
            not_modified << t('permissions.flash.fragment.user_and_role_change', :user => permission.user.login,
                            :old_role => old_role.name,
                            :role => permission.role.name)
          end
        end
      end
    end
    unless modified.empty?
      flash[:notice] = t('permissions.flash.notice.modified', :list => modified.to_sentence)
    end
    unless not_modified.empty?
      flash[:error] = t('permissions.flash.error.not_add', :list => not_modified.to_sentence)
    end
    if modified.empty? and not_modified.empty?
      flash[:error] = t("permissions.flash.error.no_users_selected")
    end
    respond_to do |format|
      format.html { redirect_to @return_path }
      format.js { render :partial => 'index',
                    :permission_object_type => @permission_object.class.name,
                    :permission_object_id => @permission_object.id }
    end
  end

  def multi_destroy
    set_permission_object
    deleted=[]
    not_deleted=[]

    Permission.find(params[:permission_selected]).each do |p|
      if check_privilege(Privilege::PERM_SET, p.permission_object) && p.destroy
        deleted << t('permissions.flash.fragment.user_and_role', :user => p.user.login,
                      :role => p.role.name)
      else
        not_deleted << t('permissions.flash.fragment.user_and_role', :user => p.user.login,
                      :role => p.role.name)
      end
    end

    unless deleted.empty?
      flash[:notice] = t('permissions.flash.notice.deleted', :list => deleted.to_sentence)
    end
    unless not_deleted.empty?
      flash[:error] = t('permissions.flash.error.not_deleted', :list => not_deleted.to_sentence)
    end
    respond_to do |format|
      format.html { redirect_to @return_path }
        format.js { render :partial => 'index',
                    :permission_object_type => @permission_object.class.name,
                    :permission_object_id => @permission_object.id }
        format.json { render :json => @permission, :status => :created }
    end

  end
  def destroy
    if request.post?
      p =Permission.find(params[:permission][:id])
      require_privilege(Privilege::PERM_SET, p.permission_object)
      p.destroy
    end
    redirect_to :action => "list",
                :permission_object_type => p.permission_object_type,
                :permission_object_id => p.permission_object_id
  end

  private

  def load_users
    sort_order = params[:sort_by].nil? ? "login" : params[:sort_by]
    @users = User.all(:order => sort_order)
  end

  def load_headers
    @header = [
      { :name => '', :sortable => false },
      { :name => t('users.index.username') },
      { :name => t('users.index.last_name'), :sortable => false },
      { :name => t('users.index.first_name'), :sortable => false },
      { :name => t('role'), :sortable => false }
    ]
  end

  def set_permission_object (required_role=Privilege::PERM_SET)
    obj_type = params[:permission_object_type]
    id = params[:permission_object_id]
    @path_prefix = params[:path_prefix]
    @polymorphic_path_extras = params[:polymorphic_path_extras]
    @use_tabs = params[:use_tabs]
    unless obj_type or id
      @permission_object = BasePermissionObject.general_permission_scope
    end
    @permission_object = obj_type.constantize.find(id) if obj_type and id
    raise RuntimeError, "invalid permission object" if @permission_object.nil?
    if @permission_object == BasePermissionObject.general_permission_scope
      @return_path = permissions_path
      set_admin_users_tabs 'permissions'
    else
      @return_path = send("#{@path_prefix}polymorphic_path",
                          @permission_object.respond_to?(:to_polymorphic_path_param) ?
                              @permission_object.to_polymorphic_path_param(@polymorphic_path_extras) :
                              @permission_object,
                          @use_tabs == "yes" ? {:details_tab => :permissions,
                                                :only_tab => true} : {})
    end
    require_privilege(required_role, @permission_object)
  end
end
