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

require 'spec_helper'

describe Deployment do
  before(:each) do
    @quota = FactoryGirl.create :quota
    @pool = FactoryGirl.create(:pool, :quota_id => @quota.id)
    @deployment = Factory.build(:deployment, :pool_id => @pool.id)
    @hwp1 = FactoryGirl.create(:front_hwp1)
    @hwp2 = FactoryGirl.create(:front_hwp2)
    @actions = ['start', 'stop']
  end

  it "should require pool to be set" do
    @deployment.should be_valid

    @deployment.pool_id = nil
    @deployment.should_not be_valid
  end

  it "should require a pool that is not disabled" do
    @deployment.should be_valid

    @deployment.pool.enabled = false
    @deployment.should_not be_valid
  end

# This is in flux, and currently inapplicable
#  it "should require deployable to be set" do
#    @deployment.legacy_deployable_id = nil
#    @deployment.should_not be_valid
#
#    @deployment.legacy_deployable_id = 1
#    @deployment.should be_valid
#  end

  it "should have a name of reasonable length" do
    [nil, '', 'x'*1025].each do |invalid_name|
      @deployment.name = invalid_name
      @deployment.should_not be_valid
    end
    @deployment.name = 'x'*1024
    @deployment.should be_valid

  end

  it "should have unique name" do
    @deployment.save!
    second_deployment = Factory.build(:deployment,
                                    :pool_id => @deployment.pool_id,
                                    :name => @deployment.name)
    second_deployment.should_not be_valid

    second_deployment.name = 'unique name'
    second_deployment.should be_valid
  end

  it "should tell apart valid and invalid actions" do
    @deployment.stub!(:get_action_list).and_return(@actions)
    @deployment.valid_action?('invalid action').should == false
    @deployment.valid_action?('start').should == true
  end

  it "should return action list" do
    @deployment.get_action_list.should eql(["start", "stop", "reboot"])
  end


  it "should return properties hash" do
    @deployment.properties.should be_a_kind_of(Hash)
    @deployment.properties.should == {:created=>nil, :pool=>@deployment.pool.name, :owner=>"John  Smith", :name=>@deployment.name}
  end

  it "should be removable under with stopped or create_failed instances" do
    @deployment.save!
    inst1 = Factory.create :mock_running_instance, :deployment_id => @deployment.id
    inst2 = Factory.create :mock_running_instance, :deployment_id => @deployment.id

    @deployment.should_not be_destroyable
    @deployment.destroy.should == false

    inst1.state = Instance::STATE_CREATE_FAILED
    inst1.save!
    inst2.state = Instance::STATE_STOPPED
    inst2.save!

    @deployment = Deployment.find(@deployment.id)
    @deployment.should be_destroyable
    expect { @deployment.destroy }.to change(Deployment, :count).by(-1)
  end

  it "should return start_time once an instance has started" do
    @deployment.save!
    @deployment.start_time.should be_nil
    instance = Factory.create :mock_pending_instance, :deployment_id => @deployment.id
    instance.save!
    @deployment.start_time.should be_nil
    instance.state = Instance::STATE_RUNNING
    instance.save!
    @deployment.start_time.should_not be_nil
  end

  it "should return end_time once an instance has started and stopped" do
    @deployment.save!
    instance = Factory.create :mock_pending_instance, :deployment_id => @deployment.id
    instance.save!
    instance.state = Instance::STATE_RUNNING
    instance.save!
    @deployment.end_time.should be_nil
    instance.state = Instance::STATE_STOPPED
    instance.save!
    @deployment.end_time.should_not be_nil
  end

  it "should log events as instances start and stop" do
    @deployment.save!
    instance1 = Factory.create :mock_pending_instance, :deployment_id => @deployment.id
    instance2 = Factory.create :mock_pending_instance, :deployment_id => @deployment.id
    instance1.save!
    @deployment.events.where(:status_code => 'first_running').should be_empty
    instance1.state = Instance::STATE_RUNNING
    instance1.save!
    @deployment.events.where(:status_code => 'first_running').should be_present
    @deployment.events.where(:status_code => 'all_running').should be_empty
    instance2.state = Instance::STATE_RUNNING
    instance2.save!
    @deployment.events.where(:status_code => 'all_running').should be_present
    # Now test stop events
    instance1.state = Instance::STATE_STOPPED
    instance1.save!
    @deployment.events.where(:status_code => 'some_stopped').should be_present
    @deployment.events.where(:status_code => 'all_stopped').should_not be_present
    instance2.state = Instance::STATE_STOPPED
    instance2.save!
    @deployment.events.where(:status_code => 'all_stopped').should be_present
  end


  describe "using image from iwhd" do
    before do
      image_id = @deployment.deployable_xml.assemblies.first.image_id
      @provider_image = provider_name = Aeolus::Image::Warehouse::Image.find(image_id).latest_pushed_build.provider_images.first
      provider_name = @provider_image.provider_name
      provider1 = FactoryGirl.create(:mock_provider, :name => provider_name)
      provider2 = FactoryGirl.create(:mock_provider)
      @provider_account1 = FactoryGirl.create(:mock_provider_account, :label => 'testaccount', :provider => provider1, :priority => 10)
      @provider_account2 = FactoryGirl.create(:mock_provider_account, :label => 'testaccount2', :provider => provider2, :priority => 20)
      @deployment.pool.pool_family.provider_accounts = [@provider_account2, @provider_account1]
      admin_perms = FactoryGirl.create :admin_permission
      @user_for_launch = admin_perms.user
    end

    it "should return errors when checking assemblies matches which are not launchable" do
        @deployment.check_assemblies_matches(@user_for_launch).should be_empty
        @deployment.pool.pool_family.provider_accounts.destroy_all
        @deployment.check_assemblies_matches(@user_for_launch).should_not be_empty
    end

    it "should launch instances when launching deployment" do
      @deployment.save!
      @deployment.instances.should be_empty

      Taskomatic.stub!(:create_instance).and_return(true)
      @deployment.launch(@user_for_launch)[:errors].should be_empty
      @deployment.instances.count.should == 2
    end

    it "should match provider accounts according to priority when launching deployment" do
      @deployment.save!
      @deployment.instances.should be_empty

      Instance.any_instance.stub(:provider_images_for_match).and_return([@provider_image])
      Taskomatic.stub!(:create_dcloud_instance).and_return(true)
      Taskomatic.stub!(:handle_dcloud_error).and_return(true)
      Taskomatic.stub!(:handle_instance_state).and_return(true)
      @deployment.launch(@user_for_launch)[:errors].should be_empty
      @deployment.reload
      @deployment.instances.count.should == 2
      @deployment.instances[0].provider_account.should == @provider_account1
      @deployment.instances[1].provider_account.should == @provider_account1
      @provider_account1.priority = 30
      @provider_account1.save!
      deployment2 = Factory.create(:deployment, :pool_id => @pool.id)
      deployment2.launch(@user_for_launch)[:errors].should be_empty
      deployment2.reload
      deployment2.instances.count.should == 2
      deployment2.instances[0].provider_account.should == @provider_account2
      deployment2.instances[1].provider_account.should == @provider_account2
    end

    it "should not launch instances if user has no access to hardware profile" do
      @deployment.save!
      @deployment.instances.should be_empty

      Taskomatic.stub!(:create_instance).and_return(true)
      @deployment.launch(@user_for_launch)[:errors].should be_empty
      @deployment.instances.count.should == 2
    end

  end

  it "should be able to stop running instances on deletion" do
    @deployment.save!
    inst1 = Factory.create :mock_running_instance, :deployment_id => @deployment.id
    inst2 = Factory.create :mock_running_instance, :deployment_id => @deployment.id

    @deployment.stop_instances_and_destroy!

    # this emulates Condor stopping the actual instances
    # and dbomatic reflecting the changes back to Conductor
    inst1.state = Instance::STATE_STOPPED; inst1.save!
    inst2.state = Instance::STATE_STOPPED; inst2.save!


    # verify that the deployment and all its instances are deleted
    lambda {Deployment.find(@deployment.id)}.should raise_error(ActiveRecord::RecordNotFound)
    lambda {Instance.find(inst1.id)}.should raise_error(ActiveRecord::RecordNotFound)
    lambda {Instance.find(inst2.id)}.should raise_error(ActiveRecord::RecordNotFound)
  end

  it "should be return nil if deployment has no events " do
    deployment = Factory :deployment
    deployment.uptime_1st_instance.should be_nil
    deployment.uptime_all.should be_nil
  end

  it "should return false if no deployed instances" do
    deployment = Factory.build :deployment
    instance = Factory.build(:mock_running_instance, :deployment => deployment)
    instance2 = Factory.build(:mock_pending_instance, :deployment => deployment)
    deployment.stub(:instances){[instance, instance2]}
    deployment.any_instance_running?.should be_true
    instance.state = Instance::STATE_PENDING
    deployment.any_instance_running?.should be_false
  end

  it "should return mixed if instances have differing states" do
    deployment = Factory.build :deployment
    instance = Factory.build(:mock_running_instance, :deployment => deployment)
    instance2 = Factory.build(:mock_pending_instance, :deployment => deployment)
    deployment.stub(:instances){[instance, instance2]}
    deployment.deployment_state.should == Deployment::STATE_MIXED
  end

  it "should not have any instance parameters" do
    @deployment = Factory.build :deployment
    instance = Factory.build(:mock_running_instance, :deployment => @deployment)
    @deployment.stub(:instances){[instance]}
    @deployment.instances[0].instance_parameters.should be_empty
  end

  it "should have instance parameters" do
    d = Factory.build :deployment_with_launch_parameters
    instance = Factory.build(:mock_running_instance, :deployment => d)
    d.stub(:instances){[instance]}
    d.instances[0].instance_parameters.count.should >= 0
  end
end
