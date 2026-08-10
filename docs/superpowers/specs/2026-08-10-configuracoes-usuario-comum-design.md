# Configurações da própria loja para usuário comum

## Problema

O dashboard de vendas (`/painel/vendas`) exibe "Nenhuma integração de anúncio
configurada para este cliente" para usuários comuns (não-admin), mas a única
forma de configurar Meta Ads / Google Ads é `ClientsController#edit`, que
exige `require_admin!`. Usuários comuns não têm como configurar as
integrações do próprio cliente.

## Objetivo

Permitir que um usuário comum acesse e edite as configurações do **próprio**
cliente (somente o seu, nunca outro), incluindo as integrações de anúncio
(Meta Ads, Google Ads), Shopify, Zapi e o toggle do dashboard de vendas. O
único campo que continua exclusivo de admin é `active` (ativar/desativar o
cliente).

## Escopo

### 1. Rota e controller dedicados

Nova rota singular, fora do namespace de admin:

```ruby
resource :settings, path: 'configuracoes', controller: 'settings', only: [:edit, :update]
```

Gera `edit_settings_path` (GET) e `settings_path` (PATCH), montadas dentro do
`scope '/painel'` existente.

`SettingsController`:

- `before_action :authenticate_user!` (herdado do `ApplicationController`).
- `set_client` carrega **sempre** `current_user.client` — nunca lê `:id` da
  URL e não usa `session[:selected_client_id]` (essa lógica de "cliente
  selecionado" é exclusiva do fluxo admin em `ClientScoped`). Isso elimina
  qualquer possibilidade de um usuário comum acessar dados de outro cliente
  through parameter tampering.
- Se `current_user.client` for `nil`, redireciona para `painel_path` com
  alerta "Você não está vinculado a nenhum cliente.".
- `edit` apenas renderiza a view.
- `update` usa os mesmos `client_params` do `ClientsController`, **exceto
  `:active`**, e replica a lógica existente de não sobrescrever
  `meta_access_token` quando enviado em branco. Redireciona de volta para
  `edit_settings_path` com notice/erro, seguindo o padrão de
  `ClientsController#update`.

### 2. View

`app/views/settings/edit.html.erb` renderiza a partial já existente
`clients/_form`, passando `client: @client, read_only: false`. Não há
duplicação de formulário.

### 3. Ajustes na partial `clients/_form.html.erb`

- O bloco "Status" (checkbox `active`) só é renderizado quando
  `current_user.admin?`.
- O bloco "Usuários Vinculados" só é renderizado quando `current_user.admin?`
  (edição de outros usuários continua uma feature exclusiva de admin,
  incluindo o link `edit_user_path`, que é uma rota admin-only).
- Todo o resto do formulário (Informações Básicas exceto Status, Shopify,
  Zapi, Dashboard de Vendas, Meta Ads, Google Ads) permanece igual para os
  dois perfis.

### 4. `GoogleAdsController`

Hoje todas as ações (`connect`, `callback`, `disconnect`) exigem
`require_admin!`. Passam a autorizar por cliente:

- `connect` e `disconnect`: carregam `@client` via `params[:id]` e checam
  `current_user.admin? || current_user.client_id == @client.id`; caso
  contrário, redirect com alerta "Acesso restrito." (mesmo padrão de
  mensagem do `require_admin!` atual, adaptado).
- `callback`: o `client_id` vem do `state` assinado (`message_verifier`), não
  de `params[:id]` — então a mesma checagem de autorização (`admin? ||
  client_id == client.id`) é aplicada depois de resolver o `client` a partir
  do state, antes de persistir o `refresh_token`.
- Redirecionamento pós-ação: `edit_client_path(client)` para admin,
  `edit_settings_path` para usuário comum (helper privado
  `settings_return_path(client)`).

### 5. UX

- Header (`_header.html.erb`): novo item "Configurações" (ícone engrenagem)
  no dropdown do usuário, visível para usuários não-admin e não-afiliados,
  apontando para `edit_settings_path`.
- `sales_dashboard/index.html.erb`: no alerta de "Nenhuma integração de
  anúncio configurada", adiciona um link "Configurar integração" — aponta
  para `edit_settings_path` (usuário comum) ou `edit_client_path(@client)`
  (admin).

### Fora de escopo

- `SalesDashboardController#sync_ad_costs` continua restrito a admin
  (`before_action :require_admin!, only: [:sync_ad_costs]`). Não foi pedido
  e sincronizar custos consome a API de anúncios — fica para uma decisão
  separada do usuário.
- Nenhuma mudança em `ClientsController` (comportamento admin inalterado).

## Testes

- Novo `test/controllers/settings_controller_test.rb`:
  - Usuário comum consegue editar campos do próprio cliente (inclusive Meta
    Ads / Google Ads Customer ID) via `PATCH settings_path`.
  - Usuário comum **não** consegue alterar `active` (campo ignorado
    silenciosamente, sem erro).
  - `GET edit_settings_path` sempre carrega o cliente do usuário logado,
    independente de qualquer parâmetro na URL.
  - Usuário sem `client_id` é redirecionado com alerta.
- Ajustes em `test/controllers/google_ads_controller_test.rb`:
  - Usuário comum autorizado (`connect`/`disconnect`/`callback`) no próprio
    cliente, redirecionando para `edit_settings_path`.
  - Usuário comum **negado** ao tentar `connect`/`disconnect` em cliente
    alheio.
