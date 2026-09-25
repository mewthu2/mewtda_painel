# E-mail Marketing — Templates (Design)

Data: 2026-09-07

## Objetivo

Dar ao cliente uma tela completa de "E-mail Marketing" pra criar e-mails a partir de templates
prontos (editados em blocos, sem HTML/rich text), com preview ao vivo, e marcar cada e-mail com
uma finalidade/gatilho (boas-vindas, carrinho abandonado, cliente inativo, pós-compra, cashback,
ou envio manual). Segue o mesmo padrão de `Popup` (blocos simples + preview inline) e de
`Campaign` (um registro guarda conteúdo + tipo de gatilho + configuração do gatilho em jsonb).

## Fora de escopo (v1)

- Envio de e-mail de verdade (mailer, SMTP/API de e-mail, job de disparo). Esta etapa só cria e
  configura o template; o mecanismo de envio será definido numa conversa separada.
- Editor de HTML puro ou rich text (WYSIWYG) — conteúdo é sempre por campos fixos (blocos), igual
  ao `Popup`.
- Múltiplos designs de e-mail por gatilho (um cliente pode ter vários `EmailTemplate` com o mesmo
  `trigger_kind`, sem restrição — não impomos "só um template de boas-vindas").
- Duplicar template (pode vir depois, não foi pedido).
- Envio de e-mail de teste a partir do preview.
- Dados de aniversário do cliente (`Customer` não tem campo de nascimento hoje) — por isso não
  entra gatilho de aniversário nesta v1.

## 1. Modelo de dados

### `EmailTemplate` (`belongs_to :client`, `Client has_many :email_templates, dependent: :destroy`)

| campo | tipo | notas |
|---|---|---|
| `client_id` | integer | FK |
| `name` | string | nome interno, só aparece na listagem (ex.: "Carrinho abandonado — padrão") |
| `subject` | string | assunto do e-mail |
| `heading` | string | título grande dentro do e-mail |
| `body` | text | parágrafo principal |
| `button_text` | string | texto do CTA |
| `button_url` | string | link do CTA (opcional — sem link do site do cliente ainda mapeado, então é digitado à mão) |
| `coupon_code` | string, opcional | mostrado em destaque no e-mail quando presente |
| `accent_color` | string | hex `#RRGGBB`, cor do botão/destaque |
| `layout` | string, enum-like | `image_top` / `image_left` / `image_right` / `banner` (mesmo espírito dos 4 templates do `Popup`) |
| `image` | ActiveStorage (`has_one_attached`) | opcional; ignorada no layout `banner` |
| `trigger_kind` | integer, enum | ver seção 4 |
| `trigger_config` | jsonb, default `{}` | parâmetros do gatilho escolhido (ver seção 4) |
| `active` | boolean, default `false` | fica `false` até o cliente revisar e ativar — não implica envio nesta v1, é só um status |

Validações: `name`, `subject`, `heading`, `body`, `button_text` presentes; `layout` dentro dos
valores aceitos; `accent_color` no formato hex quando presente; `trigger_kind` presente;
validação condicional dos campos de `trigger_config` conforme o gatilho (via os mesmos
accessors de `filters` jsonb que `Campaign` já usa — `trigger_inactive_days`,
`trigger_delay_hours`, `trigger_days_after_purchase`).

Sem unicidade por `trigger_kind`: um cliente pode ter vários e-mails pra "carrinho abandonado",
por exemplo.

## 2. Rotas

```ruby
resources :email_templates
```

Dentro do `scope '/crm'` já autenticado, mesmo nível de `campaigns`/`popup`. Sem `show` — a
listagem (`index`) e a edição (`new`/`edit`) cobrem tudo, não há histórico de envios pra ver
(isso só existirá quando o envio for implementado).

## 3. Fluxo de telas

### 3.1. `index` — Listagem

Tabela simples (reaproveitando `crm-table`, igual a `campaigns#index`): nome, assunto, gatilho
(label), status (Ativo/Rascunho), atualizado em, ações (Editar / Excluir). Botão "Novo e-mail"
no topo leva pra `new`.

### 3.2. `new` — Galeria de templates prontos

Antes do formulário, uma grade de cards (um por preset — seção 5), cada um com nome, ícone e
uma miniatura simples (CSS, não imagem real) do layout. Clicar num card faz
`GET /crm/email_templates/new?preset=cart_recovery`, que pré-preenche
`@email_template = current_client.email_templates.new(EmailTemplate.preset(:cart_recovery))`
e já mostra o formulário completo (seção 3.3) com os valores do preset — tudo editável antes de
salvar. Um card "Em branco" pula direto pro formulário vazio.

### 3.3. Formulário (`new`/`edit`, mesma view parcial `_form`)

Duas colunas, igual ao `popups/edit`:

- **Coluna esquerda (form):**
  - Campos de conteúdo: nome interno, assunto, título, corpo, texto/link do botão, cupom
    (opcional), cor de destaque, layout (select), imagem (upload, com preview/remoção igual ao
    `Popup`).
  - Seção "Configuração" (a parte que o usuário chamou de "escolher o gatilho"): select de
    `trigger_kind` com as opções da seção 4; ao trocar a opção, mostra/esconde (JS simples, sem
    reload) os campos extras daquele gatilho (ex.: "Dias sem comprar" só aparece pra
    `inactive_customer`).
  - Toggle `active`.
- **Coluna direita (preview):** card fixo estilo e-mail (largura ~600px, fundo branco, sombra
  leve simulando um cliente de e-mail), atualizado ao vivo via JS inline nos eventos
  `input`/`change` dos campos acima — mesmo mecanismo do `popups/edit.html.erb` (sem Stimulus,
  sem framework, só manipulação direta do DOM). O layout escolhido troca a classe CSS do card de
  preview (`email-preview--image-top`, `--image-left`, `--image-right`, `--banner`), replicando
  o texto/imagem/cor atuais.

## 4. Gatilhos (`trigger_kind`)

Enum, valores e config extra (armazenada em `trigger_config` jsonb):

| valor | label | config extra |
|---|---|---|
| `manual` | Envio manual | nenhuma (destinatários serão definidos na hora do envio, a implementar depois) |
| `welcome` | Boas-vindas | nenhuma (dispara em novo cadastro — ex.: submissão do Pop-up) |
| `cart_recovery` | Carrinho abandonado | `delay_hours` (enviar X horas após o abandono) |
| `inactive_customer` | Cliente inativo | `inactive_days` (não compra há X dias) |
| `post_purchase` | Pós-compra | `days_after_purchase` (X dias após a compra) |
| `cashback` | Cashback disponível | nenhuma (mesmo conceito do `Campaign#cashback` já existente pro WhatsApp) |

Só guardamos a escolha e o parâmetro agora — nenhum job/automação dispara a partir disso nesta
etapa; é a mesma ideia dos campos `days_after_purchase`/`send_delay_minutes` que `Campaign` já
tem preenchidos antes mesmo de qualquer job rodar.

## 5. Templates prontos (presets da galeria)

Método de classe `EmailTemplate.preset(key)` retornando um hash de atributos (não persiste nada
sozinho — só usado pra pré-preencher o `new`):

1. **Boas-vindas** (`welcome`) — layout `image_top`, assunto "Seja bem-vindo(a)!", CTA "Ver
   produtos", `trigger_kind: welcome`.
2. **Promoção** (`promo`) — layout `banner`, assunto "Oferta imperdível por tempo limitado",
   campo de cupom em destaque, `trigger_kind: manual`.
3. **Carrinho abandonado** (`cart_recovery`) — layout `image_left`, assunto "Você esqueceu algo
   no carrinho", CTA "Finalizar compra", `trigger_kind: cart_recovery`, `delay_hours: 2`.
4. **Cliente inativo** (`inactive_customer`) — layout `image_right`, assunto "Sentimos sua
   falta!", `trigger_kind: inactive_customer`, `inactive_days: 30`.
5. **Pós-compra** (`post_purchase`) — layout `image_top`, assunto "Obrigado pela sua compra!",
   `trigger_kind: post_purchase`, `days_after_purchase: 3`.
6. **Cashback disponível** (`cashback`) — layout `banner`, assunto "Você tem cashback
   disponível!", `trigger_kind: cashback`.

Todos os presets vêm com `heading`/`body`/`button_text` de exemplo em português, editáveis antes
de salvar.

## 6. Navegação

- `_sidebar.html.erb`: novo item "E-mail" dentro do submenu "Marketing" (mesmo grupo do "Pop Up"
  e "Afiliados"), linkando pra `email_templates_path`.
- `header_helper.rb`: novo item na lista de busca da navbar (`searchable_nav_items`), mesmo
  padrão dos demais.

## 7. Testes

- `test/models/email_template_test.rb`: validações (campos obrigatórios, formato de cor, layout
  dentro do enum, validação condicional de `trigger_config` por `trigger_kind`), método
  `EmailTemplate.preset`.
- `test/controllers/email_templates_controller_test.rb`: `index`/`new`/`create`/`edit`/
  `update`/`destroy` autenticados e escopados por cliente (mesmo padrão de
  `test/controllers/campaigns_controller_test.rb`, se existir, ou `popups_controller_test.rb`).
- Sem teste de JS automatizado (mesmo caso do preview do `Popup` — comportamento do preview ao
  vivo verificado manualmente no navegador).
