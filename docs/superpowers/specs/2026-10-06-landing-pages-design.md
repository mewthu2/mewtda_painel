# Landing Pages — design

Data: 2026-10-06 · Status: aprovado em conversa (usuário pediu implementação direta pelo prazo do Drop 01 da 1822)

## Objetivo

Páginas de conversão públicas, escritas à mão em `.html.erb`, por cliente. Conversão = compra direta
(1–2 produtos fixos, escolhe variante, vai direto pro checkout da Shopify) + cadastro de lead como
alternativa. Pedidos vindos da página são atribuídos a ela.

## Decisões

- Model `LandingPage` (sem relação com `Campaign`, que é WhatsApp).
- URL pública `/:path_prefix/:slug`. `path_prefix` é por página (default = `clients.slug`) para que
  a marca na URL possa ser neutra — o branding book da 1822 proíbe HENRRI em anúncio, então a página
  da 1822 usa `/use1822/drop-01` em vez de `/henrri/...`. Prefixos reservados bloqueados.
- Conteúdo NÃO é configurável: o registro aponta pra um template em
  `app/views/landing_pages/templates/<template>.html.erb`; produtos são handles da Shopify
  guardados no registro (`product_handles`), carregados no servidor via Storefront API (cache 5 min).
- Comprar: botão chama `cartCreate` direto na Storefront API pelo navegador (token público por
  design) com 1 linha e atributos `_landing_page=<id>` + UTMs, e redireciona pro `checkoutUrl`.
  Sem carrinho visível. Pede só `checkoutUrl` (não expõe o id/secret do cart).
- Atribuição: o sync de pedidos já lê `note_attributes`; passa a gravar `orders.landing_page_id`
  a partir de `_landing_page` (escopado ao client).
- Lead: `POST /:path_prefix/:slug/lead`. Antes de criar, verifica se a pessoa já está na base
  (Shopify por e-mail/telefone + `customers` local do cliente). Já existe → `tagsAdd` com
  `lp-<prefix>-<slug>`, lead marcado `existing_customer: true`. Não existe → `customerCreate`
  com a tag. Um lead por (página, e-mail).
- `ends_at` opcional: depois dele a página troca a compra por "pré-venda encerrada" e mantém o lead.
- `clients.shopify_storefront_token` (criptografado) editável no form do cliente (admin) e em
  Configurações; `clients.slug` editável no form do admin.

## Painel

`/crm/landing-pages`: listagem, criar/editar/excluir, detalhe com visitas, leads (novos × já na
base), pedidos atribuídos e faturamento. Link no menu Marketing.

## Template 1822 · Drop 01

Segue o branding book: preto `#111111`, papel `#F4F1EA`, amarelo `#F4C618` (preço/destaque), verde
`#2B9A3E`, azul `#0A5CD6` (só em blocos). Nunca vermelho. Anton caixa alta para títulos, Archivo
(400/600/700) para texto. Endosso "produzido por HENRRI" só no rodapé. Tom de voz conforme a
coluna "falamos assim". Logo: até receber o SVG, usa algarismos em Anton nas cores na ordem
amarelo/verde/azul/amarelo.

## Configuração na Shopify (manual)

O produto precisa estar publicado no canal de vendas do app/headless que emitiu o token da
Storefront API — pode ficar oculto da Online Store (coleção oculta).

## Testes

Models (slugs, reservados, unicidade), controller público (200/404/inativa/encerrada, lead),
service de lead (já existe × novo, Shopify stubada), extração de `_landing_page` no sync.
