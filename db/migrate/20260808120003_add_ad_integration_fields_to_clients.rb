class AddAdIntegrationFieldsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :meta_access_token, :string
    add_column :clients, :meta_ad_account_id, :string
    add_column :clients, :google_ads_customer_id, :string
    add_column :clients, :google_ads_refresh_token, :string
    add_column :clients, :google_ads_connected_at, :datetime
  end
end
