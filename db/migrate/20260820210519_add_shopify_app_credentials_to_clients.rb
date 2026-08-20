class AddShopifyAppCredentialsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :shopify_api_key, :string
    add_column :clients, :shopify_api_secret, :string
  end
end
