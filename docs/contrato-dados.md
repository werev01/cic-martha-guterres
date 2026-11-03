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

- **Vendedor da venda = `utm_source`.** O padrão é `comercial-nome-sobrenome` (ex.:
  `utm_source=comercial-ana-souza`). A view lê só o `utm_source` e cruza com o
  cadastro de vendedores. Venda sem `comercial-*` no `utm_source` fica como "sem
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
| Unnichat | `unnichat_automacoes` | webhook | `contact_id,telefone,codigo_copy,minuto` |
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

Webhook: `/webhook/martha-guterres/hubla/eventos`, com Switch pelo tipo de evento.

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
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | text | `utm_source` traz o `comercial-*` |
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
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | text | primeiro toque; `utm_source` traz o `comercial-*` |
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
| `raw_payload` | jsonb | **obr.** |

Se o payload do Unnichat trouxer um id único do evento, trocamos a chave pra ele
(migration pequena). Mandar o primeiro payload real pra eu conferir.

### `unnichat_automacoes` (webhook `/webhook/martha-guterres/unnichat/automacoes`)
| Coluna | Tipo | Nota |
|---|---|---|
| `minuto` | timestamptz | **obr.** horário do envio, truncado no minuto |
| `contact_id`, `telefone` | text | entram na chave |
| `codigo_copy` | text | entra na chave |
| `fluxo`, `funil`, `tipo`, `msg` | text | |
| `cadencia`, `disparo`, `envios` | int | partes do código de copy |
| `raw_payload` | jsonb | **obr.** |

### `unnichat_broadcasts` (coleta agendada, de hora em hora)
`broadcast_id` **obr.**, `nome`, `status`, `contatos`, `send_at`, `started_at`,
`finished_at`, contadores `tpl_enviados/entregues/lidos/falhas` e
`srv_enviados/entregues/lidos/falhas` (int), `raw_payload` **obr.** Cada coleta
regrava o broadcast inteiro (os contadores sobem até o fim).

### `unnichat_conversas_dia` (coleta diária, 23h40)
`dia` **obr.**, `contact_id` **obr.**, `telefone`, `vendedor`, contadores
`msg_vendedor`, `msg_agendada`, `tpl_vendedor_utl`, `tpl_vendedor_mkt`,
`msg_automacao`, `tpl_automacao`, `msg_lead`, `msg_sistema` (int), `raw_payload`
**obr.**

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
       count(*) filter (where utm_source is null or utm_source not like 'comercial-%') sem_vendedor
from hubla_vendas;
```

## Em aberto

- [ ] Id único do evento no payload do Unnichat (pode trocar a chave de
      `unnichat_eventos`).
- [ ] Regra definitiva do valor TMB (hoje 50%, provisório). Cobrar o Nirla.
