class AddSiteUrlToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :site_url, :string
  end
end
