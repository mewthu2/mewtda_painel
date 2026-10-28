# Todas as consultas da tela "Trackeamento site" filtram por cliente + período
# (created_at), e não havia índice pra isso: o Postgres varria todos os eventos
# do cliente. CONCURRENTLY pra não travar a tabela, que recebe eventos do pixel
# o tempo todo.
class AddClientCreatedAtIndexToShopifyEvents < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :shopify_events, [:client_id, :created_at], algorithm: :concurrently, if_not_exists: true
  end
end
