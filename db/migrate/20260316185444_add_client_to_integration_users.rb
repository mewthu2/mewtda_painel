class AddClientToIntegrationUsers < ActiveRecord::Migration[7.2]
  def change
    add_reference :integration_users, :client, null: false, foreign_key: true
  end
end