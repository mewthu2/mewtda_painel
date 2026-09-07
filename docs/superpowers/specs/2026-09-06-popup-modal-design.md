# Pop-up de cadastro embutível (Marketing) — Design

Data: 2026-09-06

## Objetivo

Permitir que cada cliente cole um `<script>` no site dele que exibe um pop-up de cadastro
(nome, e-mail, telefone). Ao enviar, cadastramos o visitante como cliente na Shopify da loja e
mostramos um cupom fixo configurado no painel. Tudo é configurável em Marketing → "Pop Up"
(título, descrição, cupom, texto do botão, cor, template visual, tamanho, imagem e tempo de
reexibição), e cada envio fica registrado num log dentro do painel.

## Fora de escopo (v1)

- Checkbox de consentimento/LGPD.
- Campos configuráveis (nome/e-mail/telefone são sempre os três, fixos).
- Cupom gerado dinamicamente via Shopify (`Shopify::CreateDiscountCode`) — o cupom é um código
  fixo que o admin já criou manualmente na Shopify e só digita aqui.
- Múltiplos pop-ups por cliente (só existe um `Popup` por `Client`, como um `has_one`).
- Abertura manual via botão/link customizado no site do cliente — só abertura automática.
- Editor de texto rico (WYSIWYG) para título/descrição — campos de texto simples.

## 1. Modelo de dados

### `Popup` (`belongs_to :client`, `Client has_one :popup`)

| campo | tipo | notas |
|---|---|---|
| `client_id` | integer | FK, índice único (1 popup por cliente) |
| `active` | boolean, default false | controla se o widget responde no site do cliente |
| `title` | string | ex.: "Ganhe 10% de desconto!" |
| `description` | text | texto de apoio abaixo do título |
| `coupon_code` | string | código já existente na Shopify, mostrado após o envio |
| `button_text` | string, default "Cadastrar" | |
| `accent_color` | string | hex (`#RRGGBB`), usado no botão e destaque do cupom |
| `template` | string, enum-like | `template_1`..`template_4` (ver seção 5) |
| `size` | string, enum-like | `small` / `medium` / `large` |
| `reappear_after_hours` | integer, default 24 | horas até o pop-up voltar a aparecer pra quem já fechou/enviou |
| `image` | ActiveStorage (`has_one_attached`) | opcional; ignorado no `template_4` (sem imagem) |
| `public_token` | string, índice único, gerado no `before_create` (`SecureRandom.hex(16)`) | identifica o cliente no endpoint público — **não é secreto** (vai no HTML do site do cliente), então nunca deve dar acesso a nada além de ler a config pública e criar submissões |

Validações: `title`, `coupon_code`, `button_text` presentes quando `active: true` (não faz sentido
ativar um pop-up sem título/cupom/botão); `accent_color` no formato hex; `template` e `size`
dentro dos valores aceitos; `reappear_after_hours` inteiro `>= 1`.

### `PopupSubmission` (`belongs_to :popup`)

| campo | tipo | notas |
|---|---|---|
| `popup_id` | integer | FK |
| `name` | string | |
| `email` | string | |
| `phone` | string | |
| `shopify_customer_id` | string, nullable | preenchido quando a criação na Shopify funciona |
| `status` | string, enum-like | `success` / `shopify_error` |
| `created_at` | datetime | (sem `updated_at` — registro é imutável) |

`status: success` cobre tanto "cliente criado" quanto "e-mail já existia" (tratado como sucesso,
conforme decidido). `shopify_error` é qualquer outra falha na chamada à API — a submissão ainda é
salva e o cupom ainda é devolvido ao visitante (não travamos a experiência dele por um erro
nosso).

## 2. Rotas

```ruby
# público, sem autenticação, fora do scope /crm
namespace :widget do
  get  'popup.js',         to: 'popup#script'
  get  'popup/config',     to: 'popup#config'
  post 'popup/submissions', to: 'popup#create_submission'
end

# dentro do scope /crm (autenticado, como hoje)
resource  :popup, only: %i[edit update]
get       'popup/cadastros', to: 'popups#submissions', as: :submissions_popup
```

`Widget::PopupController < ApplicationController` (pra reaproveitar as views `.js.erb`/layout do
projeto), mas com `skip_before_action :authenticate_user!, :redirect_affiliate_to_events!` e
`protect_from_forgery with: :null_session` (precisa aceitar POST de fora do domínio, sem cookie de
sessão nem token CSRF). O CORS já está liberado globalmente
(`config/initializers/cors.rb`, `origins '*'`), então isso já cobre o widget também.

## 3. Widget público (JS embutível)

O cliente cola no site dele:

```html
<script src="https://painel.mewtda.com.br/widget/popup.js" data-token="<public_token>" async></script>
```

Fluxo do script (`Widget::PopupController#script`, `.js.erb`, `content_type: 'application/javascript'`):

1. No load, lê o próprio `data-token` (via `document.currentScript`).
2. Verifica `localStorage['mewtda_popup_dismissed_at']` — se existir e
   `agora - dismissed_at < reappear_after_hours`, não faz mais nada (evita a chamada de rede).
3. Senão, `GET /widget/popup/config?token=...`. Resposta:
   - `{ active: false }` (ou 404/config não encontrada) → widget não faz nada.
   - `{ active: true, title, description, button_text, accent_color, template, size,
     reappear_after_hours, image_url }` → monta o HTML/CSS do modal inline (sem framework),
     injeta no `<body>` e mostra.
4. Fechar o modal (X ou clique fora) → grava `localStorage['mewtda_popup_dismissed_at'] = now`.
5. Enviar o formulário → `POST /widget/popup/submissions` com `token`, `name`, `email`, `phone`.
   - Sucesso (sempre `200` nesse endpoint, mesmo em `shopify_error`, pra não vazar detalhe de
     integração pro visitante) → troca o conteúdo do modal pela tela de cupom
     (`coupon_code` vem na resposta) e grava o mesmo `dismissed_at` no localStorage (não volta a
     aparecer pra quem já se cadastrou, respeitando o mesmo prazo configurado).
   - Falha de rede/validação (campos vazios) → mensagem de erro simples no próprio modal, sem
     fechar.

Validação de e-mail é só client-side (regex simples) — o back-end confia no que a Shopify aceitar
na mutation (se a Shopify rejeitar, cai em `shopify_error` e mesmo assim mostramos o cupom).

## 4. Integração Shopify

Novo `app/services/shopify/create_customer.rb`, seguindo o padrão de
`Shopify::Client`/`Shopify::DiscountService` já existentes:

```ruby
module Shopify
  class CreateCustomer
    def initialize(client)
      @shopify = Shopify::Client.new(client)
    end

    # Retorna o shopify_customer_id em caso de sucesso (inclusive quando o
    # e-mail já existir), ou nil se a chamada falhar por outro motivo.
    def call(name:, email:, phone:)
      ...
    end
  end
end
```

Usa a mutation GraphQL `customerCreate`. Tratamento do erro "e-mail já existe"
(`Shopify` retorna erro de negócio no array `userErrors`, não uma exceção de transporte) —
detectamos esse `userError` específico e buscamos o customer existente por e-mail
(`customerByIdentifier`/query simples) só para preencher `shopify_customer_id` no log; se não
achar por algum motivo, salvamos a submissão como `success` mesmo com `shopify_customer_id: nil`.

`Widget::PopupController#create_submission`:

```ruby
result = Shopify::CreateCustomer.new(popup.client).call(name:, email:, phone:)
status = result[:ok] ? :success : :shopify_error
PopupSubmission.create!(popup: popup, name:, email:, phone:,
                         shopify_customer_id: result[:customer_id], status:)
render json: { coupon_code: popup.coupon_code }
```

Erros inesperados (credenciais Shopify ausentes, timeout etc.) são capturados com
`rescue StandardError` e tratados como `shopify_error` — nunca deixamos a exceção subir e quebrar
a resposta pro visitante.

## 5. Templates visuais (4 variações)

Mesmo motor de HTML/CSS gerado pelo widget; o `template` só muda a disposição:

1. **`template_1` — Centralizado**: imagem no topo (se houver), título/descrição centralizados
   abaixo, campos empilhados, botão full-width.
2. **`template_2` — Imagem à esquerda**: modal dividido 50/50, imagem ocupando a coluna esquerda
   (ou escondida se não houver imagem, form ocupa 100%), formulário na direita.
3. **`template_3` — Imagem à direita**: espelho do `template_2`.
4. **`template_4` — Banner sem imagem**: mais compacto, sem área de imagem — título, descrição
   curta, campos e botão, pensado pra quem não configurou imagem.

`size` (`small`/`medium`/`large`) controla `max-width` do card (ex.: 380px / 520px / 680px) e
escala de padding/fonte — combina com qualquer um dos 4 templates. `accent_color` estiliza o
botão e o destaque do cupom na tela de sucesso, nos 4 templates.

## 6. Painel (Marketing → "Pop Up")

- `_sidebar.html.erb`: item hoje desabilitado "Campanhas" (em `crm-sidebar__link--disabled`,
  "Em breve") vira o link ativo "Pop Up" (`edit_popup_path`), dentro do submenu Marketing —
  substitui o placeholder, não adiciona um item novo.
- `PopupsController` (`app/controllers/popups_controller.rb`), `include ClientScoped`, mesmo
  padrão de `AdCostsController`/`GoalsController`:
  - `edit`/`update`: `@popup = @client.popup || @client.build_popup` — formulário com todos os
    campos configuráveis + upload de imagem + toggle `active` + o `<script>` pronto pra copiar
    (mostrando o `public_token` do cliente, só depois de salvo pela primeira vez — token é gerado
    no create).
  - `submissions`: lista `@client.popup&.popup_submissions&.order(created_at: :desc)`, reusando
    `clients-filters`/`crm-table` (filtro por status e por data, igual ao padrão de `ad_costs` e
    `clients`).
- Duas abas simples no topo da página (`Configuração` / `Cadastros`), navegando entre
  `edit_popup_path` e `submissions_popup_path` — sem JS de tab, é navegação de página mesmo
  (mesmo padrão de páginas com sub-navegação simples já usado no projeto).

## 7. Testes

- `test/models/popup_test.rb`: validações (obrigatórios quando `active`, formato de cor,
  `template`/`size` dentro do enum, unicidade de `public_token`).
- `test/models/popup_submission_test.rb`: validações básicas, enum de `status`.
- `test/services/shopify/create_customer_test.rb`: mock do `Shopify::Client#query` — sucesso,
  e-mail duplicado (`userErrors`), erro de rede.
- `test/controllers/widget/popup_controller_test.rb` (request spec): `config` retorna 404/inativo
  quando `active: false` ou token inválido; `create_submission` cria `PopupSubmission` e retorna
  `coupon_code` tanto no caminho de sucesso quanto no de `shopify_error` (mockando
  `Shopify::CreateCustomer`).
- `test/controllers/popups_controller_test.rb`: `edit`/`update` autenticado, scoped por cliente
  (mesmo padrão dos testes existentes de `ad_costs`/`goals`, se houver).
- Sem teste de JS automatizado (mesmo caso do `navbar-search` — o projeto não tem suíte de JS
  hoje); comportamento do widget (abrir/fechar/reexibição/envio) verificado manualmente no
  navegador contra uma loja de teste.
