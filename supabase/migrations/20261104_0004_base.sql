-- =====================================================================
-- 0004 · Base do CIC (Onda 0)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Docs: docs/escopo.md, docs/banco.md
--
-- Cria: config do cliente, vendedores, perfis (com vínculo automático ao
-- usuário do Auth pelo e-mail), menus por papel, etapas do CRM, motivos de
-- perda, metas, calendário, funções de papel, RLS e o schema tmp_claude
-- com limpeza automática (pg_cron).
--
-- Regras:
--  * O app só LÊ estas tabelas (select para authenticated, via RLS).
--    Edição é feita por SQL pela equipe de ferramentas.
--  * anon não lê nada.
--  * Tudo que é do cliente fica em cic_config ou nas tabelas de cadastro,
--    nunca na lógica.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Config do cliente (chave/valor)
-- ---------------------------------------------------------------------
create table public.cic_config (
  chave         text primary key,
  valor         jsonb not null,
  descricao     text,
  atualizado_em timestamptz not null default now()
);

insert into public.cic_config (chave, valor, descricao) values
  ('cliente_slug',    '"martha-guterres"', 'Slug do cliente (paths de webhook, seletor de projeto)'),
  ('cliente_nome',    '"Martha Guterres"', 'Nome exibido no CIC'),
  ('fuso',            '"America/Sao_Paulo"', 'Fuso de referência para datas e horas'),
  ('tmb_fator_valor', '0.5', 'Fator aplicado ao valor das vendas TMB. PROVISÓRIO (03/11/2026), regra definitiva pendente'),
  ('utm_vendedor',    '{"campo": "utm_source", "prefixo": "comercial-"}', 'Atribuição de venda ao vendedor'),
  ('conversao_alvo',  '{"etapa_base": 2, "pct": 0.15}', 'Conversão alvo: 15% de "2. Em Contato" para venda');

-- ---------------------------------------------------------------------
-- 2. Vendedores (slug = valor do utm_source)
-- ---------------------------------------------------------------------
create table public.vendedores (
  utm_slug   text primary key check (utm_slug ~ '^comercial-[a-z0-9-]+$'),
  nome       text not null,
  email      text not null unique check (email = lower(email)),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

insert into public.vendedores (utm_slug, nome, email) values
  ('comercial-daniele-silva',   'Daniele Silva',   'comercialdaniele85@gmail.com'),
  ('comercial-henrique-cabral', 'Henrique Cabral', 'lhenriquecabralf99@gmail.com'),
  ('comercial-lorena-ruas',     'Lorena Ruas',     'lorenaruasa@hotmail.com'),
  ('comercial-gabriel-poloni',  'Gabriel Poloni',  'gabrielpoloni18@hotmail.com');

-- ---------------------------------------------------------------------
-- 3. Perfis (cadastro prévio por e-mail; user_id preenchido sozinho
--    quando o usuário é criado no Auth)
-- ---------------------------------------------------------------------
create table public.perfis (
  email          text primary key check (email = lower(email)),
  user_id        uuid unique references auth.users(id) on delete set null,
  nome           text not null,
  papel          text not null check (papel in ('admin', 'vendedor')),
  vendedor_slug  text references public.vendedores(utm_slug),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  constraint perfis_vendedor_tem_slug check (papel <> 'vendedor' or vendedor_slug is not null)
);

-- Vínculo automático: usuário criado no Auth -> perfil com o mesmo e-mail
create or replace function public.cic_vincular_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.perfis set user_id = new.id where email = lower(new.email);
  return new;
end $$;

create trigger cic_vincular_usuario
  after insert or update of email on auth.users
  for each row execute function public.cic_vincular_usuario();

-- Vínculo no sentido inverso: perfil cadastrado depois do usuário
create or replace function public.cic_vincular_perfil()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.user_id is null then
    select u.id into new.user_id from auth.users u where lower(u.email) = new.email;
  end if;
  return new;
end $$;

create trigger cic_vincular_perfil
  before insert or update of email on public.perfis
  for each row execute function public.cic_vincular_perfil();

insert into public.perfis (email, nome, papel, vendedor_slug) values
  ('matta@werev.com.br',                'Matta',           'admin',    null),
  ('nirla@werev.com.br',                'Nirla',           'admin',    null),
  ('mitsuo@werev.com.br',               'Mitsuo',          'admin',    null),
  ('godoy.danielaugusto@gmail.com',     'Godoy',           'admin',    null),
  ('comercialdaniele85@gmail.com',      'Daniele Silva',   'vendedor', 'comercial-daniele-silva'),
  ('lhenriquecabralf99@gmail.com',      'Henrique Cabral', 'vendedor', 'comercial-henrique-cabral'),
  ('lorenaruasa@hotmail.com',           'Lorena Ruas',     'vendedor', 'comercial-lorena-ruas'),
  ('gabrielpoloni18@hotmail.com',       'Gabriel Poloni',  'vendedor', 'comercial-gabriel-poloni');

-- ---------------------------------------------------------------------
-- 4. Funções de papel (usadas nas policies e no app)
-- ---------------------------------------------------------------------
create or replace function public.cic_meu_papel()
returns text language sql stable security definer set search_path = '' as $$
  select papel from public.perfis where user_id = auth.uid() and ativo
$$;

create or replace function public.cic_eh_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select papel = 'admin' from public.perfis where user_id = auth.uid() and ativo), false)
$$;

create or replace function public.cic_meu_vendedor()
returns text language sql stable security definer set search_path = '' as $$
  select vendedor_slug from public.perfis where user_id = auth.uid() and ativo
$$;

revoke execute on function public.cic_meu_papel(), public.cic_eh_admin(), public.cic_meu_vendedor()
  from public, anon;
grant execute on function public.cic_meu_papel(), public.cic_eh_admin(), public.cic_meu_vendedor()
  to authenticated;
revoke execute on function public.cic_vincular_usuario(), public.cic_vincular_perfil()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Menus por papel
-- ---------------------------------------------------------------------
create table public.perfil_menus (
  papel  text not null check (papel in ('admin', 'vendedor')),
  menu   text not null check (menu in ('home','metadomes','mensageria','discadora','desempenho',
                                       'minhapagina','relatorios','taxapassagem','motivosperda',
                                       'ciclovenda','reembolsos')),
  ordem  smallint not null,
  primary key (papel, menu)
);

insert into public.perfil_menus (papel, menu, ordem)
select 'admin', m, o from unnest(array['home','metadomes','mensageria','discadora','desempenho',
  'minhapagina','relatorios','taxapassagem','motivosperda','ciclovenda','reembolsos'])
  with ordinality as t(m, o);

insert into public.perfil_menus (papel, menu, ordem) values
  ('vendedor', 'minhapagina', 1),
  ('vendedor', 'relatorios',  2),
  ('vendedor', 'reembolsos',  3);

-- ---------------------------------------------------------------------
-- 6. Etapas do CRM e motivos de perda (nomes iguais aos do Unnichat)
-- ---------------------------------------------------------------------
create table public.crm_etapas (
  ordem          smallint primary key,
  nome_unnichat  text not null unique,   -- como chega em unnichat_eventos.etapa_crm
  rotulo         text not null           -- como aparece no CIC
);

insert into public.crm_etapas (ordem, nome_unnichat, rotulo) values
  (0, '0. Base/Entrada',             'Base/Entrada'),
  (1, '1. Discadora (Sem Resposta)', 'Discadora (Sem Resposta)'),
  (2, '2. Em Contato',               'Em Contato'),
  (3, '3. Negociação',               'Negociação'),
  (4, '4. Forecast',                 'Forecast');

create table public.motivos_perda (
  nome_unnichat  text primary key,       -- como chega em unnichat_eventos.motivo_perda
  grupo          text not null check (grupo in ('1','2','3','4','cs')),
  rotulo         text not null,
  ordem          smallint not null
);

insert into public.motivos_perda (nome_unnichat, grupo, rotulo, ordem) values
  ('[1] Nunca respondeu abordagem',          '1',  'Nunca respondeu abordagem',          1),
  ('[2] Tentativa de contato esgotada',      '2',  'Tentativa de contato esgotada',      2),
  ('[2] Já é cliente CMP',                   '2',  'Já é cliente CMP',                   3),
  ('[2] Não recebeu a Loja',                 '2',  'Não recebeu a Loja',                 4),
  ('[2] Não gostou do produto',              '2',  'Não gostou do produto',              5),
  ('[2] Não possui verba',                   '2',  'Não possui verba',                   6),
  ('[2] Não é prioridade/interesse',         '2',  'Não é prioridade/interesse',         7),
  ('[3] Não respondeu após negociação',      '3',  'Não respondeu após negociação',      8),
  ('[4] Não respondeu após link enviado',    '4',  'Não respondeu após link enviado',    9),
  ('[cs] Detrator / Blocklist',              'cs', 'Detrator / Blocklist',              10),
  ('[cs] Reembolso/Cancelamento',            'cs', 'Reembolso/Cancelamento',            11);

-- ---------------------------------------------------------------------
-- 7. Metas (faixas por mês)
-- ---------------------------------------------------------------------
create table public.metas (
  mes        date not null check (extract(day from mes) = 1),
  nivel      text not null check (nivel in ('bronze','prata','ouro')),
  valor      numeric(14,2) not null check (valor > 0),
  criado_em  timestamptz not null default now(),
  primary key (mes, nivel)
);

insert into public.metas (mes, nivel, valor) values
  ('2026-11-01', 'bronze', 100000),
  ('2026-11-01', 'prata',  150000),
  ('2026-11-01', 'ouro',   200000);

-- ---------------------------------------------------------------------
-- 8. Calendário (dias úteis = seg a sex sem feriado nacional)
-- ---------------------------------------------------------------------
create table public.dim_calendario (
  data      date primary key,
  dia_util  boolean not null,
  feriado   text
);

insert into public.dim_calendario (data, dia_util, feriado)
select d::date,
       extract(isodow from d) < 6 and f.nome is null,
       f.nome
from generate_series('2026-11-01'::date, '2026-12-31'::date, interval '1 day') d
left join (values
  ('2026-11-02'::date, 'Finados'),
  ('2026-11-15'::date, 'Proclamação da República'),
  ('2026-11-20'::date, 'Dia da Consciência Negra'),
  ('2026-12-25'::date, 'Natal')
) f(data, nome) on f.data = d::date;

-- ---------------------------------------------------------------------
-- 9. RLS e permissões
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['cic_config','vendedores','perfis','perfil_menus',
                           'crm_etapas','motivos_perda','metas','dim_calendario'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- Leitura geral para quem tem perfil ativo
create policy cic_config_le     on public.cic_config     for select to authenticated using ((select public.cic_meu_papel()) is not null);
create policy crm_etapas_le     on public.crm_etapas     for select to authenticated using ((select public.cic_meu_papel()) is not null);
create policy motivos_perda_le  on public.motivos_perda  for select to authenticated using ((select public.cic_meu_papel()) is not null);
create policy metas_le          on public.metas          for select to authenticated using ((select public.cic_meu_papel()) is not null);
create policy dim_calendario_le on public.dim_calendario for select to authenticated using ((select public.cic_meu_papel()) is not null);

-- Admin vê todos; vendedor vê só o próprio registro
create policy vendedores_le on public.vendedores for select to authenticated
  using ((select public.cic_eh_admin()) or utm_slug = (select public.cic_meu_vendedor()));

create policy perfis_le on public.perfis for select to authenticated
  using ((select public.cic_eh_admin()) or user_id = (select auth.uid()));

-- Cada um vê só os menus do próprio papel (admin vê a tabela inteira)
create policy perfil_menus_le on public.perfil_menus for select to authenticated
  using ((select public.cic_eh_admin()) or papel = (select public.cic_meu_papel()));

-- ---------------------------------------------------------------------
-- 10. Schema tmp_claude (views de trabalho com validade de 12h)
--     Carimbo no comentário: expira_em=<timestamptz ISO sem espaço>,
--     ex.: expira_em=2026-11-04T22:00:00-03. Sem carimbo = removida.
-- ---------------------------------------------------------------------
create schema if not exists tmp_claude;
revoke all on schema tmp_claude from public, anon, authenticated;
comment on schema tmp_claude is
  'Views temporárias de trabalho/diagnóstico. Comentário obrigatório: expira_em=<timestamptz> (máx. 12h). Limpeza de hora em hora.';

create or replace function tmp_claude.limpar_views_expiradas()
returns integer language plpgsql security definer set search_path = '' as $$
declare r record; n integer := 0; exp timestamptz;
begin
  for r in
    select c.oid, c.relname, c.relkind, obj_description(c.oid, 'pg_class') as cmt
    from pg_class c
    where c.relnamespace = 'tmp_claude'::regnamespace and c.relkind in ('v','m')
  loop
    begin
      exp := substring(r.cmt from 'expira_em=(\S+)')::timestamptz;
    exception when others then
      exp := null;
    end;
    if exp is null or exp < now() then
      execute format('drop %s if exists tmp_claude.%I cascade',
                     case r.relkind when 'm' then 'materialized view' else 'view' end, r.relname);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

revoke execute on function tmp_claude.limpar_views_expiradas() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('limpar-views-tmp-claude', '5 * * * *',
                     $$select tmp_claude.limpar_views_expiradas()$$);
