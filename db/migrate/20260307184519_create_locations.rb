class CreateLocations < ActiveRecord::Migration[7.0]
  def change
    create_table :locations do |t|
      t.string :slug
      t.string :name
      t.decimal :kpi_ratio, precision: 10, scale: 4
      t.datetime :kpi_updated_at
      t.string :shopify_location_id

      t.timestamps
    end

    add_index :locations, :slug, unique: true
    add_index :locations, :shopify_location_id, unique: true
  end
end