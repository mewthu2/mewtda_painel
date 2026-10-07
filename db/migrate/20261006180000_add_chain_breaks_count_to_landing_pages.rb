class AddChainBreaksCountToLandingPages < ActiveRecord::Migration[7.2]
  def change
    add_column :landing_pages, :chain_breaks_count, :integer, null: false, default: 0
  end
end
