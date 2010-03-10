require 'spec_helper'

describe PortalPoolController do

  before(:each) do
    @admin_permission = Factory :admin_permission
    @admin = @admin_permission.user
    activate_authlogic
  end

  it "should provide ui to create new pool" do
     UserSession.create(@admin)
     get :new
     response.should be_success
     response.should render_template("new")
  end

  it "should fail to grant access to new pool ui for unauthenticated user" do
     get :new
     response.should_not be_success
  end

  it "should provider means to create new pool" do
     @instance_creator = Factory :instance_creator

     UserSession.create(@admin)
     lambda do
       post :create, :portal_pool => { :name => 'foopool' }
     end.should change(PortalPool, :count).by(1)
     response.should redirect_to('http://test.host/portal_pool/show/1')
  end


end
