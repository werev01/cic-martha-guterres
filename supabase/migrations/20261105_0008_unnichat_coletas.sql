-- =====================================================================
-- 0008 · Coletas agendadas do Unnichat (custo de mensagens)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Contrato: docs/contrato-dados.md (Unnichat · coletas)
--
-- Custo de mensagem por coleta agendada (não por webhook; unnichat_automacoes
-- não é alimentada, decidido em 04/11/2026).
--
-- a) unnichat_automacoes_metricas: foto horária de /automations/{id}/metrics.
--    Uma linha por automação x node x hora; node_id = '_total' guarda os
--    totais. Métricas são acumuladas desde a criação: a view tira a diferença
--    entre fotos (a primeira foto de cada node é a base, não consumo da hora).
-- b) unnichat_broadcasts.template_id: template usado no disparo.
-- c) unnichat_automacoes_nodes: dimensão (estado atual) ligando o node ao
--    template e à categoria de cobrança da Meta. Regravada a cada coleta.
-- d) whatsapp_preco: preço da Meta por categoria, com vigência. Config
--    genérica (não é dado da Martha). SERVICE tem franquia de 1.000/mês por
--    número, tratada como desconto do mês no total (decidido em 05/11/2026).
-- =====================================================================

-- a) Foto horária das métricas das automações (bruta)
create table public.unnichat_automacoes_metricas (
  coletado_em      timestamptz not null,   -- início da hora da coleta (America/Sao_Paulo)
  automacao_id     text not null,
  node_id          text not null,          -- '_total' = totais da automação
  automacao_nome   text,
  pasta            text,
  automacao_ativa  boolean,
  node_tipo        text,
  message_type     text,
  conexao          text,
  enviados         integer,
  entregues        integer,
  lidos            integer,
  falhas           integer,
  raw_payload      jsonb not null,
  received_at      timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (automacao_id, node_id, coletado_em)
);
create trigger trg_unnichat_automacoes_metricas_updated
  before update on public.unnichat_automacoes_metricas
  for each row execute function public.set_updated_at();
alter table public.unnichat_automacoes_metricas enable row level security;
revoke all on public.unnichat_automacoes_metricas from anon, authenticated;
comment on table public.unnichat_automacoes_metricas is
  'BRUTA: foto horária de /automations/{id}/metrics (n8n, service role). Sem acesso pro app. Contrato: docs/contrato-dados.md';

-- b) Broadcasts: template usado (custo por categoria sai do template)
alter table public.unnichat_broadcasts add column if not exists template_id text;

-- c) Dimensão dos nodes de mensagem das automações (estado atual)
create table public.unnichat_automacoes_nodes (
  automacao_id        text not null,
  node_id             text not null,
  automacao_nome      text,
  pasta               text,
  node_tipo           text,
  message_type        text,          -- send_template, interactive-message, text...
  template_nome       text,          -- só nodes de template (do detalhe da automação)
  template_categoria  text,          -- MARKETING / UTILITY / AUTHENTICATION (de /templates)
  categoria_cobranca  text,          -- template_categoria, ou SERVICE se não for template
  raw_payload         jsonb not null,
  visto_em            timestamptz not null,  -- última coleta que viu o node
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  primary key (automacao_id, node_id)
);
create trigger trg_unnichat_automacoes_nodes_updated
  before update on public.unnichat_automacoes_nodes
  for each row execute function public.set_updated_at();
alter table public.unnichat_automacoes_nodes enable row level security;
revoke all on public.unnichat_automacoes_nodes from anon, authenticated;
comment on table public.unnichat_automacoes_nodes is
  'BRUTA: nodes de mensagem das automações com template e categoria de cobrança (n8n, service role). Sem acesso pro app. Contrato: docs/contrato-dados.md';

-- d) Preço da Meta por categoria, com vigência
create table public.whatsapp_preco (
  categoria      text not null,               -- MARKETING, UTILITY, AUTHENTICATION, SERVICE
  vigente_desde  date not null,
  preco_brl      numeric(10,4) not null,      -- por mensagem entregue
  franquia_mes   integer not null default 0,  -- SERVICE: grátis por número/mês
  fonte          text,
  primary key (categoria, vigente_desde)
);
alter table public.whatsapp_preco enable row level security;
revoke all on public.whatsapp_preco from anon, authenticated;
comment on table public.whatsapp_preco is
  'CONFIG: preço da Meta (WhatsApp, Brasil) por mensagem entregue, com vigência. Mudou o preço = nova linha. App lê só via view.';

insert into public.whatsapp_preco (categoria, vigente_desde, preco_brl, franquia_mes, fonte) values
  ('MARKETING',      '2026-10-01', 0.3217, 0,    'rate card Meta BR, vigência 01/10/2026'),
  ('UTILITY',        '2026-10-01', 0.0350, 0,    'rate card Meta BR, vigência 01/10/2026'),
  ('AUTHENTICATION', '2026-10-01', 0.0350, 0,    'rate card Meta BR, vigência 01/10/2026'),
  ('SERVICE',        '2026-10-01', 0.0350, 1000, 'rate card Meta BR, vigência 01/10/2026; 1.000 grátis por número/mês');
