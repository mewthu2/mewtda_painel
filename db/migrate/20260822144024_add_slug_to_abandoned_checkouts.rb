class AddSlugToAbandonedCheckouts < ActiveRecord::Migration[7.2]
  def change
    add_column :abandoned_checkouts, :slug, :string
    add_index :abandoned_checkouts, :slug, unique: true
  end
end
