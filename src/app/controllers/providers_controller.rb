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

class ProvidersController < ApplicationController
  before_filter :require_user
  before_filter :load_providers, :only => [:index, :show, :new, :edit, :create, :update]

  def index
    @params = params
    begin
      @provider = Provider.find(session[:current_provider_id]) if session[:current_provider_id]
    rescue ActiveRecord::RecordNotFound => exc
      logger.error(exc.message)
    ensure
      @provider ||= @providers.first
    end

    respond_to do |format|
      format.html do
        if @providers.present?
          redirect_to edit_provider_path(@provider), :flash => { :notice => flash[:notice], :error => flash[:error] }
        else
          render :action => :index
        end
      end
      format.xml { render :partial => 'list.xml' }
    end

  end

  def new
    require_privilege(Privilege::CREATE, Provider)
    @provider = Provider.new
    @provider.url = Provider::DEFAULT_DELTACLOUD_URL
  end

  def edit
    @provider = Provider.find_by_id(params[:id])
    session[:current_provider_id] = @provider.id
    require_privilege(Privilege::MODIFY, @provider)

    @alerts = provider_alerts(@provider)

    if params.delete :test_provider
      test_connection(@provider)
    end

    load_provider_tabs

    respond_to do |format|
      format.html
      format.js { render :partial => @view }
      format.json { render :json => @provider }
    end

  end

  def show
    @provider = Provider.find(params[:id])
    @realm_names = @provider.realms.collect { |r| r.name }

    require_privilege(Privilege::VIEW, @provider)
    @tab_captions = [t("properties"), t('hw_profiles'), t('realm_s'), t("provider_accounts.index.provider_accounts"), t('services'), t('history'), t('permissions')]
    @details_tab = params[:details_tab].blank? ? t("properties") : params[:details_tab]

    if params.delete :test_provider
      test_connection(@provider)
    end

    respond_to do |format|
      format.html { render :action => 'show' }
      format.js do
        if params.delete :details_pane
          render :partial => 'layouts/details_pane' and return
        end
        render :partial => @details_tab and return
      end
    end
  end

  def create
    require_privilege(Privilege::CREATE, Provider)
    if params[:provider].has_key?(:provider_type_deltacloud_driver)
      provider_type = params[:provider].delete(:provider_type_deltacloud_driver)
      provider_type = ProviderType.find_by_deltacloud_driver(provider_type)
      params[:provider][:provider_type_id] = provider_type.id
    end
    @provider = Provider.new(params[:provider])
    if !@provider.connect
      flash[:warning] = t"providers.flash.warning.connect_failed"
      render :action => "new"
    else
      if @provider.save
        @provider.assign_owner_roles(current_user)
        flash[:notice] = t"providers.flash.notice.added"
        redirect_to edit_provider_path(@provider)
      else
        flash[:warning] = t"providers.flash.error.not_added"
        render :action => "new"
      end
    end
  end

  def update
    @provider = Provider.find_by_id(params[:id])
    require_privilege(Privilege::MODIFY, @provider)
    @provider.attributes = params[:provider]
    provider_disabled = @provider.enabled_changed? && !@provider.enabled
    if @provider.save
      # stop running instances when a provider is disabled
      # it would be better to have this in provider's observer
      # but we need to display error message when an error occurs
      if provider_disabled
        errs = @provider.stop_instances(current_user)
        flash[:error] = errs unless errs.empty?
      end
      flash[:notice] = t"providers.flash.notice.updated"
      redirect_to edit_provider_path(@provider)
    else
      # we reset 'enabled' attribute to real state
      # if save failed
      @provider.reset_enabled!
      unless @provider.connect
        flash.now[:warning] = t"providers.flash.warning.connect_failed"
      else
        flash[:error] = t"providers.flash.error.not_updated"
      end
      load_provider_tabs
      @alerts = provider_alerts(@provider)
      render :action => "edit"
    end
  end

  def destroy
    provider = Provider.find(params[:id])
    require_privilege(Privilege::MODIFY, provider)
    if provider.destroy
      session[:current_provider_id] = nil
      flash[:notice] = t("providers.flash.notice.deleted")
    else
      flash[:error] = t("providers.flash.error.not_deleted", :errors => provider.errors)
    end

    respond_to do |format|
      format.html { redirect_to providers_path }
    end
  end

  def test_connection(provider)
    @provider.errors.clear
    if @provider.connect
      flash.now[:notice] = t"providers.flash.notice.connected"
    else
      flash.now[:warning] = t"providers.flash.warning.connect_failed"
      @provider.errors.add :url
    end
  end

  protected
  def load_providers
    @providers = Provider.list_for_user(current_user, Privilege::VIEW)
  end

  def provider_alerts(provider)
    alerts = []

    # Quota Alerts
    provider.provider_accounts.each do |provider_account|
      unless provider_account.quota.maximum_running_instances == nil
        if provider_account.quota.maximum_running_instances < provider_account.quota.running_instances
          alerts << {
            :class => "critical",
            :subject => "#{t'providers.alerts.subject.quota'}",
            :alert_type => "#{t'providers.alerts.alert_type.quota_exceeded'}",
            :path => edit_provider_provider_account_path(@provider,provider_account),
            :description => "#{t'providers.alerts.description.quota_exceeded', :name => "#{provider_account.name}"}",
            :account_id => provider_account.id
          }
        end

        if (70..100) === provider_account.quota.percentage_used.round
          alerts << {
            :class => "warning",
            :subject => "#{t'providers.alerts.subject.quota'}",
            :alert_type => "#{provider_account.quota.percentage_used.round}% #{t'providers.alerts.alert_type.quota_reached'}",
            :path => provider_provider_account_path(@provider,provider_account),
            :description => "#{provider_account.quota.percentage_used.round}% #{t'providers.alerts.description.quota_reached', :name => "#{provider_account.name}" }",
            :account_id => provider_account.id
          }
        end
      end
    end

    return alerts
  end

  def load_provider_tabs
    @realms = @provider.all_associated_frontend_realms
    #TODO add links to real data for history,properties,permissions
    @tabs = [{:name => t('connectivity'), :view => 'edit', :id => 'connectivity'},
             {:name => t('accounts'), :view => 'provider_accounts/list', :id => 'accounts', :count => @provider.provider_accounts.count},
             {:name => t('realm_s'), :view => 'realms/list', :id => 'realms', :count => @realms.count},
             #{:name => 'Roles & Permissions', :view => @view, :id => 'roles', :count => @provider.permissions.count},
    ]
    add_permissions_tab(@provider, "edit_")
    details_tab_name = params[:details_tab].blank? ? 'connectivity' : params[:details_tab]
    @details_tab = @tabs.find {|t| t[:id] == details_tab_name} || @tabs.first[:name].downcase

    @provider_accounts = @provider.provider_accounts.list_for_user(current_user, Privilege::VIEW).apply_filters(:preset_filter_id => params[:provider_accounts_preset_filter], :search_filter => params[:provider_accounts_search]) if @details_tab[:id] == 'accounts'
    #@permissions = @provider.permissions if @details_tab[:id] == 'roles'

    @view = @details_tab[:view]
  end
end
