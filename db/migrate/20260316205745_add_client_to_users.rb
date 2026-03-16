class AddClientToUsers < ActiveRecord::Migration[7.0]
  def change
    add_reference :users, :client, foreign_key: true, index: true, null: true
  end
end