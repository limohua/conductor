require 'spec_helper'

describe ProviderController do

  before(:each) do
    Factory :base_portal_object
    @admin_permission = Factory :provider_admin_permission
    @provider = @admin_permission.permission_object
    @admin = @admin_permission.user
    activate_authlogic
  end


  it "should provide ui to view accounts" do
     UserSession.create(@admin)
     get :accounts, :id => @provider.id
     response.should be_success
     response.should render_template("accounts")
  end

  it "should provide ui to create new account" do
     UserSession.create(@admin)
     get :new_account, :id => @provider.id
     response.should be_success
     response.should render_template("new_account")
  end

  it "should fail to grant access to account UIs for unauthenticated user" do
     get :accounts
     response.should_not be_success

     get :new_account
     response.should_not be_success
  end

end
