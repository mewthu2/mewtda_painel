# Redesign visual (dart.dev) + nova página institucional — Design Spec

**Data:** 2026-08-09
**Status:** aguardando revisão do usuário

## Objetivo

Redesenhar toda a estética do painel (mewtda-painel) usando como referência visual
o site [dart.dev](https://dart.dev/) — tipografia, paleta de cores, raio de borda,
estrutura de navegação — e, junto disso, mover o app hoje acessível em `/painel`
para `/crm`, liberando a raiz do domínio (`/`) para uma nova página institucional
pública sobre a empresa.

Este spec cobre visual + roteamento. Não cobre lógica de negócio nova (isso já foi
tratado nos specs anteriores do dashboard de vendas).

## Decisões já validadas visualmente (mockups aprovados)

Estrutura de navegação, tema claro/escuro e componentes (tabela, formulário,
botões) foram validados interativamente via mockups no navegador antes deste
documento. Resumo do que foi aprovado:

### Tokens de design

| Token | Claro | Escuro |
|---|---|---|
| `--primary` | `#1967d2` | `#47b0f8` |
| `--bg` | `#ffffff` | `#121317` |
| `--fg` | `#212121` | `#dcdcdc` |
| `--fg-alt` (texto secundário) | `#6a6f71` | `#a8acad` |
| `--chrome-bg` (barra superior, não inverte) | `#1c2834` | `#0c1116` |
| `--chrome-fg` | `#F3F4F6` | `#F3F4F6` |
| `--outline` (bordas) | `#e7e8ed` | `#2c313a` |
| `--primary-tint` (fundo de hover/seleção) | `rgba(25,103,210,.08)` | `rgba(71,176,248,.12)` |
| `--radius` | `0.45rem` | `0.45rem` |

**Tipografia:** `'Google Sans Flex', 'Roboto', ui-sans-serif, sans-serif`, carregada via
Google Fonts (`family=Google+Sans+Flex:opsz,wght@6..72,400..700`). Pesos: normal 400,
bold 600, mais forte 700. Fonte de código (se necessário em algum lugar):
`'Google Sans Code', 'Roboto Mono', monospace`.

### Alternância de tema

Um botão (ícone sol/lua) no topo, provavelmente perto do menu do usuário. Ao clicar,
alterna uma classe (`theme-light`/`theme-dark`) no `<body>` e salva a escolha em
`localStorage` — sem coluna nova no banco, sem migration. Todo o CSS novo é escrito
com as custom properties da tabela acima, então a troca é só reatribuir os valores
das variáveis.

### Estrutura de navegação (dentro do `/crm`)

Barra de chrome escura no topo (logo, seletor de cliente do admin, menu do usuário,
botão de tema) + sidebar fixa à esquerda. **Os grupos e itens da sidebar são
exatamente os mesmos que existem hoje no header** (`_header.html.erb`), só
reorganizados de header horizontal para sidebar vertical — nomes, ordem, links
"quebrados" (ex.: "Automações") e a duplicidade de nome "Clientes" (Operações vs.
Admin) ficam como estão, por decisão explícita do usuário, fora de escopo deste
redesign:

- **Dashboard** (`painel_path` → renomeado para `crm_path`, ver seção de rotas)
- **Vendas** (`sales_dashboard_path`) — sempre visível, sem gate de toggle (já
  decidido em spec anterior, ainda pendente de implementação)
- **Operações**: Pedidos, Clientes, Produtos
- **Marketing**: Campanhas, Afiliados, Automações (link morto, mantido como está)
- **Admin** (só para admins): Usuários, Clientes, Perfis, Sidekiq, Try-On Virtual

Para o perfil Afiliado, a sidebar mostra só "Meus Eventos", igual hoje.

Mobile: a sidebar vira um drawer deslizante (reaproveita o padrão de
hamburger/overlay que já existe em `_header.html.erb`, só adaptado pra abrir a
sidebar em vez do menu horizontal).

### Componentes

Botões (preenchido primário / contornado secundário), inputs, tabelas com hover de
linha e "tags" de status coloridas, cards de KPI — todos usando os tokens acima.
Ver mockups aprovados para referência visual exata (cores, raio, espaçamento).

## Mudança de rotas: `/painel` → `/crm`, raiz vira página institucional

**Hoje:**
```ruby
root to: redirect('/painel')
scope '/painel' do
  devise_for :user, skip: [:registrations]
  ...
  get '/', to: 'dashboard#index', as: :painel
  ...
end
```

**Depois:**
```ruby
root to: 'home#index'   # nova página institucional pública, sem login
scope '/crm' do
  devise_for :user, skip: [:registrations]
  ...
  get '/', to: 'dashboard#index', as: :crm   # renomeado de :painel para :crm
  ...
end
```

- Sem redirect de compatibilidade: `/painel/*` simplesmente deixa de existir.
  `http://.../painel/clients/36/edit` vira `http://.../crm/clients/36/edit` — decisão
  explícita do usuário, já que é uso interno.
- **13 referências** a `painel_path`/`painel_session_path` em 5 arquivos precisam
  virar `crm_path`/`crm_session_path`: `app/controllers/sales_dashboard_controller.rb`,
  `app/controllers/try_on_controller.rb`, `app/views/dashboard/index.html.erb`,
  `app/views/layouts/partials/_footer.html.erb`, `app/views/layouts/partials/_header.html.erb`.
- `HomeController#index` já existe (hoje só redireciona pra login se não autenticado,
  e não tem rota associada) — vai ser reaproveitado: remove o redirect condicional,
  passa a renderizar a página institucional pra qualquer visitante (autenticado ou
  não). O botão de login na página leva pra `new_user_session_path` (dentro de `/crm`).
- Login, recuperação de senha, confirmação de conta, etc. (todas as views
  `devise/*`) continuam vivendo dentro do `/crm`, só mudam de prefixo de URL junto
  com o resto.

## Página institucional (`/`)

Estrutura simples (hero + seções básicas + CTA de login), com **conteúdo
placeholder por enquanto** — o usuário vai fornecer o texto real depois. Usa os
mesmos tokens de design do `/crm` (mesma fonte, cores, alternância de tema) —
decisão explícita do usuário de manter uma identidade visual única em vez de usar
uma referência diferente (thedevelopersclub.com.br foi cogitado e descartado).

Seções da estrutura placeholder:
1. Hero — nome/logo da empresa, frase de efeito, botão "Entrar"
2. O que é / pra quem é — 2-3 blocos curtos explicando o produto
3. Rodapé simples

Sem formulário de contato, sem seção de preços, sem nada que dependa de conteúdo
real ainda — só a casca visual pronta pra receber o texto.

## Escopo: quais telas são redesenhadas

Todas as views autenticadas do `/crm` (a lista completa abaixo) mais todas as views
`devise/*` (login, nova senha, editar senha, confirmação, desbloqueio — não só a
tela de login, o fluxo inteiro de autenticação) mais a nova página institucional.

**Views em escopo** (`app/views/`):
`dashboard/index`, `sales_dashboard/index`, `clients/{index,new,edit,_form}`,
`customers/index`, `orders/index`, `products/index`, `campaigns/{index,new,edit,show,_form}`,
`affiliates/{index,new,edit,show,_form,_form_styles}`, `profiles/{index,new,edit,show,_form}`,
`users/{index,new,edit,_form}`, `events/index`, `attempts/{index,verify_attempts}`,
`try_on/index`, `home/index` (nova página institucional), `layouts/partials/{_header,_footer,_sidebar,_messages,_content}`,
todas as `devise/*` (exceto `devise/mailer/*`).

**Fora de escopo:**
- `layouts/mailer.html.erb` e `devise/mailer/*` — e-mails, não são páginas web.
- Sidekiq Web UI (`/crm/sidekiq`) — é uma engine montada, não é nosso código pra
  restilizar.
- `leads/index.html.erb` e `home/index.html.erb` (versão antiga) — sem rota
  associada hoje (órfãs); `home/index` é reaproveitada para a página
  institucional, `leads/index` continua fora do roteamento, sem necessidade de
  redesign.
- Naming/links quebrados na navegação ("Automações", duplicidade "Clientes") —
  mantidos como estão, decisão explícita do usuário.

## Arquitetura de CSS

Em vez de mais blocos `<style>` inline (23 views já têm isso hoje), o redesign
escreve SCSS de verdade em `app/assets/stylesheets/`, substituindo os arquivos
atuais em `layouts/` (`header.scss`, `sidebar.scss`, `global.scss`, etc.) por uma
estrutura nova organizada por responsabilidade:

```
app/assets/stylesheets/
  admin.scss              # entry point, mantém os imports
  tokens.scss             # NOVO: variáveis de cor/fonte/raio (claro + escuro)
  layouts/
    topbar.scss            # NOVO (substitui header.scss)
    sidebar.scss            # NOVO (reescrito)
    footer.scss
  components/
    _button.scss           # NOVO
    _input.scss             # NOVO
    _table.scss             # NOVO
    _card.scss               # NOVO (KPI cards, cards genéricos)
    _tag.scss                 # NOVO (badges de status)
  pages/
    institutional.scss     # NOVO (página em /)
    ... (uma parcial por página que precisar de algo específico)
```

Isso absorve, como efeito colateral, a maior parte do objetivo de "consolidar o
CSS espalhado" que tínhamos planejado como um terceiro projeto separado — não
precisa mais ser uma etapa à parte depois do redesign.

**Fora de escopo desta mudança:** Bootstrap 5, jQuery, DataTables continuam sendo
usados onde já são usados hoje (modais, dropdowns, tabelas interativas) — o
redesign é sobre aparência (cores, tipografia, espaçamento, estrutura de
navegação), não uma reescrita de JavaScript/framework.

## Verificação

Como é majoritariamente CSS/HTML sem lógica de negócio nova, a verificação principal
é visual, não testes automatizados:
- Cada página migrada é conferida manualmente no navegador (claro e escuro) antes
  de ser considerada concluída.
- Testes automatizados existentes (a suíte de 41 testes do dashboard de vendas,
  etc.) não devem quebrar — nenhuma mudança de comportamento, só de aparência e
  de prefixo de rota. Os testes que usam `sales_dashboard_path`,
  `client_google_ads_connect_path`, etc. continuam funcionando sem alteração,
  já que são helpers do Rails que se ajustam automaticamente ao novo prefixo de
  rota — só as referências literais a `painel_path`/`painel_session_path` no
  código precisam ser atualizadas para `crm_path`/`crm_session_path`.
- Rodar a suíte completa (`bin/rails test`) depois da mudança de rotas para
  garantir que nada quebrou por causa do prefixo novo.
