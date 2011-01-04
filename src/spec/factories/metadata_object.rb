Factory.define :metadata_object do |o|
  o.key 'key'
  o.value 'value'
  o.object_type nil
end

Factory.define :default_logins_metadata, :parent => :metadata_object do |o|
   o.key 'allow_self_service_logins'
   o.value 'true'
end

Factory.define :default_pool_family_metadata, :parent => :metadata_object do |o|
   o.key 'default_pool_family'
   o.value {Factory.create(:pool_family).id}
   o.object_type 'PoolFamily'
end

Factory.define :default_quota_metadata, :parent => :metadata_object do |o|
  o.key 'self_service_default_quota'
  o.value {Factory.create(:quota).id}
  o.object_type 'Quota'
end

Factory.define :default_role_metadata, :parent => :metadata_object do |o|
  o.key 'self_service_default_role'
  o.value {Factory.create(:role).id}
  o.object_type 'Role'
end

Factory.define :default_pool_metadata, :parent => :metadata_object do |o|
  o.key 'self_service_default_pool'
  o.value {Factory.create(:pool).id}
  o.object_type 'Pool'
end
