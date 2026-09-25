class AddEmailSendingConfigToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :email_sending_domain, :string
    add_column :clients, :ses_verification_status, :string, null: false, default: 'unverified'
    add_column :clients, :ses_dkim_tokens, :string, array: true, null: false, default: []
    add_column :clients, :ses_verified_at, :datetime
  end
end
