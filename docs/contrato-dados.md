# Contrato de dados por fonte (camada bruta)

O que cada workflow do n8n entrega, em qual tabela, com qual chave de upsert. É a
referência pra montar os workflows. A DDL está em
`supabase/migrations/20261103_0001_brutas.sql` (aplicada em 03/11/2026).

Última atualização: 03/11/2026

## Regras gerais

- Gravação: HTTP Request pro PostgREST com upsert (ver `padroes-n8n.md`):
  `POST /rest/v1/<tabela>?on_conflict=<chave>` +
  `Prefer: resolution=merge-duplicates,return=minimal`.
- Sempre mandar `raw_payload` com o JSON original inteiro. É obrigatório em todas as
  tabelas. Se um campo não for mapeado, ele ainda fica salvo ali.
- Não mandar `id`, `received_at` nem `updated_at`. O banco preenche.
- Datas e horas: ISO 8601 com fuso (ex.: `2026-11-04T10:15:00-03:00`). Se a fonte
  mandar sem fuso, o workflow assume `America/Sao_Paulo` e acrescenta `-03:00`.
- Valores: Hubla em centavos (inteiro, como a Hubla manda). TMB e Unnichat em reais
  (decimal com ponto). A conversão fica nas views, não no n8n.
- Campo vazio vai como `null`, nunca como string vazia (exceção: `callix_lista_id` no
  resumo por hora, ver abaixo).
- Nomes de coluna seguem o payload da fonte quando ele é claro (ex.: `invoice_id`,
  `pedido_id`), pra facilitar o mapeamento.
- Nenhuma regra de negócio no n8n: vendedor, valor TMB a 50% e status válidos são
  calculados nas views da etapa 3.

## Regras de negócio que afetam a leitura (calculadas nas views)

- **Vendedor da venda = `utm_source`.** O padrão é `comercial_nome-sobrenome` (ex.:
  `utm_source=comercial_ana-souza`). A view lê só o `utm_source` e cruza com o
  cadastro de vendedores tratando `_` e `-` como iguais e ignorando maiúscula
  (`cic_vendedor_de_utm`). Venda sem `comercial_*` no `utm_source` fica como "sem
  vendedor".
- **TMB vale 50%** do valor (provisório, parâmetro na config do cliente). A bruta
  guarda o valor cheio.
- **Callix é conta da WeRev, compartilhada entre operações.** Ver seção Callix.

## Visão geral

| Fonte | Tabela | Como chega | Chave de upsert (`on_conflict`) |
|---|---|---|---|
| Hubla | `hubla_vendas` | webhook | `invoice_id` |
| Hubla | `hubla_reembolsos` | webhook | `invoice_id,event_type` |
| Hubla | `hubla_carrinho_abandonado` | webhook | `lead_id,lead_created_at` |
| Hubla | `hubla_recusadas` | webhook | `invoice_id,failed_at` |
| TMB | `tmb_vendas` | webhook | `pedido_id` |
| TMB | `tmb_reembolsos` | webhook | `pedido_id` |
| Unnichat | `unnichat_eventos` | webhook | `telefone,acao,etapa_crm,event_ts` |
| Unnichat | `unnichat_automacoes` | webhook (não alimentada) | `contact_id,telefone,codigo_copy,minuto` |
| Unnichat | `unnichat_automacoes_metricas` | coleta de hora em hora (API) | `automacao_id,node_id,coletado_em` |
| Unnichat | `unnichat_automacoes_nodes` | coleta de hora em hora (API) | `automacao_id,node_id` |
| Unnichat | `unnichat_templates` | coleta de hora em hora (API) | `template_id` |
| Unnichat | `unnichat_blocklist` | webhook | `telefone` |
| Unnichat | `unnichat_broadcasts` | coleta agendada (API) | `broadcast_id` |
| Unnichat | `unnichat_conversas_dia` | coleta diária (API) | `dia,contact_id` |
| Callix | `callix_ligacoes` | coleta agendada | `protocol` |
| Callix | `callix_usuarios` | coleta agendada | `callix_user_id` |
| Callix | `callix_qualificacoes` | coleta agendada | `callix_qualificacao_id` |
| Callix | `callix_campanhas` | coleta agendada | `callix_campanha_id` |
| Callix | `callix_listas` | coleta agendada | `callix_lista_id` |
| Callix | `callix_resumo_hora` | coleta agendada | `tipo,callix_campanha_id,callix_lista_id,data,hora` |
| Callix | `callix_resumo_1x1_hora` | coleta agendada | `callix_user_id,data,hora` |
| Callix | `callix_performance_agente` | coleta agendada | `callix_user_id,data` |

Prioridade pra 04/11 (abertura de carrinho): **Hubla vendas, TMB vendas e Unnichat
eventos**. Depois: reembolsos, carrinho/recusadas, Callix e as coletas do Unnichat.

Legenda das colunas: **obr.** = obrigatório (sem ele o upsert falha).

## Hubla

Um webhook por tabela (decidido em 04/11/2026, substitui o webhook único com Switch).
Cada regra na Hubla (Integrações > Automações > Webhook > Configurações) aponta pra
um path e marca só os eventos daquela tabela. Os webhooks da Hubla pro Unnichat
continuam como estavam; os do n8n são regras adicionais.

Produtos por regra (05/11/2026): Ultra Black 2026 nas 4 regras. Meal Prep Express +
Regina IA só nas regras de Vendas e Reembolsos (carrinho e recusa do Meal Prep não são
medidos). Produto novo entra marcando na regra da Hubla, sem mexer no workflow (só
grava; repasse ao Unnichat exige entrar no mapa abaixo). Atenção: o mapeamento grava só
`products[0]`; se algum produto passar a ser vendido como order bump, ajustar antes.

### Repasse ao Unnichat (n8n, não é webhook da Hubla)

Vendas, Carrinho e Recusadas mandam `{name, email, phone}` pra URL de start de um fluxo
do Unnichat (phone só com dígitos, `55` na frente quando vem com 10 ou 11). Só passa
quem tem telefone com 10 a 15 dígitos. Reembolsos não repassa. A gravação no Supabase
não depende do repasse. As URLs reais ficam só no n8n; no export do repo viram
`<URL_UNNICHAT_...>`.

**Vendas: repasse por `product_id`** (05/11/2026). Só `invoice.payment_succeeded`. Nó
"Config repasse" guarda o mapa `product_id -> URL`; nó "Fluxo do produto" resolve a URL.
Produto fora do mapa não repassa (sai sem erro). Mapa atual:

| product_id | Produto | Fluxo no Unnichat |
|---|---|---|
| `rknQJI9bMjaNjnuUziSN` | Ultra Black vitalícia | Compra Aprovada BF26 (`<URL_UNNICHAT_COMPRA_APROVADA>`) |
| `rjJkwWreyVXnn7hYgG85` | Meal Prep Express + Regina IA | fluxo próprio desde 05/11/2026 (`<URL_UNNICHAT_MEAL_PREP>`) |
| `aIbhQ9f2JP4OHInCx8Cq` | Meal Prep Express (produto novo, ofertas 397 e 497) | mesmo fluxo do Meal Prep, [HUBLA] Compra Aprovada - Meal Prep Express + Regina IA (`<URL_UNNICHAT_MEAL_PREP>`), desde 05/11/2026 |

Produto novo com fluxo: acrescentar a linha no "Config repasse" e publicar.

Carrinho e Recusadas: uma URL fixa cada (`<URL_UNNICHAT_CARRINHO_ABANDONADO>`,
`<URL_UNNICHAT_COMPRA_RECUSADA>`), sem filtro de produto.

| Workflow | Path | Eventos marcados na Hubla | Tabela |
|---|---|---|---|
| `[MARTHA] Hubla · Vendas` | `/webhook/martha-guterres/hubla/vendas` | Pagamento da fatura realizado, Status da fatura atualizada | `hubla_vendas` |
| `[MARTHA] Hubla · Reembolsos` | `/webhook/martha-guterres/hubla/reembolsos` | Solicitação de reembolso criada/aceita/rejeitada/cancelada, Fatura reembolsada | `hubla_reembolsos` |
| `[MARTHA] Hubla · Carrinho` | `/webhook/martha-guterres/hubla/carrinho` | Carrinho abandonado (lead) | `hubla_carrinho_abandonado` |
| `[MARTHA] Hubla · Recusadas` | `/webhook/martha-guterres/hubla/recusadas` | Pagamento da fatura falhou | `hubla_recusadas` |

Autenticação: header `x-hubla-token` (token da aba Autenticação da integração de
webhook da Hubla), credencial `[MARTHA] Hubla`. Na regra, filtrar pelos produtos da
Martha (a regra permite escolher produtos e ofertas).

**Mapeamento** (payload v2: `type` + `event`). O workflow tenta mais de um caminho por
campo e grava o primeiro que existir; vazio vira `null`. Datas: ISO com fuso (sem fuso
assume -03:00). Centavos como a Hubla manda.

| Coluna | Caminho no payload |
|---|---|
| `event_type` | `type` |
| `invoice_id` | `event.invoice.id` (reembolso: também `event.refundRequest.invoiceId`) |
| `status`, `payment_method`, `installments` | `event.invoice.status`, `.paymentMethod`, `.installments` |
| `subscription_id` | `event.invoice.subscriptionId` ou `event.subscription.id` |
| `product_id`, `product_name` | `event.product.*` ou `event.products[0].*` |
| `offer_id`, `offer_name` | `event.products[0].offers[0].*` ou `event.offer.*` |
| `payer_id` | `event.invoice.payerId` ou `event.user.id` |
| `payer_nome` | `event.user.firstName` + `lastName` (ou `name`/`fullName`) |
| `payer_email`, `payer_telefone`, `payer_documento` | `event.user.email`, `.phone`, `.document` (telefone como a Hubla manda) |
| `coupon_code` | `event.invoice.coupon.code` |
| `subtotal_cents`, `discount_cents`, `total_cents` | `event.invoice.amount.*Cents` |
| `seller_net_cents` | `totalCents` do recebedor com `role = seller` em `event.invoice.receivers` |
| `utm_*` | `event.invoice.paymentSession.utm.*` |
| `sale_date`, `invoice_created_at`, `invoice_modified_at` | `event.invoice.saleDate`, `.createdAt`, `.modifiedAt` |
| `refund_id`, `refund_status`, `refund_description`, `refund_feedback`, `is_auto_accepted`, `refund_created_at` | `event.refundRequest.*` |
| `refunded_at` | `event.refundRequest.acceptedAt`; em `invoice.refunded`, `event.invoice.modifiedAt` |
| `lead_id`, `nome`, `email`, `telefone` | `event.lead.id`, `.fullName`, `.email`, `.phone` |
| `lead_created_at` | `event.lead.createdAt`; sem ela, hora do recebimento |
| `checkout_url`, `utm_*` (carrinho) | `event.lead.session.url`, `event.lead.session.utm.*` |
| `failed_at` | `event.invoice.failedAt`, senão `event.invoice.modifiedAt`; sem nenhuma, hora do recebimento |

Sem a chave principal (`invoice_id` ou `lead_id`), o workflow para com erro e cai no
`[MARTHA] Erros` (sinal de evento errado marcado na regra).

**Pendente:** os caminhos acima seguem o formato v2 conhecido da Hubla; a página de
payload de exemplo da doc não abriu. Validar com o "Testar configuração" do painel e
ajustar o que vier diferente (o dado fica no `raw_payload` de qualquer jeito).

### `hubla_vendas`
Fatura paga e mudanças de status. Reenvio do mesmo `invoice_id` atualiza a linha
(status mais recente vence).

| Coluna | Tipo | Nota |
|---|---|---|
| `invoice_id` | text | **obr.** id da fatura |
| `event_type` | text | tipo do evento da Hubla |
| `status` | text | status da fatura |
| `subscription_id` | text | |
| `product_id`, `product_name` | text | |
| `offer_id`, `offer_name` | text | |
| `payer_id`, `payer_nome`, `payer_email`, `payer_telefone`, `payer_documento` | text | nome completo em `payer_nome` |
| `payment_method` | text | |
| `installments` | int | |
| `coupon_code` | text | |
| `subtotal_cents`, `discount_cents`, `total_cents`, `seller_net_cents` | bigint | centavos |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | text | `utm_source` traz o `comercial_*` |
| `sale_date` | timestamptz | data do pagamento |
| `invoice_created_at`, `invoice_modified_at` | timestamptz | |
| `raw_payload` | jsonb | **obr.** |

### `hubla_reembolsos`
| Coluna | Tipo | Nota |
|---|---|---|
| `invoice_id` | text | **obr.** |
| `event_type` | text | **obr.** (solicitado, aprovado etc.) |
| `refund_id`, `refund_status`, `refund_description`, `refund_feedback` | text | |
| `is_auto_accepted` | boolean | |
| `product_id`, `product_name`, `offer_id`, `offer_name` | text | |
| `payer_nome`, `payer_email`, `payer_telefone` | text | |
| `payment_method` | text | |
| `total_cents` | bigint | |
| `utm_*` (5) | text | |
| `sale_date`, `refund_created_at`, `refunded_at` | timestamptz | |
| `raw_payload` | jsonb | **obr.** |

### `hubla_carrinho_abandonado`
| Coluna | Tipo | Nota |
|---|---|---|
| `lead_id` | text | **obr.** |
| `lead_created_at` | timestamptz | **obr.** |
| `event_type`, `nome`, `email`, `telefone` | text | |
| `product_id`, `product_name`, `offer_id`, `offer_name`, `checkout_url` | text | |
| `utm_*` (5) | text | |
| `raw_payload` | jsonb | **obr.** |

### `hubla_recusadas`
| Coluna | Tipo | Nota |
|---|---|---|
| `invoice_id` | text | **obr.** |
| `failed_at` | timestamptz | **obr.** momento da recusa |
| `event_type`, `status` | text | |
| `product_id`, `product_name`, `offer_id`, `offer_name` | text | |
| `payer_nome`, `payer_email`, `payer_telefone`, `payment_method` | text | |
| `installments` | int | |
| `total_cents` | bigint | |
| `sale_date` | timestamptz | |
| `raw_payload` | jsonb | **obr.** |

## TMB

Webhook: `/webhook/martha-guterres/tmb/eventos`.

### `tmb_vendas`
Um registro por pedido; mudança de status atualiza a linha.

| Coluna | Tipo | Nota |
|---|---|---|
| `pedido_id` | bigint | **obr.** |
| `status_pedido`, `status_financeiro` | text | |
| `cliente`, `email`, `telefone`, `documento` | text | |
| `produto_id` | bigint | |
| `produto_nome` | text | |
| `valor_total` | numeric | reais, **valor cheio** (os 50% são aplicados na view) |
| `parcelas` | int | |
| `valor_entrada`, `valor_parcela` | numeric | |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | text | primeiro toque; `utm_source` traz o `comercial_*` |
| `utm_last_source`, `utm_last_medium`, `utm_last_campaign`, `utm_last_content` | text | último toque, se a TMB mandar |
| `criado_em`, `data_efetivado` | timestamptz | |
| `raw_payload` | jsonb | **obr.** |

### `tmb_reembolsos`
Mesmos campos de identificação da venda (`pedido_id` **obr.**, status, cliente,
produto, `valor_total`, `parcelas`, `utm_*`, `criado_em`, `data_efetivado`), mais
`reembolsado_em` (timestamptz, quando o cancelamento/reembolso foi detectado) e
`raw_payload` **obr.**

## Unnichat (conta da Martha)

### `unnichat_eventos` (webhook `/webhook/martha-guterres/unnichat/eventos`)
Cada mudança no CRM (etapa, ganho, perda).

| Coluna | Tipo | Nota |
|---|---|---|
| `event_ts` | timestamptz | **obr.** momento do evento |
| `telefone` | text | **obr.** só dígitos, com DDI (ex.: `5531999998888`) |
| `acao` | text | **obr.** tipo de ação do evento |
| `etapa_crm` | text | etapa do card no CRM (entra na chave) |
| `email`, `nome` | text | |
| `origem`, `status` | text | |
| `proprietario` | text | dono do card (vendedor no Unnichat) |
| `conexao`, `pipeline` | text | |
| `produto`, `oferta`, `forma_pagamento` | text | |
| `valor_total`, `valor_liquido` | numeric | reais |
| `motivo_perda` | text | |
| `codigo_copy` | text | campo personalizado "Código Copy" (ex.: `CP 01`) |
| `negocio_id` | text | id do negócio no CRM (`data.Etapa[].id`), desde a 0007 |
| `etapa_desde` | timestamptz | quando o negócio entrou na etapa (`data.Etapa[].attributedIn`), desde a 0007 |
| `raw_payload` | jsonb | **obr.** |

**`data.Etapa` é uma lista de negócios**, não texto. Cada item traz `id`, `columnName`
(a etapa, igual a `crm_etapas.nome_unnichat`), `status` (open/won/lost),
`reasonLossDescription`, `pipelineName` e `attributedIn`. Usar o item com
`attributedIn` mais recente. `data.eventDate` e `data.Data` chegam em **segundos
Unix** (ex.: `"1793835192"`), não ISO (confirmado nos eventos de 04/11).

**Origem no Unnichat:** conexão Martha Guterres 0209, pipeline
`[COMERCIAL] Pipeline - Disparo`. Sete automações `[EVENTO]` (0. Base/Entrada,
1. Discadora, 2. Em Contato, 3. Negociação, 4. Forecast, Ganho, Perdido): espera de
15 s e POST. Só eventos de CRM passam por este webhook (sem Switch).

**Body recebido** (chaves dentro de `data`):
`{"data":{"id","name","email","phoneNumber","Data","Acao","Origem","Proprietario",
"Etapa","conexao","pipeline","codigo copy","field":{...},"profilePicUrl","eventDate"}}`.
Ganho e Perdido podem ter `Acao` diferente; grava o que vier.

**Mapeamento** (workflow `[MARTHA] Unnichat · Eventos CRM`, nó "Mapear evento"):

| Coluna | De onde vem |
|---|---|
| `telefone` | `data.phoneNumber`, mesma regra da blocklist (só dígitos; 10 ou 11 ganham `55`; fora de 10 a 15 para com erro) |
| `event_ts` | `data.eventDate` (segundos Unix); se vier ISO, aceita também. Sem data válida, hora do recebimento |
| `acao` | `data.Acao`. Obrigatório no banco: vazio para com erro |
| `etapa_crm` | `columnName` do negócio mais recente em `data.Etapa` |
| `status`, `motivo_perda`, `pipeline` | `status`, `reasonLossDescription`, `pipelineName` do mesmo negócio |
| `negocio_id`, `etapa_desde` | `id`, `attributedIn` do mesmo negócio |
| `nome`, `email` | `data.name`, `data.email` |
| `origem` | `data.Origem` |
| `proprietario` | `data.Proprietario` |
| `conexao`, `pipeline` | `data.conexao`, `data.pipeline` |
| `codigo_copy` | `data["codigo copy"]` |
| `produto`, `oferta`, `forma_pagamento`, `motivo_perda`, `status` | se vierem em `data` ou `data.field` (nome da chave sem diferenciar maiúscula/minúscula) |
| `valor_total`, `valor_liquido` | idem; aceita número ou texto BR (`R$ 1.234,56`). Não convertível não é enviado |
| `raw_payload` | body inteiro |

Campo vazio ou com variável não resolvida (`{{...}}`) não é enviado. A tabela não tem
`contact_id`: o id do contato fica em `raw_payload->'data'->>'id'`.

Efeito do `event_ts` na chave: se cair na hora do recebimento, reenvio do mesmo evento
vira linha nova; se `eventDate` for uma data fixa (ex.: criação do contato), o mesmo
contato voltando pra mesma etapa vira uma linha só.

**Ganhos e perdas (05/11/2026).** Chegam pelas automações [EVENTO] Ganho e [EVENTO]
Perdido do Unnichat, com `status` won/lost no próprio evento (`motivo_perda` na perda;
a perda vem sem `etapa_crm`). Em 05/11 houve backfill de 131 eventos pela API, marcado
em `raw_payload->>'backfill'` (`api_deals_2026-11-05`, com o deal em `raw_payload->'deal'`);
é tratado igual aos demais. Uso no CIC (migration 0015, `cic_negocios()`):
- negócio = `negocio_id`; vendedor = `proprietario` mais recente (fallback: telefone,
  últimos 8 dígitos); fora do cadastro de vendedores = sem vendedor;
- grupo do motivo = código entre colchetes do texto; grupo `cs` (Detrator/Blocklist,
  Reembolso/Cancelamento) é saída de CS, fora da perda comercial;
- ganho no CIC é sempre a venda paga na Hubla, casada pelo telefone (DDI + DDD +
  últimos 8); o won do CRM não entra em conta.

**Segunda recuperação de ganhos e perdas (09/11/2026).** Causa: a [EVENTO] Perdido tinha
uma espera de 15 s que era cancelada quando BLOCKLIST/GERAL rodavam no mesmo contato
(1.111 disparos, 341 esperas canceladas); a espera foi removida às 14:59 de 09/11.
Correção: workflow manual `[MARTHA] Unnichat · Recuperar ganhos e perdas`
(`n8n/workflows/unnichat-recuperar-ganhos-perdas.json`, desativado, `gravar=false` por
padrão) lê `/crm/pipelines/{id}/deals/lost|won` com `lostFrom/lostTo` e `wonFrom/wonTo`,
pula negócio que já tem evento com o mesmo `negocio_id` e status e insere o que falta no
formato do backfill (`raw_payload->>'backfill'` = `api_deals_2026-11-09`), com
`on conflict do nothing`. Regras do preenchimento: `event_ts` = `attributedIn` no
segundo; `proprietario` = último evento de etapa do negócio, senão da mesma pessoa
(`pessoa_chave`) antes do fechamento; `origem` e `codigo_copy` do campo do negócio, senão
do último evento do mesmo negócio; origem vazia até 06/11 = "Disparos BF26"; "Disparo
BF26" normalizado para "Disparos BF26". Resultado: 341 perdas e 2 ganhos inseridos (68
com proprietário). Depois: banco = API em perdas (1.237 negócios de 04/11 a 09/11 15:27)
e as 2 perdas após 15:00 chegaram pela automação.

### `unnichat_automacoes` (webhook `/webhook/martha-guterres/unnichat/automacoes`)
**Não alimentada por decisão (04/11/2026):** só o comercial reporta (eventos de CRM em
`unnichat_eventos`) e o custo de mensagem das automações sai da coleta horária
(`unnichat_automacoes_metricas` + `unnichat_automacoes_nodes`), não de webhook por
mensagem. Tabela fica no banco sem workflow.

| Coluna | Tipo | Nota |
|---|---|---|
| `minuto` | timestamptz | **obr.** horário do envio, truncado no minuto |
| `contact_id`, `telefone` | text | entram na chave |
| `codigo_copy` | text | entra na chave |
| `fluxo`, `funil`, `tipo`, `msg` | text | |
| `cadencia`, `disparo`, `envios` | int | partes do código de copy |
| `raw_payload` | jsonb | **obr.** |

### Custo de mensagens das automações (coleta de hora em hora)

Workflow `[MARTHA] Unnichat · Coleta de automações` (minuto 5 de cada hora). Config no
nó "Config": conexão `Martha Guterres 0209`, pasta raiz `[COMERCIAL]` (entra ela e
todas as subpastas: hoje GERAL, BANCO DE EVENTOS, CHECKOUT; a "Comercial" dentro de
"Black Friday 2026" não entra), base `https://unnichat.com.br/api`, intervalo 7 s.

API (credencial `[MARTHA] Unnichat`, header `Authorization: Bearer <token>`). Toda
resposta vem como `{ success, data, metadata, links }`; a paginação segue `links.next`.
Limite informado nos headers: 10/s e 300/min; o espaçamento de 7 s segue a orientação
de `/metrics` ser consulta pesada.

| Chamada | Uso |
|---|---|
| `GET /automation-folders` | acha a pasta raiz pelo nome e as descendentes (`parentId`) |
| `GET /automations` | filtra as automações dessas pastas (`folderId`) |
| `GET /meta/templates` | nome -> categoria (MARKETING, UTILITY, AUTHENTICATION) |
| `GET /automations/{id}/metrics` | contadores acumulados por node |
| `GET /automations/{id}` | o nome do template fica no `text` do node de envio de template. Só é chamado quando as métricas têm node `send_template` |

#### `unnichat_automacoes_metricas` (bruta)
Foto horária das métricas, uma linha por automação x node x hora. Métricas são
**acumuladas desde a criação**: a view tira a diferença entre fotos, e a primeira foto
de cada node é base (não consumo daquela hora).

| Coluna | Origem |
|---|---|
| `coletado_em` | **obr.** início da hora da coleta em America/Sao_Paulo |
| `automacao_id` | **obr.** |
| `node_id` | **obr.** `nodeId`; `_total` = `totals.messages` da automação |
| `automacao_nome`, `pasta`, `automacao_ativa` | da listagem |
| `node_tipo`, `message_type` | `type`, `messageType` do node (`_total` no total) |
| `conexao` | rótulo da config |
| `enviados`, `entregues`, `lidos`, `falhas` | `messages.sent/delivered/read/failed` |
| `raw_payload` | **obr.** o node; na linha `_total`, a resposta inteira |

Só entram nodes com bloco `messages` (nodes de mensagem). **Automação zerada não grava
foto** (`totals.messages.sent = 0`): entra a partir da primeira hora em que enviar algo.
Na view, hora sem foto = sem consumo; a diferença é contra a foto anterior que existir.

#### `unnichat_templates` (bruta, estado atual)
Templates do WhatsApp da conta, da mesma chamada `/meta/templates` (sem chamada extra).
Liga o id da Meta (o mesmo do node de template em automações e broadcasts) à categoria.

| Coluna | Origem |
|---|---|
| `template_id` | **obr.** `id` (id da Meta) |
| `nome`, `categoria`, `idioma`, `status` | `name`, `category`, `language`, `status` |
| `raw_payload` | **obr.** o template |
| `visto_em` | **obr.** última coleta que viu o template; apagado não é removido |

A categoria guardada é a atual. Se a Meta reclassificar um template, o histórico passa a
ser lido com a categoria nova (tratar com vigência se acontecer).

#### `unnichat_automacoes_nodes` (bruta, estado atual)
Dimensão regravada a cada coleta. Liga cada node de mensagem ao template e à categoria
de cobrança da Meta.

| Coluna | Origem |
|---|---|
| `automacao_id`, `node_id` | **obr.** chave |
| `automacao_nome`, `pasta`, `node_tipo`, `message_type` | métricas |
| `template_nome` | `text` do node no detalhe (só `send_template`) |
| `template_categoria` | categoria do template em `/meta/templates` |
| `categoria_cobranca` | `template_categoria` em node de template; `SERVICE` nos demais |
| `raw_payload` | **obr.** `{ metricas: node, detalhe: node }` |
| `visto_em` | **obr.** última coleta que viu o node |

Se trocarem o template de um node, o histórico desse node passa a ser lido com o
template novo (raro; tratar com vigência se acontecer).

#### Regra de custo (decidida em 05/11/2026, revista em 13/11/2026)
Conferência de 13/11/2026: a carteira do Unnichat debitou R$ 3.186,65 de 01 a 12/11
(broadcast R$ 1.465,80, automações R$ 1.242,25, live chat R$ 478,60) e o CIC mostrava
R$ 1.233,60 de custo comercial contra ~R$ 1.950 real. Causas: o Unnichat cobra por
mensagem **enviada**, a R$ 0,05 (utility e serviço) e ~R$ 0,35 (marketing), e a
mensagem do fluxo depois do clique entra como serviço no custo do broadcast.
Prova: LT1 de 12/11 = 293 templates + 8 mensagens de fluxo = 301 x 0,05 = R$ 15,05,
igual ao `cost` da API (LT5 R$ 15,00 e LT22 R$ 9,95 fecham do mesmo jeito).

1. **Broadcast:** custo = `unnichat_broadcasts.custo_api` (`data.cost.amount` do
   `/broadcasts/{id}/metrics`, em R$; sobe com os cliques, a recoleta de 48 h pega).
   Sem custo: `tpl_enviados` x preço da categoria do template + `srv_enviados` x SERVICE.
2. **Automação** (só a pasta `[COMERCIAL]` e subpastas): `data.cost.amount` vem no node
   `_total` e é o custo ACUMULADO desde a criação. Custo do período = acumulado na
   última foto do período menos o da última foto antes dele (sem foto antes = 0). Foto
   sem custo (coletas antigas) usa o acumulado estimado: enviados de cada node x preço
   da categoria (template) ou SERVICE (demais).
3. **Vendedor:** (`msg_vendedor` + `msg_agendada`) x SERVICE + `tpl_vendedor_utl` x
   UTILITY + `tpl_vendedor_mkt` x MARKETING (estimado; não há custo na API).
4. **Preço** em `whatsapp_preco` (config com vigência; mudou o preço = nova linha).
   Desde 01/11/2026 (carteira Unnichat, conferida em 13/11/2026): UTILITY, SERVICE e
   AUTHENTICATION R$ 0,05; MARKETING R$ 0,35. Linhas de 01/10/2026 (rate card Meta:
   R$ 0,035 e R$ 0,3217) ficam como histórico.
5. **Marketing** (`[Disparo]`) fica fora do CIC.
6. **Live chat fora do CRM:** o custo de vendedor só vê os contatos do universo da coleta
   `Conversas do dia` (CRM comercial). O aviso `fora_crm` da `cic_mensageria` compara as
   mensagens recebidas do painel do Unnichat (`unnichat_painel_dia`) com as recebidas de
   contatos do CRM (`unnichat_conversas_dia.msg_lead`), só nos dias com as duas fontes.
   É indicador, não custo: muita mensagem de fora do CRM é respondida por automação.
- **Serviço** = mensagem que não é template (texto, botão, mídia) enviada pela empresa.
  Fontes, uma por tipo (sem somar duas vezes): bot = esta coleta; vendedores =
  `unnichat_conversas_dia` (`msg_vendedor`, `msg_agendada`); broadcast = `srv_*` de
  `unnichat_broadcasts`. As contagens de automação em `conversas_dia` só servem pra
  conferência.
- **Franquia de serviço:** 1.000 grátis por número por mês. Não é rateada por automação:
  todo serviço enviado é custeado pelo preço SERVICE e a franquia entra como desconto do
  mês no total do número (1.000 x SERVICE; R$ 50/mês desde 01/11/2026).

### `unnichat_blocklist` (webhook `/webhook/martha-guterres/unnichat/blocklist`)
Contato que pediu pra não receber mais mensagens. Chamado por um passo de requisição
HTTP nos fluxos de disparo e automação do Unnichat.

| Coluna | Tipo | Nota |
|---|---|---|
| `telefone` | text | **obr.** só dígitos com DDI, 10 a 15 dígitos (o banco recusa outro formato) |
| `contact_id`, `nome` | text | |
| `origem` | text | nome do fluxo que gerou a saída |
| `codigo_copy` | text | copy que gerou a saída |
| `bloqueado_em` | timestamptz | se não mandar, o banco usa a hora do recebimento |
| `ativo` | boolean | `true` bloqueia (padrão); mandar `false` pra desbloquear |
| `raw_payload` | jsonb | **obr.** |

Toda lista de disparo gerada no banco exclui `ativo = true`. Formato de telefone
errado faz o upsert falhar e cai no `[MARTHA] Erros`: tratar na hora, senão o contato
continua recebendo.

**Origem no Unnichat:** automação `[COMERCIAL] Negócio fechado perdido - BLOCKLIST`
(conexão Martha Guterres 0209; a 8538 está em desuso e não tem blocklist). Gatilho
filtra por motivo de perda. Passos: tag > arquivar > POST (este webhook) > opt-out
nativo. O opt-out é obrigatoriamente o último passo no Unnichat.

**Body recebido:** varia entre automações. O workflow só depende de `data.phoneNumber`.
Exemplo atual:
`{"data":{"id","name","email","phoneNumber","field":{...,"Origem"},"profilePicUrl","eventDate"}}`

**Mapeamento** (workflow `[MARTHA] Unnichat · Blocklist`, nó "Mapear contato"):

| Coluna | De onde vem |
|---|---|
| `telefone` | `data.phoneNumber` só com dígitos; 10 ou 11 dígitos ganham `55` na frente. Fora de 10 a 15 dígitos o workflow para com erro (vai pro `[MARTHA] Erros`). Nono dígito não é normalizado aqui (fica pra view de disparo) |
| `contact_id` | `data.id` |
| `nome` | `data.name` |
| `origem` | `fluxo` no topo do body ou, se não houver, `data.fluxo` |
| `codigo_copy` | `data.codigoCopy` ou `data.field["Código Copy"]` |
| `bloqueado_em` | `data.eventDate` só se for ISO com data e hora (sem fuso assume -03:00); senão a coluna não é enviada e o banco usa a hora do recebimento |
| `ativo` | sempre `true`. Não existe desbloqueio nesta operação |
| `raw_payload` | body inteiro |

Campo ausente ou vazio não é enviado (em vez de `null`), pra não apagar valor já gravado
quando outro envio chega com body mais pobre. `email` e `profilePicUrl` são ignorados
(ficam só no `raw_payload`).

### `unnichat_broadcasts` (coleta agendada, de hora em hora)
Workflow `[MARTHA] Unnichat · Coleta de broadcasts` (minuto 15 de cada hora). Cada coleta
regrava o broadcast inteiro (os contadores sobem até o fim). Config no nó "Config":
conexão 0209, prefixos, data inicial `2026-11-04T00:00:00-03:00`, lista de status,
status finais, intervalo 7 s, recoleta 48 h.

**Quais entram:**
- Broadcast não tem pasta (`folderId` nulo): o filtro é pelo **prefixo do nome**,
  `[COMERCIAL]` ou `COMERCIAL_`, sem diferenciar maiúscula.
- `GET /broadcasts?createdFrom=<data inicial>&perPage=20&status=...` com **todos** os
  status do enum (repetindo `status=`), lixeira inclusive: `draft, idle, processing,
  success, error, archived, awaiting-processing, paused, trash, locked, active,
  inactive`. Paginação por `cursor`.
- **Zerado fica fora:** só entra broadcast que começou a enviar (`startedAt` preenchido e
  `contactsAmount > 0`). Agendado, rascunho e arquivado sem envio entram quando
  começarem.

**Recoleta (eficiência):** antes do loop o workflow lê `broadcast_id, status,
finished_at` do banco e só chama `GET /broadcasts/{id}/metrics` quando o broadcast não
está no banco, ou o status mudou, ou não está em status final (`success`, `error`,
`archived`, `trash`), ou não tem `finished_at`, ou finalizou há menos de 48 h.

**Mapeamento** (resposta `{ success, data }`):

| Coluna | Origem |
|---|---|
| `broadcast_id` | **obr.** `id` |
| `nome`, `status`, `contatos` | `name`, `status`, `contactsAmount` |
| `send_at`, `started_at`, `finished_at` | `sendAt`, `startedAt`, `finishedAt` |
| `template_id` | `templateId` do **primeiro node de template** (id da Meta, liga em `unnichat_templates`). O `templateId` do topo do broadcast é id interno do Unnichat e não é usado |
| `tpl_enviados/entregues/lidos/falhas` | soma dos nodes de template (`type = send_template` ou `templateId` preenchido) + o `firstStep` quando `firstStepType = template` |
| `srv_enviados/entregues/lidos/falhas` | soma dos demais nodes de mensagem (sessão) |
| `raw_payload` | **obr.** resposta de metrics inteira (detalhe por node fica aqui) |

O primeiro passo dos broadcasts comerciais costuma não ser mensagem (`firstStepType =
node`) e o template sai num node seguinte; por isso a classificação é por tipo de node,
não por posição. Broadcast com mais de um template: `template_id` guarda o primeiro e o
custo exato por template sai do `raw_payload`.

### `unnichat_painel_dia` (coleta diária, 06h23)
Workflow `[MARTHA] Unnichat · Painel do dia` (VPS, `xijY2Y238pY668Ld`).
`GET /analytics/dashboard?from=&to=&granularity=day` com a credencial
`[MARTHA] Unnichat MG0209`; `from` = o maior entre hoje − `janela_dias` (60) e
`data_inicial` (04/11/2026), `to` = ontem. Upsert de uma linha por dia, chave
`(conexao, dia)`, então recalcula a janela inteira a cada execução (o painel do Unnichat
recalcula com atraso).

| Coluna | Origem (`series[]`) |
|---|---|
| `conexao` | Config do workflow (`Martha Guterres 0209`) |
| `dia` | `date` |
| `mensagens_recebidas` | `messagesReceived` |
| `conversas` | `conversations` (janela de 24 h aberta no cálculo do dia) |
| `contatos_criados` | `contactsCreated` |
| `templates_utility` / `templates_marketing` | `templatesUtility` / `templatesMarketing` (D-1) |
| `raw_payload` | o item da série inteiro |

### `unnichat_conversas_dia` (coleta diária, 23h40)
Workflow `[MARTHA] Unnichat · Conversas do dia`. Mensagens do dia por contato,
separadas por quem enviou: esforço do vendedor e custo de serviço humano.

**Universo do dia** (sem repetir):
- contatos com negócio aberto nas 5 colunas do `[COMERCIAL] Pipeline - Disparo`
  (`GET /crm/pipelines/{id}/deals/column/{columnId}`, paginado);
- contatos com evento de CRM no dia em `unnichat_eventos` (`raw_payload->data->>id`),
  pra pegar quem ganhou ou perdeu e saiu das colunas.

Só o universo comercial: quem recebeu broadcast mas não está no pipeline nem teve evento
não entra. Por isso `tpl_automacao` aqui é menor que o dos broadcasts. Custo de bot e de
broadcast vem das coletas de automações e broadcasts (uma fonte por tipo).

**Mensagens:** `GET /contact/{id}/messages?limit=50`, paginando com `before`
(`metadata.nextBefore`) até passar do início do dia. Resposta REST:
`{ success, data: [ { id, date, type, origin?, senderBy, message?, templateId?,
templateCategory? } ], metadata: { nextBefore } }`, da mais antiga pra mais nova.
Conta só as do dia em America/Sao_Paulo. O formato do MCP é diferente (`sender`,
`text`, sem categoria): o contrato vale pelo REST.

**Classificação** (aprovada em 05/11/2026):

| Coluna | Regra |
|---|---|
| `msg_lead` | `senderBy = contact` |
| `msg_sistema` | `senderBy = platform` (avisos, atribuição de conversa) |
| `tpl_automacao` | `senderBy = user`, `origin = automation`, `type = template` |
| `msg_automacao` | `senderBy = user`, `origin = automation`, demais tipos; origem desconhecida também (vai pro `raw_payload` pra revisar) |
| `msg_agendada` | `senderBy = user`, `origin = schedule` |
| `msg_vendedor` | `senderBy = user`, sem `origin`, tipo diferente de template |
| `tpl_vendedor_mkt` | `senderBy = user`, sem `origin`, `type = template`, `templateCategory = MARKETING` |
| `tpl_vendedor_utl` | idem, `UTILITY`, `AUTHENTICATION` (mesmo preço) ou sem categoria |

Broadcast e automação chegam iguais (`origin = automation`) e não dá pra separar aqui;
por isso `*_automacao` nesta tabela serve só pra conferência.

**Vendedor:** nome do prefixo `[Nome]` das mensagens de vendedor do dia (o que mais
aparece). Sem prefixo no dia, `GET /contact/{id}/assign` (`data.name`, atendente de
agora). `raw_payload.vendedor_fonte` diz qual foi (`prefixo` ou `assign`).

**Grava** só contato com pelo menos 1 mensagem no dia. `raw_payload`: contagens, ids
das mensagens por coluna, templates por categoria (vendedor e automação), fonte do
vendedor, origens desconhecidas e se o contato veio do pipeline ou de evento. Sem texto
de mensagem. O n8n não guarda dados de execução com sucesso deste workflow (teriam o
texto das mensagens); só as com erro.

**Reprocessamento:** `POST /webhook/martha-guterres/unnichat/conversas-dia/reprocessar?dia=YYYY-MM-DD`
com header `x-cic-token` (credencial `[MARTHA] Webhook token`). Upsert por `dia,
contact_id`: reprocessar regrava sem duplicar. Limitação: dia antigo usa o pipeline de
hoje (mais os eventos daquele dia), e o fallback `/assign` traz o atendente de agora.

Ritmo: 0,3 s entre chamadas (limite da API 300/min). Cerca de 280 contatos levam de 7 a
9 min.

## Callix (conta WeRev compartilhada)

A conta atende mais de uma operação. Regra:

1. **Campanhas da Martha na Callix são nomeadas com o prefixo `[MARTHA]`** (mesmo
   padrão do n8n). O workflow `[MARTHA] Callix · *` lê a lista de campanhas, pega os
   ids das que começam com `[MARTHA]` e filtra ANTES de gravar. Só entra no Supabase
   da Martha o que é dessas campanhas. Campanha criada fora do padrão não aparece no
   CIC.
2. Cadastros (`callix_usuarios`, `callix_qualificacoes`) entram inteiros; são
   pequenos e o vínculo agente x vendedor da Martha fica numa tabela de apoio
   (etapa 3).
3. `callix_resumo_1x1_hora` e `callix_performance_agente` são por agente, sem
   campanha. Entram filtrados pelos agentes vinculados à Martha.

**Ressalva:** se o mesmo agente trabalhar em duas operações no mesmo dia, a
performance dele (tempo logado, ligações manuais) aparece inteira nas duas. Não dá
pra separar com o dado da Callix. Aceito pro MVP; se acontecer, a gente trata.

| Tabela | Obrigatórios | Demais colunas |
|---|---|---|
| `callix_ligacoes` | `protocol`, `raw_payload` | callix_ligacao_id, origem, call_type, started_at, answered_at, ended_at, duration_s, service_duration_s, destination_phone, hangup_cause, callix_user_id, agente_nome, callix_qualificacao_id, qualificacao_nome, callix_campanha_id, callix_lista_id |
| `callix_usuarios` | `callix_user_id`, `raw_payload` | nome, email, ramal, equipe_nome, ativo |
| `callix_qualificacoes` | `callix_qualificacao_id`, `raw_payload` | nome, cpc, sucesso |
| `callix_campanhas` | `callix_campanha_id`, `raw_payload` | nome, status |
| `callix_listas` | `callix_lista_id`, `raw_payload` | callix_campanha_id, nome |
| `callix_resumo_hora` | `tipo`, `callix_campanha_id`, `callix_lista_id`, `data`, `hora`, `raw_payload` | discado, completado, perdido, perdido_amd, perdido_num_inexistente, perdido_nao_atende, perdido_falta_agente, perdido_abandono, perdido_outro |
| `callix_resumo_1x1_hora` | `callix_user_id`, `data`, `hora`, `raw_payload` | tentativas, atendidas, perdidas |
| `callix_performance_agente` | `callix_user_id`, `data`, `raw_payload` | available_time_s, in_call_time_s, after_call_time_s, in_break_time_s, idle_time_s, total_time_s, answered_count, manual_calls, campaign_calls, average_service_time_s, first_available, last_offline |

Em `callix_resumo_hora`, resumo sem lista vai com `callix_lista_id = ""` (string
vazia), porque o campo faz parte da chave primária. `hora` = 0 a 23, horário de
Brasília.

## Como validar

Depois do primeiro evento real de cada fonte:

```sql
-- Últimos registros que chegaram, por tabela bruta (rodar no SQL Editor)
select 'hubla_vendas' t, count(*), max(received_at) from hubla_vendas
union all select 'tmb_vendas', count(*), max(received_at) from tmb_vendas
union all select 'unnichat_eventos', count(*), max(received_at) from unnichat_eventos;

-- Reenvio não pode duplicar: mesmo invoice_id deve ter 1 linha
select invoice_id, count(*) from hubla_vendas group by 1 having count(*) > 1;

-- Campos importantes vazios (sinal de mapeamento errado no n8n)
select count(*) filter (where sale_date is null)  sem_data,
       count(*) filter (where total_cents is null) sem_valor,
       count(*) filter (where public.cic_vendedor_de_utm(utm_source) is null) sem_vendedor
from hubla_vendas;
```

## Em aberto

- [ ] Id único do evento no payload do Unnichat (pode trocar a chave de
      `unnichat_eventos`).
- [ ] Regra definitiva do valor TMB (hoje 50%, provisório). Cobrar o Nirla.
