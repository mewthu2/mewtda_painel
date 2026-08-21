class CreateGoals < ActiveRecord::Migration[7.2]
  def change
    create_table :goals do |t|
      t.references :client, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :month, null: false
      t.decimal :revenue_target, precision: 12, scale: 2
      t.decimal :roas_target, precision: 6, scale: 2

      t.timestamps
    end

    add_index :goals, %i[client_id year month], unique: true
  end
end
