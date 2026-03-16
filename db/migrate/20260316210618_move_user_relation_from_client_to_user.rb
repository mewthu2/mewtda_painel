class MoveUserRelationFromClientToUser < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      UPDATE users
      SET client_id = clients.id
      FROM clients
      WHERE users.id = clients.user_id
    SQL

    remove_reference :clients, :user, foreign_key: true
  end

  def down
    add_reference :clients, :user, foreign_key: true

    execute <<~SQL
      UPDATE clients
      SET user_id = users.id
      FROM users
      WHERE users.client_id = clients.id
    SQL
  end
end