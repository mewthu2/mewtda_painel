class AddShopifyCredentialsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :shopify_shop_url, :string
    add_column :clients, :shopify_access_token, :string

    add_index :clients, :shopify_shop_url, unique: true
  end
end
