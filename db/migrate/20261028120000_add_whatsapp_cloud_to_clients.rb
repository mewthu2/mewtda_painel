class AddWhatsappCloudToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :whatsapp_cloud_phone_number_id, :string
    add_column :clients, :whatsapp_cloud_business_account_id, :string
    add_column :clients, :whatsapp_cloud_access_token, :text
  end
end
