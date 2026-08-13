# Home personalizada com prévia de vendas — Design

Data: 2026-08-12

## Objetivo

Quando um usuário logado (Admin ou Usuário comum) acessa `/`, em vez da página institucional
pública, ele vê uma saudação personalizada ("Olá, {nome}") e uma prévia do novo dashboard de
vendas: 3 cards com gráfico de tendência diária do mês corrente — Faturamento, Pedidos e Ticket
Médio — usando dados que já vêm do Shopify (sem depender de Meta/Google Ads configurado).
Serve como "novidade" atual do sistema e chamada pro dashboard completo (`/crm/vendas`).

Usuário deslogado continua vendo a página institucional pública, sem nenhuma mudança.

## Fora de escopo (v1)

- Sistema genérico de "novidades" (banco de dados, versionamento, dispensar/marcar como visto).
  Esta é uma tela fixa — trocar o conteúdo no futuro é editar a view de novo.
- ROAS/CAC/Taxa de conversão na prévia — dependem de integração de anúncio (Meta/Google Ads),
  que a maioria dos clientes não tem configurada; ficam só no dashboard completo.
- Qualquer alteração no dashboard completo (`/crm/vendas`) em si.

## 1. Roteamento e público

`HomeController#index` (rota `/`, já existe, `skip_before_action :authenticate_user!`)
passa a ramificar:

- **Deslogado**: renderiza a view institucional atual (`home/index.html.erb`), sem alteração.
- **Logado, perfil Afiliado** (`Profile::AFFILIATE`): redirecionado para `/events`, como já
  acontece em quase todo o resto do sistema. Implementação: remover a exceção
  `return if controller_name == 'home'` de `ApplicationController#redirect_affiliate_to_events!`
  — como esse método só roda depois de `user_signed_in?` ser true, usuários deslogados não são
  afetados.
- **Logado, Admin ou Usuário comum**: renderiza a nova view `home/dashboard.html.erb`.

`HomeController#index` decide qual view renderizar com base em `user_signed_in?`.

## 2. Dados — `Sales::DailyBreakdown`

Novo serviço em `app/services/sales/daily_breakdown.rb`, seguindo o mesmo padrão de
`Sales::MonthlyMetrics` (já existe, usado pelo dashboard completo):

```ruby
Sales::DailyBreakdown.new(client:, year:, month:).call
# => {
#   days: [1, 2, 3, ..., N],           # dias do mês, só até o dia atual se for o mês corrente
#   revenue_by_day: [120.0, 0.0, ...], # total_price por dia
#   orders_by_day: [2, 0, ...],        # contagem de pedidos por dia
#   avg_ticket_by_day: [60.0, nil, ...], # revenue_by_day[i] / orders_by_day[i], nil se 0 pedidos
#   revenue_total: 1234.56,
#   orders_total: 20,
#   avg_ticket_total: 61.73,           # nil se orders_total == 0
#   has_data: true                     # orders_total > 0
# }
```

Consulta: `Order.not_cancelled.where(client_id:, shopify_creation_date: mês_corrente)`, agrupado
por dia (`shopify_creation_date.to_date`). Mesmo escopo de "pedido válido" que `Sales::MonthlyMetrics`
já usa (via `Order.not_cancelled`).

`HomeController#index` monta esses dados só quando `current_user.client` existe (ver seção 4).

## 3. View — `home/dashboard.html.erb`

Estrutura:

```
Olá, {current_user.name}

[3 crm-card lado a lado (grid responsivo, empilha em mobile)]
  Faturamento          Pedidos              Ticket Médio
  R$ 1.234,56           20                   R$ 61,73
  [gráfico de área]     [gráfico de barras]  [gráfico de linha]

[Botão "Ver dashboard completo" → /crm/vendas]
```

- Reaproveita `.crm-card` e os tokens de cor/dark-mode do design system já existente. Título dos
  cards no estilo `.crm-kpi-card__label`/`.crm-kpi-card__value` (mesmas classes do dashboard
  completo, `app/assets/stylesheets/pages/sales_dashboard.scss`).
- Gráficos com ApexCharts (já carregado globalmente via `//= require apexcharts`, já usado em
  `/crm` e `/crm/events` — sem dependência nova). Tipo de gráfico por card: Faturamento = área,
  Pedidos = barras, Ticket Médio = linha — mesma escolha visual do dashboard de eventos existente.
- Cores dos gráficos seguem os tokens do design system (`--primary` etc.) em vez de hex fixo,
  pra funcionar em claro/escuro (implementação vai usar `getComputedStyle` pra ler as CSS custom
  properties, já que ApexCharts não lê `var(--...)` direto em JS).
- Botão "Ver dashboard completo" sempre aparece e sempre aponta pra `/crm/vendas` — se o cliente
  não tiver o dashboard completo habilitado, a própria `SalesDashboardController#ensure_dashboard_access!`
  já redireciona com alerta explicando; não duplicamos essa checagem aqui.

## 4. Estados vazios

- **`current_user.client` é nil** (típico de conta Admin pura, sem cliente vinculado): mostra só
  "Olá, {nome}" + uma mensagem convidando a selecionar um cliente no menu superior (mesmo texto
  já usado em `ClientScoped#set_client` pra Admin: `'Nenhum cliente selecionado. Selecione um
  cliente no menu superior.'`). Não tenta montar `Sales::DailyBreakdown` sem cliente.
- **Cliente existe mas `has_data` é `false`** (zero pedidos no mês corrente — loja nova ou
  Shopify ainda não sincronizado): os 3 cards continuam aparecendo, com valores zerados (R$ 0,00
  / 0 / R$ 0,00) e uma mensagem amigável abaixo dos números, tipo "Assim que suas vendas
  começarem a chegar, esse gráfico ganha vida" — sem tentar desenhar um ApexCharts vazio sem
  contexto nenhum.

## 5. Testes

- `test/services/sales/daily_breakdown_test.rb`: mês com pedidos em dias variados (soma correta
  por dia, total correto), mês sem pedidos nenhum (`has_data: false`, arrays zerados), pedido
  cancelado excluído do cálculo (reaproveitando o mesmo padrão de teste de `Sales::MonthlyMetrics`
  se existir um).
- `test/controllers/home_controller_test.rb` (criar se não existir): usuário deslogado vê a
  página institucional; usuário comum logado com cliente vê a nova view; usuário comum logado
  sem cliente vê o estado vazio de "selecione um cliente" sem erro; afiliado logado é
  redirecionado pra `/events`; admin logado vê a nova view.

## Decisões que ficam para depois (fora de escopo, mas vale registrar)

- Se um dia quiserem trocar o conteúdo da "novidade" sem deploy, aí sim vale considerar um
  registro no banco — não faz sentido agora com uma única novidade.
- Período fixo em "mês corrente" — não há seletor de mês nesta tela (isso já existe no
  dashboard completo).
