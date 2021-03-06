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

class RenameCloudAccountsPoolFamiliesToProviderAccountsPoolFamilies < ActiveRecord::Migration
  def self.up
    rename_table :cloud_accounts_pool_families, :pool_families_provider_accounts
    rename_column :pool_families_provider_accounts, :cloud_account_id, :provider_account_id
  end

  def self.down
    rename_column :pool_families_provider_accounts, :provider_account_id, :cloud_account_id
    rename_table :pool_families_provider_accounts, :cloud_accounts_pool_families
  end
end
