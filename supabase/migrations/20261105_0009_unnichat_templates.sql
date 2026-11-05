-- =====================================================================
-- 0009 · Templates do WhatsApp (dimensão)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Contrato: docs/contrato-dados.md (Unnichat · unnichat_templates)
--
-- id da Meta -> nome e categoria de cobrança (MARKETING / UTILITY /
-- AUTHENTICATION). Alimentada pela coleta de automações, que já baixa
-- /meta/templates toda hora (sem chamada extra). Usada no custo de
-- broadcasts (unnichat_broadcasts.template_id) e de automações
-- (unnichat_automacoes_nodes.template_nome).
-- Template apagado não é removido: para de atualizar (visto_em antigo).
-- =====================================================================
create table public.unnichat_templates (
  template_id  text primary key,       -- id da Meta (o mesmo do node de template)
  nome         text not null,
  categoria    text,                   -- MARKETING / UTILITY / AUTHENTICATION
  idioma       text,
  status       text,                   -- APPROVED / PENDING / REJECTED
  raw_payload  jsonb not null,
  visto_em     timestamptz not null,   -- última coleta que viu o template
  received_at  timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_unnichat_templates_updated before update on public.unnichat_templates
  for each row execute function public.set_updated_at();
alter table public.unnichat_templates enable row level security;
revoke all on public.unnichat_templates from anon, authenticated;
comment on table public.unnichat_templates is
  'BRUTA: templates do WhatsApp da conta (n8n, service role). Sem acesso pro app. Contrato: docs/contrato-dados.md';
