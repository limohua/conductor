# -*- coding: utf-8 -*-
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

# -*- coding: utf-8 -*-
require 'spec_helper'

describe Provider do
  context "(using stubbed out connect method)" do
    before(:each) do
      @client = mock('DeltaCloud').as_null_object
      @provider = Factory.build(:mock_provider)
      @provider.stub!(:connect).and_return(@client)
    end

    it "should return a client object" do
      @provider.send(:valid_framework?).should be_true
    end

    it "should validate mock provider" do
      @provider.should be_valid
    end

    it "should require a valid name" do
      long_name = ""
      256.times { long_name << 'a' }

      [nil, "", "£*(&", long_name].each do |invalid_value|
        @provider.name = invalid_value
        @provider.should_not be_valid
      end
    end

    it "should require a valid provider_type" do
        @provider.provider_type = nil
        @provider.should_not be_valid
    end

    it "should require a valid url" do
      [nil, ""].each do |invalid_value|
        @provider.url = invalid_value
        @provider.should_not be_valid
      end
    end

    it "should be able to connect to the specified framework" do
      @provider.should be_valid
      @provider.connect.should_not be_nil

      @provider.url = "http://invalid.provider/url"
      @provider.stub(:connect).and_return(nil)
      deltacloud = @provider.connect
      @provider.should have(1).error_on(:url)
      @provider.errors[:url].first.should eql("must be a valid provider url")
      @provider.should_not be_valid
      deltacloud.should be_nil
    end

    it "should require unique name" do
      @provider.save!
      provider2 = Factory.build :mock_provider
      provider2.stub!(:connect).and_return(@client)
      provider2.should be_valid

      provider2.name = @provider.name
      provider2.should_not be_valid
    end

    it "should set valid cloud type" do
      @client.driver_name = @provider.provider_type
      @provider.provider_type = nil
      @provider.provider_type = ProviderType.find_by_deltacloud_driver "mock"
      @provider.should be_valid
    end

    it "should not destroy provider if deletion of associated cloud account fails" do
      # TODO: front end HW profiles are not deleted with provider, which
      # involves "External name is already used" error.
      # This should be solved when implementing "Scripted import of Hardware Profiles
      # from EC2" scenario, then it's possible to delete this line
      # note: same situation will be with images
      HardwareProfile.destroy_all

      instance = FactoryGirl.create(:instance)
      provider = instance.provider_account.provider
      provider.destroyed?.should be_false
    end

    it "should return all associated frontend realms" do
      provider1 = Factory.create(:mock_provider)
      frontend_realm = FactoryGirl.create :frontend_realm
      backend_realm = FactoryGirl.create :backend_realm, :provider => provider1
      t = RealmBackendTarget.create!(:frontend_realm => frontend_realm, :realm_or_provider => backend_realm)
      provider1.all_associated_frontend_realms.count.should == 1
      t.destroy
      provider1.realms.reload
      provider1.frontend_realms.reload
      provider1.all_associated_frontend_realms.count.should == 0
      RealmBackendTarget.create!(:frontend_realm => frontend_realm, :realm_or_provider => provider1)
      provider1.realms.reload
      provider1.frontend_realms.reload
      provider1.all_associated_frontend_realms.count.should == 1
    end

    it "should stop all associated instances" do
      provider1 = Factory.create(:mock_provider)
      pa = FactoryGirl.create(:mock_provider_account, :provider => provider1)
      inst1 = FactoryGirl.create(:instance, :provider_account => pa)
      inst2 = FactoryGirl.create(:instance, :provider_account => pa)
      errs = provider1.stop_instances(nil)
      errs.should be_empty
    end

  end

  context "(using original connect method)" do
    it "should log errors when connecting to invalid url" do
      @logger = mock('Logger').as_null_object
      @provider = Factory.build(:mock_provider)
      @provider.stub!(:logger).and_return(@logger)

      @provider.logger.should_receive(:error).twice
      @provider.url = "http://invalid.provider/url"
      @provider.connect.should be_nil
    end
  end

end
