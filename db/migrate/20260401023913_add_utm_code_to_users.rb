class AddUtmCodeToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :utm_code, :string
    add_index :users, :utm_code, unique: true
  end
end