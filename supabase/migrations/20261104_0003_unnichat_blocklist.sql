-- =====================================================================
-- 0003 · Blocklist do Unnichat (bruta)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Contrato: docs/contrato-dados.md (seção Unnichat · unnichat_blocklist)
--
-- Contatos que pediram pra não receber mais mensagens. Alimentada pelo
-- webhook /webhook/martha-guterres/unnichat/blocklist (passo de
-- requisição HTTP nos fluxos do Unnichat). Toda lista de disparo gerada
-- no banco exclui quem está aqui com ativo = true.
-- Desbloquear = mandar o mesmo telefone com ativo = false (não apaga).
-- =====================================================================
create table public.unnichat_blocklist (
  telefone      text primary key,            -- só dígitos, com DDI
  contact_id    text,
  nome          text,
  origem        text,                        -- nome do fluxo que gerou a saída
  codigo_copy   text,                        -- copy que gerou a saída
  bloqueado_em  timestamptz not null default now(),
  ativo         boolean not null default true,
  raw_payload   jsonb not null,
  received_at   timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint unnichat_blocklist_tel_digitos check (telefone ~ '^[0-9]{10,15}$')
);

create trigger trg_unnichat_blocklist_updated before update on public.unnichat_blocklist
  for each row execute function public.set_updated_at();
alter table public.unnichat_blocklist enable row level security;
revoke all on public.unnichat_blocklist from anon, authenticated;
comment on table public.unnichat_blocklist is
  'BRUTA: alimentada pelo n8n (service role). Sem acesso pro app. Contrato: docs/contrato-dados.md';
