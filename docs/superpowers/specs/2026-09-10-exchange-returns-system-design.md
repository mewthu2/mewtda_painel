# Sistema de Trocas e Devoluções (vinculado à Shopify)

## Objetivo

Dar a cada cliente (tenant do CRM) uma página pública, com a marca dele,
onde os consumidores finais da loja Shopify podem solicitar troca ou
devolução de itens de um pedido, sem precisar de login. A equipe do
lojista revisa essas solicitações dentro do CRM e decide manualmente o
que fazer na Shopify (reembolso, novo pedido etc.) — o v1 não escreve
nada na Shopify além de gerar cupons na aprovação.

## Fora de escopo (v1)

- Criar o return/exchange nativamente na Shopify via API.
- Aprovação automática ou por regra — sempre manual, feita por alguém
  da equipe do lojista dentro do CRM.
- Seleção de variante de troca (tamanho/cor) pelo cliente final — ele
  só marca "quero trocar" + motivo; a equipe decide o produto novo por
  fora (telefone/WhatsApp etc.).
- Aprovação/rejeição por item — o status é por solicitação inteira.

## Modelo de dados

### `ExchangeConfig` (1:1 com `Client`, mesmo padrão do `Popup`)

Tela única de configuração por cliente.

| campo | tipo | notas |
|---|---|---|
| `client_id` | bigint | |
| `active` | boolean | |
| `company_name` | string | exibido na página pública |
| `logo` | ActiveStorage attachment | |
| `accent_color` | string | `#RRGGBB` |
| `instructions` | text | texto livre na tela pública |
| `return_window_days` | integer, default 7 | janela pra devolução ainda ser permitida |
| `coupon_validity_days` | integer, default 30 | validade do cupom gerado na aprovação (dias a partir de quando é criado) |
| `public_token` | string, único | gerado automaticamente, como em `Popup` |
| `requested_email_subject` / `requested_email_body` | string / text | |
| `approved_email_subject` / `approved_email_body` | string / text | |
| `rejected_email_subject` / `rejected_email_body` | string / text | |
| `completed_email_subject` / `completed_email_body` | string / text | |

Placeholders suportados nos campos de e-mail: `{{customer_name}}`,
`{{order_number}}`, `{{coupon_code}}` (vazio quando não houver cupom).

### `ExchangeRequest`

| campo | tipo | notas |
|---|---|---|
| `client_id` | bigint | |
| `shopify_order_id` | string | id do pedido na Shopify |
| `shopify_order_number` | string | ex.: `#1234` |
| `customer_email` | string | usado na busca e pra enviar os e-mails |
| `customer_name` | string | |
| `status` | enum: `pending` (default), `approved`, `rejected`, `completed` | |
| `internal_notes` | text | anotação da equipe |
| timestamps | | |

### `ExchangeRequestItem`

| campo | tipo | notas |
|---|---|---|
| `exchange_request_id` | bigint | |
| `sku` | string | |
| `product_name` | string | snapshot no momento da solicitação |
| `variant_title` | string | |
| `quantity` | integer | |
| `price` | decimal | preço unitário, snapshot |
| `kind` | enum: `troca`, `devolucao` | por item, não por pedido |
| `reason` | text | |

## Busca do pedido (endpoint público)

Busca **ao vivo** na Admin API da Shopify (via `Shopify::Client`
existente), por número do pedido + e-mail — não usa a tabela local
`orders` porque o sync (`daily_orders_sync_job`) é diário e um pedido
de hoje pode não estar sincronizado ainda.

1. Busca o pedido pelo `name` (número) na loja do `client` dono do
   `public_token`.
2. Confere se o e-mail informado bate com o e-mail do pedido
   (case-insensitive). Se não bater ou o pedido não existir, mensagem
   genérica de "não encontrado" (não revelar qual dos dois campos
   errou).
3. Pedido cancelado (`cancelled_at` presente) → bloqueado, mensagem
   específica.

**Segurança:** número do pedido + e-mail funcionam como par
"segredo compartilhado" (mesmo modelo da própria página de status de
pedido da Shopify). Ainda assim, adicionar rate limit leve por
IP/token no endpoint de busca (ex.: `rack-attack` já usado no projeto,
se houver, ou um throttle simples) pra dificultar varredura de números
de pedido sequenciais.

## Regra de elegibilidade

Calculada a partir de `fulfilled_at` do pedido (data de
entrega/despacho) e `return_window_days` da `ExchangeConfig`:

- `fulfilled_at` em branco → nem troca nem devolução disponíveis
  ainda; mensagem "aguardando envio".
- `hoje - fulfilled_at <= return_window_days` → troca **ou**
  devolução disponíveis, por item.
- `hoje - fulfilled_at > return_window_days` → só troca disponível;
  devolução desabilitada na UI com explicação do motivo.

## Fluxo público

Namespace `widget` (mesmo padrão de `Popup`), página cheia (não
popup/overlay), identificada por `public_token`:

`GET /widget/exchanges/:token` → wizard de 3 passos, server-rendered
(ERB, sem SPA):

1. **Identificação** — logo/marca do cliente (via `ExchangeConfig`),
   formulário com número do pedido + e-mail.
2. **Seleção** — lista os itens do pedido com a elegibilidade
   calculada; cliente marca quais itens, escolhe troca/devolução por
   item (dentro do permitido) e motivo.
3. **Confirmação** — cria `ExchangeRequest` + `ExchangeRequestItem`s
   com status `pending`; dispara e-mail "solicitado".

## Fluxo interno (CRM)

- `resource :exchange_config, only: %i[edit update]` — tela de
  configuração (branding, janela de dias, validade do cupom, os 4
  pares de assunto/corpo de e-mail), seguindo exatamente o padrão de
  `PopupsController`.
- `resources :exchange_requests, only: %i[index show update]` —
  listagem com filtro por status, detalhe com os itens, campo de nota
  interna, e ações de aprovar/rejeitar/marcar concluído.
- Entrada nova no sidebar (`app/views/layouts/partials/_sidebar.html.erb`).

## E-mails e cupom

Não existe nenhum envio de e-mail de fato no sistema ainda (só
`Ses::DomainIdentityService`, que verifica domínio de envio). Este
projeto constrói a primeira infraestrutura de envio real:

- **`Ses::SendEmailService`** (novo) — usa `Aws::SESV2::Client` e o
  `client.email_sending_domain` já verificado pra montar o
  remetente; renderiza um HTML simples (logo + `accent_color` da
  `ExchangeConfig` + corpo com placeholders substituídos).
- **`SendExchangeEmailJob`** (novo, ActiveJob/Sidekiq, mesmo padrão dos
  outros jobs do projeto) — recebe `exchange_request_id` e `kind`
  (`requested`/`approved`/`rejected`/`completed`), monta o e-mail a
  partir dos campos correspondentes da `ExchangeConfig` e chama o
  `Ses::SendEmailService`.
- Se `client.ses_domain_verified?` for falso, o job loga um aviso e
  não envia — nunca bloqueia o fluxo de troca/aprovação.

### Pontos de disparo

| evento | e-mail | cupom? |
|---|---|---|
| `ExchangeRequest` criada | `requested` | não |
| equipe aprova (`status = approved`) | `approved` | sim, se houver item(ns) `kind: troca` |
| equipe rejeita (`status = rejected`) | `rejected` | não |
| equipe marca concluído (`status = completed`) | `completed` | não |

### Cupom na aprovação

- Soma `price × quantity` de todos os `ExchangeRequestItem` com
  `kind: troca` na solicitação aprovada → valor fixo do cupom. Itens
  `devolucao` não entram na conta (reembolso é tratado manualmente,
  fora do sistema).
- Sem itens `troca` na solicitação → aprovação não gera cupom, só
  dispara o e-mail `approved` sem `{{coupon_code}}`.
- Validade: `starts_at = agora`, `ends_at = agora + coupon_validity_days`.
- **`Shopify::CreateDiscountCode`** (existente, hoje só cria desconto
  percentual) precisa ganhar suporte a valor fixo (`DiscountAmount` já
  é aceito pela mutation `discountCodeBasicCreate` da Shopify — só
  falta o parâmetro no serviço Ruby).

## Premissas assumidas (sinalizar se algo estiver errado)

- Elegibilidade e aprovação são no nível da solicitação/pedido, não
  por item individual dentro do fluxo de aprovação (o `kind` é por
  item só na escolha do cliente, não na decisão da equipe).
- Cupom de troca é um valor fixo (BRL), não percentual.
- Validade do cupom é por duração (dias a partir da geração), não um
  intervalo de calendário fixo.
- Se o pedido não tiver `fulfilled_at`, nenhuma opção é liberada ainda
  (nem troca, nem devolução).
