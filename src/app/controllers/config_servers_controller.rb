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
require 'rest_client'

class ConfigServersController < ApplicationController
  before_filter :require_user
  layout 'application'

  def top_section
    :administer
  end

  def edit
    @config_server = ConfigServer.find(params[:id])
    @provider_account = @config_server.provider_account
    require_privilege(Privilege::MODIFY, @provider_account)
  end

  def new
    @provider_account = ProviderAccount.find(params[:provider_account_id])
    require_privilege(Privilege::MODIFY, @provider_account)
    @config_server = ConfigServer.new()
  end

  def test
    config_server = ConfigServer.find(params[:id])
    if not config_server.connection_valid?
      flash[:error] = config_server.connection_error_msg
    else
      flash[:notice] = t('config_servers.flash.notice.test_successful')
    end
    provider_account = config_server.provider_account
    provider = provider_account.provider
    redirect_to provider_provider_account_path(provider, provider_account)
  end

  def create
    @provider_account = ProviderAccount.find(params[:provider_account_id])
    # for now the privileges required to create, modify, or delete a config
    # server are tied to modifying the particular associated provider account
    require_privilege(Privilege::MODIFY, @provider_account)

    @config_server = ConfigServer.new(params[:config_server])
    @config_server.provider_account = @provider_account
    if @config_server.invalid?
      flash[:error] = t('config_servers.flash.error.invalid')
      render :action => 'new' and return
    end
    @config_server.save!
    flash[:notice] = t('config_servers.flash.notice.added')
    redirect_to provider_provider_account_path(@provider_account.provider, @provider_account)
  end

  def update
    @config_server = ConfigServer.find(params[:id])
    @provider_account = @config_server.provider_account
    require_privilege(Privilege::MODIFY, @provider_account)

    if @config_server.update_attributes(params[:config_server])
      flash[:notice] = t('config_servers.flash.notice.updated')
      redirect_to provider_provider_account_path(@provider_account.provider, @provider_account)
    else
      flash[:error] = t('config_servers.flash.error.not_updated')
      render :action => :edit
    end
  end

  def destroy
    @config_server = ConfigServer.find(params[:id])
    require_privilege(Privilege::MODIFY, @config_server.provider_account)
    if ConfigServer.destroy(params[:id])
      flash[:notice] = t('config_servers.flash.notice.deleted')
    else
      flash[:error] = t('config_servers.flash.error.not_deleted')
    end
    provider_account = @config_server.provider_account
    provider = provider_account.provider
    redirect_to provider_provider_account_path(provider, provider_account)
  end
end
