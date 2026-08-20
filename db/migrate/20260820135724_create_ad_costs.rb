class CreateAdCosts < ActiveRecord::Migration[7.2]
  def change
    create_table :ad_costs do |t|
      t.references :client, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0.0

      t.timestamps
    end

    add_index :ad_costs, %i[client_id platform]
    add_index :ad_costs, %i[client_id start_date end_date]
  end
end
