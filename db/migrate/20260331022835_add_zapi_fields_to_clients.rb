class AddZapiFieldsToClients < ActiveRecord::Migration[7.0]
  def change
    add_column :clients, :zapi_instance_id, :string
    add_column :clients, :zapi_instance_token, :string
    add_column :clients, :zapi_client_token, :string
  end
end