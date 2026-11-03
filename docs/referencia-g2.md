# Referência do G2 (só estrutura)

Mapa do CIC do G2 levantado em 03/11/2026, por autorização do Nirla, para servir de
referência à Martha e ao modelo padrão. Contém só estrutura (tabelas, colunas, chaves,
views, policies, uso nas telas). Nenhum dado foi lido.

- Supabase: CIC-G2 (`moaoqmnbckoaooqutwir`), schema `public`.
- App: `werev01/cic-g2`, arquivo único `index.html` (~1,4 MB), abas por `setTab()`.
- n8n do G2: não lido (decisão: os fluxos da Martha nascem do zero).

Isto é referência, não especificação. O que vale pra Martha está em `escopo.md`,
`padroes-n8n.md` e `contrato-dados.md`.

## 1. Tabelas brutas por fonte

Padrão do G2: `raw_payload jsonb` + `received_at timestamptz` em quase toda bruta.

### Hubla

| Tabela | Chave única | Colunas principais |
|---|---|---|
| `hubla_sales` | `invoice_id` | event_type, invoice_id, subscription_id, product_id/name, offer_id/name, payer_* (id, nome, email, phone, document), payment_method, installments, coupon_code, subtotal/discount/prorata/installment_fee/total/seller_net em `_cents` (int8), total_brl, seller_net_brl, utm_* (5), billing_city/state/country, status, sale_date, invoice_created_at, invoice_modified_at, vendedor |
| `hubla_refunds` | `(invoice_id, event_type)` | invoice/produto/oferta/payer como acima, total_cents/brl, refund_id, refund_description, refund_feedback, refund_status, is_auto_accepted, refund_created_at/updated_at, invoice_status, sale_date, refunded_at, utm_*, seller_net_cents/brl (trigger `fill_refund_seller_net`), vendedor |
| `hubla_abandoned_cart` | `(lead_id, lead_created_at)` | event_type, lead_id, full_name, email, phone, product/offer, checkout_url, utm_*, fbp, fbc, gclid, hb_id, lead_created_at |
| `hubla_declined` | `(invoice_id, failed_at)` | invoice/produto/oferta/payer, payment_method, installments, total_cents/brl, status, failed_at, sale_date |

### TMB

| Tabela | Chave única | Colunas principais |
|---|---|---|
| `tmb_sales` | `pedido_id` | pedido_id (int8), status_pedido, status_financeiro, cliente, documento, email, telefone, nascimento, produto_id/nome, produtor/produtor_id, valor_total, parcelas, valor_entrada, valor_parcela, taxa_administracao, melhor_dia_pagamento, endereço (pais, cep, estado, cidade, bairro, logradouro, numero, complemento, completo), utm_* e utm_last_* (first e last touch), criado_em, data_efetivado, vendedor |
| `tmb_refunds` | `pedido_id` | pedido/cliente/produto como acima, valor_total, parcelas, criado_em, data_efetivado, refunded_detected_at, utm_* e utm_last_* |

### Unnichat

| Tabela | Chave única | Como chega | Colunas principais |
|---|---|---|---|
| `unnichat_events_crm` | `dedupe_key` | webhook | data, hora, event_ts, email, nome, telefone, acao, origem, status, proprietario, conexao, pipeline, etapa_crm, produto, oferta, forma_pagamento, valor_total, valor_liquido, motivo_perda, codigo_copy, vendedor |
| `disparo_broadcast` | `broadcast_id` | coleta agendada (API) | nome, status, contatos, send_at, started_at, finished_at, tpl_* e srv_* (enviados, entregues, lidos, falhas), por_node, primeiro_passo, coletado_em |
| `disparo_conversa_dia` | `(dia, contact_id)` | coleta diária 23h40 | tel_chave, vendedor, contagem de mensagens por tipo (vendedor, agendada, template utl/mkt, automação, lead, sistema) |
| `disparo_automacao` | `(contact_id, tel_chave, codigo, minuto)` NULLS NOT DISTINCT | webhook de automação | dia, codigo, valido, fluxo, funil, tipo, msg, perna, disparo, envios, alerta |
| `unnichat_contato` | `tel_chave` | apoio | contact_id, tel_encontrado, nao_encontrado |

Observação: a regra de montagem do `dedupe_key` está no n8n do G2 (não lido). Pra
Martha, definir no contrato.

### Callix

| Tabela | Chave única | Colunas principais |
|---|---|---|
| `callix_ligacoes` | `protocol` | callix_ligacao_id, origem, call_type, started_at, answered_at, ended_at, duration_s, service_duration_s, destination_phone, hangup_cause, extension, nota, has_audio, audio_link, callix_user_id, agente_nome, qualificação (id, nome, cpc, sucesso), campanha_id, lista_id, data_brt, hora_brt |
| `callix_usuarios` | `callix_user_id` | nome, email, ramal, equipe_id/nome, perfil_acesso, status, ativo |
| `callix_qualificacoes` | `callix_qualificacao_id` | nome, cpc, sucesso, is_system |
| `callix_campanhas` | `callix_campanha_id` | nome, status |
| `callix_listas` | `callix_lista_id` | nome, callix_campanha_id |
| `callix_pausas` | `callix_pausa_id` | nome |
| `callix_performance_agente` | `(callix_user_id, data)` | tempos em segundos (disponível, em ligação, pausa, ociosa etc.), contagens de chamadas, break_times |
| `callix_resumo_hora` | `(tipo, campanha_id, lista_id, data, hora)` | discado, completado, perdido e motivos de perda, ratio_completude |
| `callix_resumo_1x1_hora` | `(callix_user_id, data, hora)` | tentativas, atendidas, perdidas |
| `callix_funil` | `(campanha_id, lista_id, data)` | contatos_unicos, tentativas, atendidas, completadas, cpc, sucesso (vazia no G2) |

## 2. Tabelas de apoio (cadastro manual)

| Tabela | Para que serve | Entra na Martha? |
|---|---|---|
| `profiles` | usuário do app: email, nome, papel, vendedor, time, ativo | sim, adaptada (admin/vendedor + vínculo com projeto) |
| `meta_mensal` | meta por mês/funil/cenário (leads/dia útil, passagem %, conversão %, ticket) | sim (Meta do mês) |
| `meta_vendedor` | meta individual por mês/cenário | sim (Minha página) |
| `dim_calendario` | dias úteis, feriados, peso | sim |
| `cic_vendedor_alias` | normaliza nome do vendedor vindo das fontes | sim |
| `vendedor_utm` | UTM slug -> vendedor (atribuição de venda) | depende da decisão de atribuição |
| `callix_agente_alias` / `_vendedor` / `_papel` | agente Callix -> nome exibido, vendedor, papel | sim (Discadora/Desempenho) |
| `disparo_preco` | preço por tipo de disparo com vigência | sim (custo na Mensageria) |
| `link_produto`, `link_vendedor_tmb` | links de checkout por vendedor (Minha página) | avaliar; os blocos que usam saíram do MVP |
| `comissao_regra`, `lotes_disparo_serie9`, `blocklist` | comissão, lotes de série, blocklist | não |

## 3. Cadeia bruta -> tratada -> tela (só telas do MVP)

| Tela (aba G2) | Lê do banco | Que depende de |
|---|---|---|
| Home (`home`) | `vw_dash_vendas`, `vw_dash_tmb`, `vw_dash_reembolso`, `vw_dash_meta`, `vw_dash_calendario`, `unnichat_events_crm` | hubla_sales/refunds, tmb_sales/refunds, meta_mensal, dim_calendario |
| Meta do mês (`metadomes`) | `vw_dash_meta`, `vw_dash_calendario` + vendas | meta_mensal, dim_calendario |
| Mensageria (`infraestrutura`) | `vw_infra_disparos`, `vw_infra_conversas`, `vw_infra_automacao`, rpcs `cic_infra_campanhas`, `cic_infra_automacao_kpis` | disparo_broadcast, disparo_conversa_dia, disparo_automacao, disparo_preco, unnichat_events_crm (por código de copy via `vw_infra_disparos_codigo`) |
| Discadora (`discadora`) | `vw_callix_dash_agente_dia`, `vw_callix_dash_volume_dia`, `vw_callix_dash_hora`, `vw_callix_dash_heatmap` (`vw_callix_dash_speed` sai: é o gráfico de velocidade) | callix_ligacoes, callix_resumo_hora, callix_resumo_1x1_hora, callix_performance_agente, callix_usuarios, aliases; venda atribuída via `vw_callix_venda_atribuida` (callix_ligacoes + hubla_sales + tmb_sales) |
| Desempenho individual (`vendedores`) | eventos CRM + vendas, calculado no front | unnichat_events_crm, vw_dash_vendas, vw_dash_tmb |
| Minha página (`minhapagina`) | `meta_vendedor`, rpc `cic_meus_links` + eventos e vendas filtrados pelo vendedor | meta_vendedor, link_* |
| Relatórios (`relatorios`) | eventos CRM + vendas, calculado no front | idem Desempenho |
| Taxa de passagem (`taxapassagem`) | eventos CRM, calculado no front | unnichat_events_crm |
| Motivos de Perda (`motivosperda`) | `vw_dash_perda_etapa` (sobre MV `mv_dash_perda_etapa`) | unnichat_events_crm |
| Ciclo de Vendas (`ciclovenda`) | `vw_dash_ciclo_venda`, `vw_dash_ciclo_perda` (sobre MVs `mv_ciclo_venda`, `mv_ciclo_perda`, `mv_ciclo_leva`) | unnichat_events_crm, hubla_sales, tmb_sales |
| Reembolsos (`reembolsos`) | `vw_dash_reembolso` | hubla_refunds, tmb_refunds, tmb_sales |

Funções de apoio: `cic_meu_papel()`, `cic_eh_admin()`, `cic_eh_gestor()`,
`cic_meu_vendedor()`, `cic_novo_usuario()` (trigger de cadastro), `cic_set_vendedor()`,
`cic_vendedor_de_utm()`, `cic_etapa_grupo()`, `cic_etapa_ordinal()`,
`cic_motivo_tipo()`, `cic_assinatura_fontes()` (md5 das views de venda, pro front
saber se precisa recarregar), `set_updated_at()`.

MVs atualizadas por cron (no G2, `mv_dash_perda_etapa` em HH:07).

## 4. Policies (como o G2 faz)

- Brutas de Callix e `unnichat_events_crm`: SELECT liberado pra qualquer usuário com
  papel (`cic_meu_papel() is not null`).
- Brutas de Hubla e TMB: SELECT só gestor/admin (`cic_eh_gestor()`).
- `disparo_*` e `unnichat_contato`: só admin.
- `meta_vendedor`: gestor vê tudo, vendedor só a própria linha.
- `profiles`: o próprio usuário ou gestor.

## 5. Armadilhas e o que NÃO repetir na Martha

1. **Bruta exposta ao app.** No G2 o front lê `unnichat_events_crm` e as brutas da
   Callix direto. Na Martha, bruta não tem policy pro app; o app lê só view/tratada.
2. **Tabela inteira no navegador.** O G2 baixava `unnichat_events_crm` inteiro (~22 MB)
   a cada refresh. Na Martha, agregação no banco (views/MVs/rpcs) e paginação.
3. **Regra de negócio no front.** Ex.: a TMB entra com valor cheio na view e o JS
   aplica a metade. Na Martha, regra de valor fica no banco ou na config do cliente,
   nunca espalhada no JS.
4. **Referência morta.** O app do G2 cita a rpc `cic_infra_codigo`, que não existe mais
   no banco. Na Martha, toda view/rpc usada pelo app fica listada em doc e conferida
   no teste ponta a ponta.
5. **Monolito.** O app do G2 é um `index.html` de 1,4 MB. Na Martha, app enxuto,
   separado por tela, com config do cliente isolada.
6. **Papel "gestor".** O G2 tem admin, gestor e vendedor. O MVP da Martha tem só admin
   e vendedor.
7. **Nomenclatura.** O G2 ainda tem `perna` em `disparo_automacao`; o padrão atual é
   "cadência". Na Martha, usar `cadencia`.
