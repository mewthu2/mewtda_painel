# Busca de menus/telas na navbar — Design

Data: 2026-08-13

## Objetivo

Adicionar um campo de busca na navbar (`app/views/layouts/partials/_header.html.erb`) que filtra
os itens de navegação já existentes (sidebar + dropdown do usuário) conforme o usuário digita, e
navega pra tela escolhida ao clicar ou pressionar Enter.

## Fora de escopo (v1)

- Busca dentro de dados (clientes, pedidos, produtos etc.) — só nomes de tela/menu.
- Qualquer chamada ao backend — tudo roda client-side com a lista já carregada na página.
- Atalho de teclado global (Cmd/Ctrl+K) pra focar o campo.

## 1. Lista de itens buscáveis

Novo helper `HeaderHelper#searchable_nav_items`, retornando um array de
`{ label:, url:, icon: }`, espelhando exatamente as mesmas condicionais de visibilidade que já
existem em `_sidebar.html.erb` e no dropdown do usuário em `_header.html.erb`:

- Afiliado (`Profile::AFFILIATE`): só "Meus Eventos".
- Demais: Trackeamento site, Vendas (se admin ou `client.sales_dashboard_enabled?`), Pedidos,
  Clientes, Produtos, Campanhas, Afiliados, Automações.
- Admin: adiciona Usuários, Clientes (admin), Perfis, Sidekiq, Try-On Virtual.
- Não-admin, não-afiliado: adiciona Configurações.

Esse helper é a fonte da lista pra busca — não substitui nem reescreve a sidebar/dropdown atuais
(que continuam iguais); é uma lista paralela, mantida manualmente em sincronia. Unificar as duas
fontes seria um refactor maior, fora do escopo deste pedido.

## 2. HTML — `_header.html.erb`

Um novo bloco `<div class="crm-header__search">` entre `crm-header__left` e
`crm-header__actions`, contendo:
- `<input type="text" id="crm-nav-search-input" placeholder="Buscar telas...">`
- Ícone de lupa (sempre visível, vira o "gatilho" em mobile).
- `<div id="crm-nav-search-results" class="crm-header__search-results">` (dropdown de resultados,
  escondido até haver texto digitado).

A lista de itens (`searchable_nav_items`) é serializada como JSON num atributo `data-items` do
input, pro JS ler sem chamada ao servidor.

Em mobile (`<768px`), o input começa colapsado — só o ícone aparece; clicar no ícone expande o
campo por cima da navbar (`position: absolute`, mesma técnica de overlay já usada pelo drawer da
sidebar). Clicar fora ou Esc recolhe de novo.

## 3. Comportamento (JS)

No mesmo bloco `<script>` que já existe em `_header.html.erb` (sem lib nova):

- `input` event → filtra os itens (`label.toLowerCase().includes(query)`), renderiza o dropdown
  de resultados (ícone + label, `<a>` com `href` pro `url` de cada item).
- Sem resultado → linha "Nenhuma tela encontrada" no lugar da lista.
- Campo vazio → dropdown escondido.
- Teclado: ↑/↓ move o destaque entre resultados (classe `.active` no item), Enter navega pro
  destacado (ou pro primeiro resultado, se nenhum destacado), Esc fecha o dropdown (e recolhe o
  campo em mobile).
- Clique fora do bloco de busca fecha o dropdown — mesmo padrão (`document.addEventListener`)
  já usado pro dropdown do usuário no mesmo arquivo.

## 4. Estilo

Novas classes em `app/assets/stylesheets/layouts/topbar.scss` (onde `.crm-header*` já vive),
usando os tokens existentes (`--bg`, `--outline`, `--fg`, `--fg-alt`, `--primary`,
`--primary-tint`, `--radius`) — mesmo padrão visual do dropdown do usuário que já existe
(`.crm-header__dropdown`), pra manter consistência.

## 5. Testes

- Teste de view/helper (`test/helpers/header_helper_test.rb`): `searchable_nav_items` retorna os
  itens certos pra afiliado, usuário comum (com e sem `sales_dashboard_enabled?`), e admin —
  espelhando os testes que já existem pra visibilidade de menu em outros lugares do app, se
  houver algum padrão similar.
- Sem teste de JS automatizado (o projeto não tem suíte de teste de JS hoje) — comportamento do
  filtro/teclado fica pra verificação manual no navegador.
