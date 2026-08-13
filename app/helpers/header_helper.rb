module HeaderHelper
  # Lista de telas/menus buscáveis na navbar. Espelha manualmente as mesmas
  # condicionais de visibilidade de app/views/layouts/partials/_sidebar.html.erb
  # e do dropdown de usuário em _header.html.erb — não é gerada a partir deles,
  # então qualquer mudança de visibilidade de menu precisa ser replicada aqui.
  def searchable_nav_items(user)
    return affiliate_nav_items(user) if user.profile_id == Profile::AFFILIATE

    items = [{ label: 'Trackeamento site', url: crm_path, icon: 'fa-solid fa-chart-line' }]

    if user.admin? || user.client.present?
      items << { label: 'Vendas', url: sales_dashboard_path, icon: 'fa-solid fa-sack-dollar' }
    end

    items += [
      { label: 'Pedidos', url: orders_path, icon: 'fa-solid fa-box' },
      { label: 'Clientes', url: customers_path, icon: 'fa-solid fa-users' },
      { label: 'Produtos', url: products_path, icon: 'fa-solid fa-bag-shopping' },
      { label: 'Campanhas', url: campaigns_path, icon: 'fa-solid fa-bullseye' },
      { label: 'Afiliados', url: affiliates_path, icon: 'fa-solid fa-user-group' },
      { label: 'Automações', url: crm_path, icon: 'fa-solid fa-robot' }
    ]

    items += user.admin? ? admin_nav_items : [{ label: 'Configurações', url: edit_settings_path, icon: 'fa-solid fa-gear' }]

    items
  end

  private

  def affiliate_nav_items(user)
    [{ label: 'Meus Eventos', url: events_path(utm_code: user.utm_code), icon: 'fa-solid fa-chart-line' }]
  end

  def admin_nav_items
    [
      { label: 'Usuários', url: users_path, icon: 'fa-solid fa-user' },
      { label: 'Clientes', url: clients_path, icon: 'fa-solid fa-building' },
      { label: 'Perfis', url: profiles_path, icon: 'fa-solid fa-id-badge' },
      { label: 'Sidekiq', url: '/crm/sidekiq', icon: 'fa-solid fa-bolt' },
      { label: 'Try-On Virtual', url: try_on_index_path, icon: 'fa-solid fa-wand-magic-sparkles' }
    ]
  end
end
