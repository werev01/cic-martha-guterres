-- =====================================================================
-- 0001 · Tabelas brutas (camada alimentada pelo n8n)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Contrato: docs/contrato-dados.md
-- Aplicada em 03/11/2026 via MCP (nome: 20261103_0001_brutas).
--
-- Regras desta camada:
--  * Toda tabela tem chave única de negócio, usada no upsert do n8n
--    (?on_conflict=<colunas>).
--  * raw_payload guarda o JSON original inteiro; received_at/updated_at
--    são preenchidos pelo banco.
--  * RLS ligado e SEM policy: anon e authenticated não leem nada.
--    Só a service role (credencial do n8n) grava. O app lê só views.
--  * Nada de regra de negócio aqui (vendedor por UTM, valor TMB 50%,
--    conversão de centavos): isso fica nas views da etapa 3.
-- =====================================================================

-- Trigger genérico de updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- HUBLA
-- ---------------------------------------------------------------------

-- Vendas (fatura paga e mudanças de status da fatura)
create table public.hubla_vendas (
  id                  uuid primary key default gen_random_uuid(),
  invoice_id          text not null,
  event_type          text,
  status              text,
  subscription_id     text,
  product_id          text,
  product_name        text,
  offer_id            text,
  offer_name          text,
  payer_id            text,
  payer_nome          text,
  payer_email         text,
  payer_telefone      text,
  payer_documento     text,
  payment_method      text,
  installments        int,
  coupon_code         text,
  subtotal_cents      bigint,
  discount_cents      bigint,
  total_cents         bigint,
  seller_net_cents    bigint,
  utm_source          text,
  utm_medium          text,
  utm_campaign        text,
  utm_content         text,
  utm_term            text,
  sale_date           timestamptz,
  invoice_created_at  timestamptz,
  invoice_modified_at timestamptz,
  raw_payload         jsonb not null,
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint hubla_vendas_uk unique (invoice_id)
);

-- Reembolsos (um registro por fatura e tipo de evento de reembolso)
create table public.hubla_reembolsos (
  id                  uuid primary key default gen_random_uuid(),
  invoice_id          text not null,
  event_type          text not null,
  refund_id           text,
  refund_status       text,
  refund_description  text,
  refund_feedback     text,
  is_auto_accepted    boolean,
  product_id          text,
  product_name        text,
  offer_id            text,
  offer_name          text,
  payer_nome          text,
  payer_email         text,
  payer_telefone      text,
  payment_method      text,
  total_cents         bigint,
  utm_source          text,
  utm_medium          text,
  utm_campaign        text,
  utm_content         text,
  utm_term            text,
  sale_date           timestamptz,
  refund_created_at   timestamptz,
  refunded_at         timestamptz,
  raw_payload         jsonb not null,
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint hubla_reembolsos_uk unique (invoice_id, event_type)
);

-- Carrinho abandonado
create table public.hubla_carrinho_abandonado (
  id               uuid primary key default gen_random_uuid(),
  lead_id          text not null,
  lead_created_at  timestamptz not null,
  event_type       text,
  nome             text,
  email            text,
  telefone         text,
  product_id       text,
  product_name     text,
  offer_id         text,
  offer_name       text,
  checkout_url     text,
  utm_source       text,
  utm_medium       text,
  utm_campaign     text,
  utm_content      text,
  utm_term         text,
  raw_payload      jsonb not null,
  received_at      timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint hubla_carrinho_abandonado_uk unique (lead_id, lead_created_at)
);

-- Pagamento recusado
create table public.hubla_recusadas (
  id               uuid primary key default gen_random_uuid(),
  invoice_id       text not null,
  failed_at        timestamptz not null,
  event_type       text,
  status           text,
  product_id       text,
  product_name     text,
  offer_id         text,
  offer_name       text,
  payer_nome       text,
  payer_email      text,
  payer_telefone   text,
  payment_method   text,
  installments     int,
  total_cents      bigint,
  sale_date        timestamptz,
  raw_payload      jsonb not null,
  received_at      timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint hubla_recusadas_uk unique (invoice_id, failed_at)
);

-- ---------------------------------------------------------------------
-- TMB
-- ---------------------------------------------------------------------

create table public.tmb_vendas (
  id                  uuid primary key default gen_random_uuid(),
  pedido_id           bigint not null,
  status_pedido       text,
  status_financeiro   text,
  cliente             text,
  email               text,
  telefone            text,
  documento           text,
  produto_id          bigint,
  produto_nome        text,
  valor_total         numeric(12,2),
  parcelas            int,
  valor_entrada       numeric(12,2),
  valor_parcela       numeric(12,2),
  utm_source          text,
  utm_medium          text,
  utm_campaign        text,
  utm_content         text,
  utm_term            text,
  utm_last_source     text,
  utm_last_medium     text,
  utm_last_campaign   text,
  utm_last_content    text,
  criado_em           timestamptz,
  data_efetivado      timestamptz,
  raw_payload         jsonb not null,
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint tmb_vendas_uk unique (pedido_id)
);

create table public.tmb_reembolsos (
  id                    uuid primary key default gen_random_uuid(),
  pedido_id             bigint not null,
  status_pedido         text,
  status_financeiro     text,
  cliente               text,
  email                 text,
  telefone              text,
  produto_id            bigint,
  produto_nome          text,
  valor_total           numeric(12,2),
  parcelas              int,
  utm_source            text,
  utm_medium            text,
  utm_campaign          text,
  utm_content           text,
  utm_term              text,
  criado_em             timestamptz,
  data_efetivado        timestamptz,
  reembolsado_em        timestamptz,
  raw_payload           jsonb not null,
  received_at           timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint tmb_reembolsos_uk unique (pedido_id)
);

-- ---------------------------------------------------------------------
-- UNNICHAT
-- ---------------------------------------------------------------------

-- Eventos de CRM (webhook). Chave = id do evento quando o Unnichat
-- mandar; enquanto não confirmado, a chave é composta.
create table public.unnichat_eventos (
  id               bigint generated always as identity primary key,
  event_ts         timestamptz not null,
  telefone         text not null,
  acao             text not null,
  etapa_crm        text,
  email            text,
  nome             text,
  origem           text,
  status           text,
  proprietario     text,
  conexao          text,
  pipeline         text,
  produto          text,
  oferta           text,
  forma_pagamento  text,
  valor_total      numeric(12,2),
  valor_liquido    numeric(12,2),
  motivo_perda     text,
  codigo_copy      text,
  raw_payload      jsonb not null,
  received_at      timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint unnichat_eventos_uk unique nulls not distinct (telefone, acao, etapa_crm, event_ts)
);

-- Broadcasts (coleta agendada na API)
create table public.unnichat_broadcasts (
  broadcast_id   text primary key,
  nome           text,
  status         text,
  contatos       int,
  send_at        timestamptz,
  started_at     timestamptz,
  finished_at    timestamptz,
  tpl_enviados   int,
  tpl_entregues  int,
  tpl_lidos      int,
  tpl_falhas     int,
  srv_enviados   int,
  srv_entregues  int,
  srv_lidos      int,
  srv_falhas     int,
  raw_payload    jsonb not null,
  received_at    timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Conversas por dia e contato (coleta diária)
create table public.unnichat_conversas_dia (
  dia               date not null,
  contact_id        text not null,
  telefone          text,
  vendedor          text,
  msg_vendedor      int,
  msg_agendada      int,
  tpl_vendedor_utl  int,
  tpl_vendedor_mkt  int,
  msg_automacao     int,
  tpl_automacao     int,
  msg_lead          int,
  msg_sistema       int,
  raw_payload       jsonb not null,
  received_at       timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (dia, contact_id)
);

-- Mensagens de automação com Código Copy (webhook)
create table public.unnichat_automacoes (
  id           bigint generated always as identity primary key,
  minuto       timestamptz not null,
  contact_id   text,
  telefone     text,
  codigo_copy  text,
  fluxo        text,
  funil        text,
  tipo         text,
  msg          text,
  cadencia     int,
  disparo      int,
  envios       int,
  raw_payload  jsonb not null,
  received_at  timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint unnichat_automacoes_uk unique nulls not distinct (contact_id, telefone, codigo_copy, minuto)
);

-- ---------------------------------------------------------------------
-- CALLIX (conta WeRev compartilhada: o n8n filtra pelas campanhas da
-- operação antes de gravar; ver contrato)
-- ---------------------------------------------------------------------

create table public.callix_ligacoes (
  protocol               text primary key,
  callix_ligacao_id      text,
  origem                 text,
  call_type              int,
  started_at             timestamptz,
  answered_at            timestamptz,
  ended_at               timestamptz,
  duration_s             int,
  service_duration_s     int,
  destination_phone      text,
  hangup_cause           int,
  callix_user_id         text,
  agente_nome            text,
  callix_qualificacao_id text,
  qualificacao_nome      text,
  callix_campanha_id     text,
  callix_lista_id        text,
  raw_payload            jsonb not null,
  received_at            timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create table public.callix_usuarios (
  callix_user_id  text primary key,
  nome            text,
  email           text,
  ramal           text,
  equipe_nome     text,
  ativo           boolean,
  raw_payload     jsonb not null,
  received_at     timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table public.callix_qualificacoes (
  callix_qualificacao_id  text primary key,
  nome                    text,
  cpc                     boolean,
  sucesso                 boolean,
  raw_payload             jsonb not null,
  received_at             timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create table public.callix_campanhas (
  callix_campanha_id  text primary key,
  nome                text,
  status              text,
  raw_payload         jsonb not null,
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table public.callix_listas (
  callix_lista_id     text primary key,
  callix_campanha_id  text,
  nome                text,
  raw_payload         jsonb not null,
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table public.callix_resumo_hora (
  tipo                     text not null,
  callix_campanha_id       text not null,
  callix_lista_id          text not null default '',
  data                     date not null,
  hora                     smallint not null,
  discado                  int,
  completado               int,
  perdido                  int,
  perdido_amd              int,
  perdido_num_inexistente  int,
  perdido_nao_atende       int,
  perdido_falta_agente     int,
  perdido_abandono         int,
  perdido_outro            int,
  raw_payload              jsonb not null,
  received_at              timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  primary key (tipo, callix_campanha_id, callix_lista_id, data, hora)
);

create table public.callix_resumo_1x1_hora (
  callix_user_id  text not null,
  data            date not null,
  hora            smallint not null,
  tentativas      int,
  atendidas       int,
  perdidas        int,
  raw_payload     jsonb not null,
  received_at     timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (callix_user_id, data, hora)
);

create table public.callix_performance_agente (
  callix_user_id          text not null,
  data                    date not null,
  available_time_s        int,
  in_call_time_s          int,
  after_call_time_s       int,
  in_break_time_s         int,
  idle_time_s             int,
  total_time_s            int,
  answered_count          int,
  manual_calls            int,
  campaign_calls          int,
  average_service_time_s  int,
  first_available         timestamptz,
  last_offline            timestamptz,
  raw_payload             jsonb not null,
  received_at             timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  primary key (callix_user_id, data)
);

-- ---------------------------------------------------------------------
-- Gatilho updated_at, RLS e permissões (todas as brutas)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'hubla_vendas','hubla_reembolsos','hubla_carrinho_abandonado','hubla_recusadas',
    'tmb_vendas','tmb_reembolsos',
    'unnichat_eventos','unnichat_broadcasts','unnichat_conversas_dia','unnichat_automacoes',
    'callix_ligacoes','callix_usuarios','callix_qualificacoes','callix_campanhas',
    'callix_listas','callix_resumo_hora','callix_resumo_1x1_hora','callix_performance_agente'
  ] loop
    execute format('create trigger trg_%1$s_updated before update on public.%1$I
                    for each row execute function public.set_updated_at()', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('comment on table public.%I is %L', t,
                   'BRUTA: alimentada pelo n8n (service role). Sem acesso pro app. Contrato: docs/contrato-dados.md');
  end loop;
end $$;

-- Índices para as views da etapa 3 (filtros por data)
create index on public.hubla_vendas (sale_date);
create index on public.hubla_reembolsos (refunded_at);
create index on public.tmb_vendas (data_efetivado);
create index on public.unnichat_eventos (event_ts);
create index on public.unnichat_eventos (codigo_copy);
create index on public.callix_ligacoes (started_at);
create index on public.callix_ligacoes (callix_user_id);
