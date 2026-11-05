-- =====================================================================
-- 0015 · Telas de gestão: Desempenho, Taxa de passagem, Motivos de perda, Ciclo
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Telas de gestão, 05/11/2026). Mapa: docs/banco.md
--
-- Negócio = negocio_id em unnichat_eventos.
-- Vendedor do negócio = proprietario do evento mais recente do negócio
--   (fallback: mesmo telefone, últimos 8 dígitos); fora do cadastro de
--   vendedores = sem vendedor.
-- Entrada = primeiro evento do negócio. Etapa da perda = última etapa antes
--   do lost. Grupo do motivo = código entre colchetes do próprio texto.
--   Grupo cs (Detrator/Blocklist, Reembolso/Cancelamento) não é perda comercial.
-- Ganho = venda paga na Hubla (sempre), casada pelo telefone:
--   DDI + DDD + últimos 8 dígitos, com venda depois da entrada.
-- Ciclo: desfecho a menos de 6 min da entrada = sem histórico, fica fora da
--   mediana/média e é contado à parte.
-- Período pela data do evento em America/Sao_Paulo. Todas só admin.
-- =====================================================================

-- 1. Cadastro (decidido em 05/11)
update public.motivos_perda set nome_unnichat = '[2] Já é cliente'
 where nome_unnichat = '[2] Já é cliente CMP';

insert into public.vendedores (utm_slug, nome, email)
select 'comercial_daniel-godoy', 'Daniel Godoy', p.email from public.perfis p where p.nome = 'Godoy'
on conflict (utm_slug) do nothing;
update public.perfis set vendedor_slug = 'comercial_daniel-godoy'
 where nome = 'Godoy' and papel = 'admin' and vendedor_slug is null;   -- segue admin

-- 2. Chave de telefone pro casamento lead x venda (DDI + DDD + últimos 8)
create or replace function public.cic_fone_chave(p text)
returns text language sql immutable set search_path = '' as $$
  select case when d = '' then null else left(d, 4) || right(d, 8) end
  from (select case when length(x) in (10, 11) then '55' || x else x end d
        from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') x) a) b
$$;

-- 3. Negócios (interna): um registro por negocio_id
create or replace function public.cic_negocios()
returns table (
  negocio_id text, entrada_ts timestamptz, lost_ts timestamptz, max_ordem int,
  vendedor_slug text, motivo text, grupo text, perda_ordem int, venda_ts timestamptz
)
language sql stable security definer set search_path = '' as $$
  with ev as (
    select e.negocio_id, e.event_ts, e.status, e.proprietario, e.motivo_perda, c.ordem,
           public.cic_fone_chave(e.telefone) chave
    from public.unnichat_eventos e
    left join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
    where e.negocio_id is not null
  ),
  n as (
    select ev.negocio_id,
           min(ev.event_ts) entrada_ts,
           min(ev.event_ts) filter (where ev.status = 'lost') lost_ts,
           max(ev.ordem) max_ordem,
           (array_agg(ev.chave order by ev.event_ts desc) filter (where ev.chave is not null))[1] chave,
           (array_agg(ev.proprietario order by ev.event_ts desc) filter (where ev.proprietario is not null))[1] prop
    from ev group by ev.negocio_id
  ),
  h as (
    select public.cic_fone_chave(v.payer_telefone) chave, v.sale_date
    from public.hubla_vendas v
    where v.status in ('paid', 'refunded', 'chargeback', 'chargedback') and v.sale_date is not null
  )
  select n.negocio_id, n.entrada_ts, n.lost_ts, n.max_ordem,
         vd.utm_slug,
         l.motivo_perda,
         substring(l.motivo_perda from '^\s*\[([^\]]+)\]'),
         (select e4.ordem from ev e4
           where e4.negocio_id = n.negocio_id and e4.ordem is not null and e4.event_ts <= n.lost_ts
           order by e4.event_ts desc limit 1),
         (select min(h.sale_date) from h where h.chave = n.chave and h.sale_date >= n.entrada_ts)
  from n
  left join lateral (
    select coalesce(n.prop, (select e2.proprietario from ev e2
                              where right(e2.chave, 8) = right(n.chave, 8) and e2.proprietario is not null
                              order by e2.event_ts desc limit 1)) nome
  ) p on true
  left join public.vendedores vd on vd.nome = p.nome
  left join lateral (
    select e3.motivo_perda from ev e3
    where e3.negocio_id = n.negocio_id and e3.status = 'lost' order by e3.event_ts limit 1
  ) l on true
$$;

revoke execute on function public.cic_fone_chave(text), public.cic_negocios() from public, anon, authenticated;

-- Período em timestamptz (SP)
-- p_inicio 00:00 até p_fim 23:59:59 em America/Sao_Paulo

-- 4. Desempenho: por vendedor ativo
create or replace function public.cic_desempenho(p_inicio date, p_fim date, p_vendedor text default null)
returns table (
  vendedor_slug text, vendedor_nome text,
  vendas_qtd bigint, liquido numeric,
  mes_liquido numeric, nivel smallint, nivel_nome text, pct numeric, comissao numeric,
  entradas_0 bigint, entradas_1 bigint, entradas_2 bigint, entradas_3 bigint, entradas_4 bigint,
  perdas_comerciais bigint, contatos bigint, conversao numeric, conversao_alvo numeric,
  msgs_vendedor bigint, tpl_vendedor bigint
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return query
  with neg as (select * from public.cic_negocios()),
  vd as (select x.utm_slug, x.nome from public.vendedores x
         where x.ativo and (p_vendedor is null or p_vendedor = '' or x.utm_slug = p_vendedor)),
  v as (select x.vendedor_slug, count(*) q, sum(x.liquido) l
        from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null group by 1),
  mes as (select * from public.cic_vendedor_mes(p_inicio)),
  ent as (
    select neg.vendedor_slug, c.ordem, count(distinct e.negocio_id) q
    from public.unnichat_eventos e
    join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
    join neg on neg.negocio_id = e.negocio_id
    where e.event_ts >= v_ini and e.event_ts < v_fim
    group by 1, 2
  ),
  per as (select neg.vendedor_slug, count(*) q from neg
          where neg.lost_ts >= v_ini and neg.lost_ts < v_fim and coalesce(neg.grupo, '') <> 'cs' group by 1),
  ct as (select x.vendedor_slug, x.contatos from public.cic_contatos_em_contato(p_inicio, p_fim) x where not x.total_time),
  cv as (select c.vendedor, sum(c.msg_vendedor) m, sum(coalesce(c.tpl_vendedor_utl, 0) + coalesce(c.tpl_vendedor_mkt, 0)) t
         from public.unnichat_conversas_dia c where c.dia between p_inicio and p_fim group by 1),
  alvo as (select coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15) a)
  select vd.utm_slug, vd.nome,
         coalesce(v.q, 0)::bigint, round(coalesce(v.l, 0), 2),
         mes.liquido_final, mes.nivel, mes.nivel_nome, mes.pct, mes.comissao,
         coalesce((select ent.q from ent where ent.vendedor_slug = vd.utm_slug and ent.ordem = 0), 0)::bigint,
         coalesce((select ent.q from ent where ent.vendedor_slug = vd.utm_slug and ent.ordem = 1), 0)::bigint,
         coalesce((select ent.q from ent where ent.vendedor_slug = vd.utm_slug and ent.ordem = 2), 0)::bigint,
         coalesce((select ent.q from ent where ent.vendedor_slug = vd.utm_slug and ent.ordem = 3), 0)::bigint,
         coalesce((select ent.q from ent where ent.vendedor_slug = vd.utm_slug and ent.ordem = 4), 0)::bigint,
         coalesce(per.q, 0)::bigint,
         coalesce(ct.contatos, 0)::bigint,
         case when coalesce(ct.contatos, 0) > 0 then round(coalesce(v.q, 0)::numeric / ct.contatos, 4) end,
         alvo.a,
         coalesce(cv.m, 0)::bigint, coalesce(cv.t, 0)::bigint
  from vd
  cross join alvo
  left join v on v.vendedor_slug = vd.utm_slug
  left join mes on mes.vendedor_slug = vd.utm_slug
  left join per on per.vendedor_slug = vd.utm_slug
  left join ct on ct.vendedor_slug = vd.utm_slug
  left join cv on cv.vendedor = vd.nome
  order by 4 desc, 2;
end $$;

-- 5. Taxa de passagem: etapas 0 a 4 (time ou um vendedor; '_sem' = sem vendedor)
create or replace function public.cic_taxa_passagem(p_inicio date, p_fim date, p_vendedor text default null)
returns table (ordem int, etapa text, entraram bigint, avancaram bigint, passagem numeric,
               perdidos bigint, vendas bigint, abertos bigint)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return query
  with neg as (
    select * from public.cic_negocios() n
    where p_vendedor is null or p_vendedor = ''
       or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor
  ),
  ent as (
    select distinct e.negocio_id, c.ordem
    from public.unnichat_eventos e
    join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
    where e.event_ts >= v_ini and e.event_ts < v_fim
  ),
  b as (
    select ent.ordem, neg.*,
           (neg.venda_ts is not null and neg.venda_ts < v_fim) vendeu
    from ent join neg on neg.negocio_id = ent.negocio_id
  )
  select c.ordem::int, c.rotulo,
         count(b.negocio_id)::bigint,
         count(b.negocio_id) filter (where b.max_ordem > c.ordem or b.vendeu)::bigint,
         case when count(b.negocio_id) > 0
              then round((count(b.negocio_id) filter (where b.max_ordem > c.ordem or b.vendeu))::numeric / count(b.negocio_id), 4) end,
         (select count(*) from neg
           where neg.lost_ts >= v_ini and neg.lost_ts < v_fim and coalesce(neg.grupo, '') <> 'cs'
             and neg.perda_ordem = c.ordem)::bigint,
         count(b.negocio_id) filter (where b.vendeu and b.max_ordem = c.ordem)::bigint,
         count(b.negocio_id) filter (where not b.vendeu and b.lost_ts is null and b.max_ordem = c.ordem)::bigint
  from public.crm_etapas c
  left join b on b.ordem = c.ordem
  group by c.ordem, c.rotulo
  order by c.ordem;
end $$;

-- 6. Motivos de perda: uma linha por (tipo, grupo, motivo, vendedor, etapa)
create or replace function public.cic_motivos_perda(p_inicio date, p_fim date, p_vendedor text default null)
returns table (tipo text, grupo text, motivo text, vendedor_slug text, vendedor_nome text,
               etapa_ordem int, etapa text, qtd bigint)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return query
  select case when n.grupo = 'cs' then 'cs' else 'comercial' end,
         n.grupo,
         coalesce(n.motivo, 'Motivo não informado'),
         n.vendedor_slug,
         coalesce(vd.nome, 'Sem vendedor'),
         n.perda_ordem,
         coalesce(c.rotulo, 'Sem etapa'),
         count(*)::bigint
  from public.cic_negocios() n
  left join public.vendedores vd on vd.utm_slug = n.vendedor_slug
  left join public.crm_etapas c on c.ordem = n.perda_ordem
  where n.lost_ts >= v_ini and n.lost_ts < v_fim
    and (p_vendedor is null or p_vendedor = ''
         or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor)
  group by 1, 2, 3, 4, 5, 6, 7
  order by 8 desc;
end $$;

-- 7. Ciclo: entrada -> venda paga e entrada -> perda comercial, em horas.
--    Uma linha por tipo e vendedor + linha do time (vendedor_slug = '_time').
create or replace function public.cic_ciclo_venda(p_inicio date, p_fim date, p_vendedor text default null)
returns table (tipo text, vendedor_slug text, vendedor_nome text, casos bigint,
               mediana_h numeric, media_h numeric,
               ate_1d bigint, de_1a3d bigint, de_3a7d bigint, mais_7d bigint, sem_historico bigint)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return query
  with neg as (
    select * from public.cic_negocios() n
    where p_vendedor is null or p_vendedor = ''
       or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor
  ),
  c as (
    select 'venda'::text t, neg.vendedor_slug vs, extract(epoch from neg.venda_ts - neg.entrada_ts) / 3600 h
    from neg where neg.venda_ts >= v_ini and neg.venda_ts < v_fim
    union all
    select 'perda', neg.vendedor_slug, extract(epoch from neg.lost_ts - neg.entrada_ts) / 3600
    from neg where neg.lost_ts >= v_ini and neg.lost_ts < v_fim and coalesce(neg.grupo, '') <> 'cs'
  ),
  g as (
    select c.t, case when grouping(c.vs) = 1 then '_time' else coalesce(c.vs, '_sem') end vs,
           count(*) filter (where c.h >= 0.1) casos,
           percentile_cont(0.5) within group (order by c.h) filter (where c.h >= 0.1) med,
           avg(c.h) filter (where c.h >= 0.1) med_a,
           count(*) filter (where c.h >= 0.1 and c.h <= 24) f1,
           count(*) filter (where c.h > 24 and c.h <= 72) f2,
           count(*) filter (where c.h > 72 and c.h <= 168) f3,
           count(*) filter (where c.h > 168) f4,
           count(*) filter (where c.h < 0.1) sh
    from c group by c.t, rollup(c.vs)
  )
  select g.t, g.vs,
         case g.vs when '_time' then 'Time' when '_sem' then 'Sem vendedor' else vd.nome end,
         g.casos::bigint, round(g.med::numeric, 1), round(g.med_a::numeric, 1),
         g.f1::bigint, g.f2::bigint, g.f3::bigint, g.f4::bigint, g.sh::bigint
  from g left join public.vendedores vd on vd.utm_slug = g.vs
  order by g.t desc, (g.vs = '_time') desc, g.casos desc;
end $$;

revoke execute on function public.cic_desempenho(date, date, text), public.cic_taxa_passagem(date, date, text),
                           public.cic_motivos_perda(date, date, text), public.cic_ciclo_venda(date, date, text)
  from public, anon;
grant execute on function public.cic_desempenho(date, date, text), public.cic_taxa_passagem(date, date, text),
                          public.cic_motivos_perda(date, date, text), public.cic_ciclo_venda(date, date, text)
  to authenticated;
