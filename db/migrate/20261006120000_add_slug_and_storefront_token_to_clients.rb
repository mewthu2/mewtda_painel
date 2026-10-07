class AddSlugAndStorefrontTokenToClients < ActiveRecord::Migration[7.2]
  class MigrationClient < ActiveRecord::Base
    self.table_name = 'clients'
  end

  def up
    add_column :clients, :slug, :string
    add_column :clients, :shopify_storefront_token, :string

    # Backfill: slug a partir do nome, desambiguando com sufixo numérico.
    used = []
    MigrationClient.order(:id).each do |client|
      base = client.name.to_s.parameterize.presence || "cliente-#{client.id}"
      candidate = base
      candidate = "#{base}-#{client.id}" if used.include?(candidate)
      used << candidate
      client.update_columns(slug: candidate)
    end

    add_index :clients, :slug, unique: true
  end

  def down
    remove_index :clients, :slug
    remove_column :clients, :shopify_storefront_token
    remove_column :clients, :slug
  end
end
