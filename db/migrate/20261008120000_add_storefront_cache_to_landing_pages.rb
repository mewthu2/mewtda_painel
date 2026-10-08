class AddStorefrontCacheToLandingPages < ActiveRecord::Migration[7.2]
  def change
    add_column :landing_pages, :storefront_cache, :jsonb, null: false, default: {}
    add_column :landing_pages, :storefront_synced_at, :datetime
  end
end
