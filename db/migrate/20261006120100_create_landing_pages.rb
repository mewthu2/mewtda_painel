class CreateLandingPages < ActiveRecord::Migration[7.2]
  def change
    create_table :landing_pages do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.string :path_prefix, null: false
      t.string :slug, null: false
      t.string :template, null: false
      t.boolean :active, null: false, default: false
      t.datetime :ends_at
      t.string :product_handles, array: true, null: false, default: []
      t.integer :views_count, null: false, default: 0
      t.timestamps
    end

    add_index :landing_pages, %i[path_prefix slug], unique: true
  end
end
