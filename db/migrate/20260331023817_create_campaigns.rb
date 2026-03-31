class CreateCampaigns < ActiveRecord::Migration[7.2]
  def change
    create_table :campaigns do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :kind, default: 0, null: false
      t.text :message
      t.integer :days_after_purchase, default: 7
      t.date :start_date
      t.date :end_date
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :campaigns, [:client_id, :kind]
    add_index :campaigns, [:start_date, :end_date]
  end
end