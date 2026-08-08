# Dashboard de Vendas (ROAS/CAC mensal) — Design

Data: 2026-08-08

## Objetivo

Criar um dashboard mensal, ativável por cliente, com cinco métricas:

- Ticket médio
- Faturamento (vendas brutas − descontos)
- Taxa de conversão
- ROAS faturado
- CAC

As métricas usam os pedidos da Shopify já sincronizados pelo painel, cruzados com o gasto
de anúncio (Google Ads + Meta Ads) do mesmo mês. Um filtro opcional permite restringir os
pedidos por tag da Shopify (ex.: `VendedoraElo`). O dashboard é ativado/desativado por
cliente numa tela de admin.

## Fora de escopo (v1)

- Google Analytics (GA4) como fonte de custo ou de sessões — a taxa de conversão usa os
  eventos já coletados via `ShopifyEvent` (pixel próprio), não GA4.
- Sincronização automática/agendada do custo de anúncio — é sob demanda (botão), no mesmo
  padrão do sync de pedidos da Shopify que já existe.
- Seleção de contas Google Ads via API (lista de contas acessíveis) — o Customer ID é
  digitado manualmente pelo admin.

## 1. Modelo de dados

### `clients` (novas colunas)

| coluna | tipo | notas |
|---|---|---|
| `sales_dashboard_enabled` | boolean, default: false | toggle do admin |
| `meta_access_token` | string, encrypted | token de longa duração (System User) colado pelo admin |
| `meta_ad_account_id` | string | ex.: `act_1234567890` |
| `google_ads_customer_id` | string | Customer ID de 10 dígitos, digitado pelo admin |
| `google_ads_refresh_token` | string, encrypted | obtido via OAuth |
| `google_ads_connected_at` | datetime | nil = não conectado |

`meta_access_token` e `google_ads_refresh_token` usam `encrypts` (Active Record Encryption,
já disponível no Rails 7.2) — mesmo nível de sensibilidade que `shopify_access_token`
merece, mas esse último hoje está em texto plano; não vamos mexer nele nesta spec.

### `orders` (novas colunas)

Hoje `orders.tags` existe na tabela mas **nunca é preenchido** pelo sync, e não há nenhum
campo com o valor bruto/desconto/total do pedido vindo da Shopify (`Order#total` é
recalculado a partir de `order_items`, que não reflete desconto a nível de pedido).

| coluna | tipo | notas |
|---|---|---|
| `subtotal_price` | decimal(12,2) | vendas brutas, pré-desconto |
| `total_discounts` | decimal(12,2) | |
| `total_price` | decimal(12,2) | valor líquido; usado como Faturamento |
| `cancelled_at` | datetime | usado para excluir pedidos cancelados do cálculo |

### Nova tabela `ad_cost_snapshots`

| coluna | tipo | notas |
|---|---|---|
| `client_id` | bigint, FK | |
| `platform` | string | `google_ads` \| `meta` |
| `year` | integer | |
| `month` | integer | 1–12 |
| `cost` | decimal(12,2) | |
| `fetched_at` | datetime | |

Índice único em `[client_id, platform, year, month]`.

Guardar o valor buscado (em vez de calcular ao vivo a cada view) evita bater na API a cada
carregamento do dashboard e preserva o histórico mesmo que o acesso à conta de anúncio seja
revogado depois.

## 2. Sync da Shopify (extensão de `Shopify::Orders`)

- `Shopify::Orders.sync_shopify_orders_to_rails` e `OrdersUpdateJob#sync_single_order`
  passam a pedir os campos `tags,subtotal_price,total_discounts,total_price,cancelled_at`
  além dos já buscados.
- `create_or_update_order_from_shopify` grava esses campos no `Order`.
- Nenhuma mudança na cadência ou no gatilho do sync.
- Backfill dos pedidos já existentes: rodar de novo
  `Shopify::Orders.sync_shopify_orders_to_rails(..., time_range: :all)` por cliente — é
  upsert (`find_or_initialize_by` + `assign_attributes`), não duplica pedidos.

## 3. Cálculo das métricas — `Sales::MonthlyMetrics`

PORO que encapsula todo o cálculo, testável isoladamente e usado pelo controller:

```ruby
Sales::MonthlyMetrics.new(client:, year:, month:, tag: nil).call
# => {
#      revenue:, gross_sales:, discounts:, avg_ticket:, conversion_rate:,
#      roas:, cac:, orders_count:, ad_cost:, new_customers_count:,
#      ad_cost_available:
#    }
```

Regras:

- **Escopo de pedidos**: `Order.where(client_id:, shopify_creation_date: mês, cancelled_at: nil)`.
  Se `tag` for passada (ex.: `"VendedoraElo"`), filtra adicionalmente com
  `tags ILIKE "%#{tag}%"` — filtro opcional, não é o padrão do dashboard.
- **Faturamento** = `Σ total_price` do escopo (já líquido de desconto, inclui frete/imposto
  — decisão explícita, ver seção de trade-offs). Vendas brutas = `Σ subtotal_price`,
  Descontos = `Σ total_discounts` — mostrados como quebra ao lado do KPI principal.
- **Ticket médio** = Faturamento / nº de pedidos do escopo. `0` pedidos → `nil` (exibido
  como "—").
- **Taxa de conversão** = nº de pedidos do escopo / sessões únicas no mês
  (`ShopifyEvent` com `kind: "page_viewed"`, `distinct session_id`, mesmo client, mesmo
  mês) × 100. A tag, quando aplicada, filtra só os pedidos — sessões continuam sendo o
  total da loja, já que uma sessão não carrega a tag de um pedido que ainda não existe.
- **Custo de anúncio do mês** = soma de `ad_cost_snapshots.cost` do client/ano/mês para as
  plataformas `google_ads` e `meta`. Se não houver snapshot para alguma/nenhuma
  plataforma, `ad_cost_available` vem `false` e ROAS/CAC são `nil` ("—") em vez de `0`.
- **ROAS faturado** = Faturamento / Custo de anúncio.
- **Clientes novos** = clientes com pedido no mês cujo pedido mais antigo (entre **todos**
  os pedidos desse client, não só o mês) caiu dentro do mês selecionado.
- **CAC** = Custo de anúncio / nº de clientes novos. `0` clientes novos → "—".

## 4. Integração de custo de anúncio

### Meta Ads — token colado (sem OAuth no app)

O cliente gera um *System User token* de longa duração no próprio Business Manager
(não expira, não depende de login humano) e o admin cola esse token + o Ad Account ID no
cadastro do cliente (`clients/_form.html.erb`, campos mascarados como
`shopify_access_token` já é hoje).

`Meta::MonthlyCostFetcher.new(client:, year:, month:).call` chama
`GET /act_<id>/insights?fields=spend&time_range={since,until}` com o token do cliente e
retorna o gasto do mês como Decimal.

### Google Ads — OAuth por cliente (único caminho possível; a API não aceita chave)

- Botão "Conectar Google Ads" na tela de edição do cliente (admin) → redireciona para o
  consentimento OAuth do Google (`scope: https://www.googleapis.com/auth/adwords`),
  levando o `client_id` no `state` (assinado, para validar no callback).
- Callback troca o `code` pelo refresh token e grava em `google_ads_refresh_token`
  (encrypted) + `google_ads_connected_at`.
- Precisa de 3 env vars novas a nível de app: `GOOGLE_ADS_CLIENT_ID`,
  `GOOGLE_ADS_CLIENT_SECRET`, `GOOGLE_ADS_DEVELOPER_TOKEN`.
- **Pré-requisito fora do código**: o Developer Token exige cadastro e aprovação da Google
  (Basic Access) no nível da própria Mewtda — isso não é algo que este projeto resolve
  sozinho; precisa ser encaminhado separadamente antes da integração funcionar em
  produção.
- `GoogleAds::MonthlyCostFetcher.new(client:, year:, month:).call` consulta
  `metrics.cost_micros` agregado no período, usando o refresh token do cliente + developer
  token do app, e retorna o gasto do mês como Decimal.

### Sincronização

- `AdCostSyncJob` (por client, por plataforma) chama o fetcher correspondente e faz upsert
  em `ad_cost_snapshots`.
- Disparo: sob demanda, por um botão "Sincronizar custos" na tela do dashboard (admin) —
  mesmo padrão de sync manual que já existe hoje para pedidos da Shopify
  (`OrdersUpdateJob`).
- Falha (token expirado/revogado): o dashboard mostra o erro com atalho para reconectar
  (Google Ads) ou para atualizar o token colado (Meta).

## 5. Dashboard, toggle de admin e navegação

### Rota e controller

`GET /painel/vendas` → `SalesDashboardController#index`.

- Gate: usuário não-admin cujo `@client.sales_dashboard_enabled?` é falso → redirect para
  `/painel` com aviso. Admin sempre acessa (para configurar/testar antes de habilitar para
  o cliente).
- Parâmetros: `year`, `month` (padrão: mês atual), navegação mês anterior/próximo, filtro
  opcional `tag`.
- Usa `Sales::MonthlyMetrics` para montar os 5 KPIs + quebra de vendas brutas/descontos.
- Se `ad_cost_available` for `false`: ROAS/CAC mostram "—" com aviso "Custos do mês não
  sincronizados" + botão (admin) "Sincronizar custos" que dispara `AdCostSyncJob`.

### Toggle de admin

`clients/_form.html.erb` ganha um checkbox "Dashboard de Vendas habilitado" (mesmo padrão
visual do checkbox `active` já existente) → adicionado em `client_params`.

### Navegação

Em `_header.html.erb`, novo link "Vendas" ao lado do link "Dashboard" existente, visível
apenas se `@client&.sales_dashboard_enabled?` (ou sempre visível para admin).

## 6. Testes

- `Sales::MonthlyMetrics`: unidade cobrindo cada fórmula, filtro de tag, mês sem pedidos,
  sem custo sincronizado, cliente novo vs. recorrente, divisão por zero em cada métrica.
- `SalesDashboardController`: teste de request garantindo que o gate
  (`sales_dashboard_enabled`) bloqueia cliente não-admin e libera admin.
- `GoogleAds::MonthlyCostFetcher` / `Meta::MonthlyCostFetcher`: HTTP mockado, cobrindo
  resposta válida e token expirado/revogado.
- Sync da Shopify: teste garantindo que `tags`, `subtotal_price`, `total_discounts`,
  `total_price` e `cancelled_at` são persistidos ao processar um pedido vindo da Shopify.

## Decisões e trade-offs assumidos nesta spec

- **Faturamento usa `total_price`** (líquido de desconto, mas inclui frete/imposto), não
  `subtotal_price - total_discounts` puro. Vendas brutas e descontos aparecem como quebra
  informativa ao lado do KPI.
- **Tag é filtro opcional**, nunca o padrão — o dashboard mostra as vendas totais da loja
  por padrão.
- **Taxa de conversão usa sessões do `ShopifyEvent`**, não GA4.
- **GA4 fica fora do escopo** desta v1 como fonte de custo.
- **CAC conta só clientes novos** (primeiro pedido no mês), não o total de pedidos.
- **Sync de custo é sob demanda** (botão), não agendado automaticamente.
