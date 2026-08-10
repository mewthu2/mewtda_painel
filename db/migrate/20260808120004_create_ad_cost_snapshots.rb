class CreateAdCostSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :ad_cost_snapshots do |t|
      t.references :client, null: false, foreign_key: true
      t.string :platform, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.decimal :cost, precision: 12, scale: 2, null: false, default: 0
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :ad_cost_snapshots, [:client_id, :platform, :year, :month],
              unique: true, name: 'index_ad_cost_snapshots_on_client_platform_month'
  end
end
