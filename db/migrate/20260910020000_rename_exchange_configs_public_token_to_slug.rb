class RenameExchangeConfigsPublicTokenToSlug < ActiveRecord::Migration[7.2]
  def change
    rename_column :exchange_configs, :public_token, :slug
  end
end
