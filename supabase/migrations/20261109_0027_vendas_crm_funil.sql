-- =====================================================================
-- 0027 · Vendas nas telas de CRM e funil padrão
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md ("Regras gerais de contagem", 09/11/2026)
--
-- 1. Regra padrão de venda: toda tela que conta venda usa só a venda comercial
--    válida (cic_vendas_validas com vendedor pelo utm_source), crédito pelo utm.
--    cic_vendas_crm casa cada venda com o negócio do CRM da pessoa (último
--    evento com negócio antes da compra) e a etapa em que ele estava na compra.
-- 2. cic_taxa_passagem: coluna vendas = vendas comerciais do período pela etapa
--    do negócio na compra; vendas sem negócio no CRM antes da compra numa linha
--    à parte (ordem null). Filtro de vendedor pelo utm.
-- 3. cic_ciclo_venda: casos de venda = vendas comerciais do período (crédito
--    pelo utm), ciclo = compra − entrada do negócio; sem negócio entra em
--    "sem histórico". Perdas sem mudança.
-- 4. cic_meta_funil: venda sem evento de CRM antes da compra vai pro funil
--    padrão (cic_config.funil_padrao), não mais "Sem funil".
-- =====================================================================

insert into public.cic_config (chave, valor, descricao) values
  ('funil_padrao', '"Disparos BF26"'::jsonb, 'Funil das vendas comerciais sem evento de CRM antes da compra (Meta do mês, matriz por funil)')
on conflict (chave) do update set valor = excluded.valor, descricao = excluded.descricao, atualizado_em = now();

create or replace function public.cic_vendas_crm(p_inicio date, p_fim date)
returns table (invoice_id text, vendedor_slug text, sale_date timestamptz, negocio_id text, entrada_ts timestamptz, ordem_venda integer)
language sql stable security definer set search_path = '' as $$
  select x.invoice_id, x.vendedor_slug, h.sale_date, u.negocio_id, n.entrada_ts, n.ordem
  from public.cic_vendas_validas(p_inicio, p_fim) x
  join public.hubla_vendas h on h.invoice_id = x.invoice_id
  left join lateral (
    select e.negocio_id from public.unnichat_eventos e
    where e.pessoa_chave = h.pessoa_chave and e.negocio_id is not null and e.event_ts <= h.sale_date
    order by e.event_ts desc limit 1) u on true
  left join lateral (
    select min(e.event_ts) entrada_ts, max(c.ordem) filter (where e.event_ts <= h.sale_date) ordem
    from public.unnichat_eventos e left join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
    where e.negocio_id = u.negocio_id) n on u.negocio_id is not null
  where x.vendedor_slug is not null
$$;
revoke execute on function public.cic_vendas_crm(date, date) from public, anon, authenticated;

drop function if exists public.cic_taxa_passagem(date, date, text);
create function public.cic_taxa_passagem(p_inicio date, p_fim date, p_vendedor text default null)
returns table (ordem integer, etapa text, entraram bigint, avancaram bigint, passagem numeric, perdidos bigint, vendas bigint, abertos bigint)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then raise exception 'sem permissão' using errcode = '42501'; end if;
  return query
  with neg as (select * from public.cic_negocios() n where p_vendedor is null or p_vendedor = '' or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor),
  ent as (select distinct e.negocio_id, c.ordem from public.unnichat_eventos e join public.crm_etapas c on c.nome_unnichat = e.etapa_crm where e.event_ts >= v_ini and e.event_ts < v_fim),
  b as (select ent.ordem, neg.*, (neg.venda_ts is not null and neg.venda_ts < v_fim) vendeu from ent join neg on neg.negocio_id = ent.negocio_id),
  -- vendas comerciais do período, crédito pelo utm, pela etapa do negócio na compra
  vc as (select * from public.cic_vendas_crm(p_inicio, p_fim) v where p_vendedor is null or p_vendedor = '' or v.vendedor_slug = p_vendedor)
  select x.* from (
    select c.ordem::int o, c.rotulo,
           count(b.negocio_id)::bigint,
           count(b.negocio_id) filter (where b.max_ordem > c.ordem or b.vendeu)::bigint,
           case when count(b.negocio_id) > 0 then round((count(b.negocio_id) filter (where b.max_ordem > c.ordem or b.vendeu))::numeric / count(b.negocio_id), 4) end,
           (select count(*) from neg where neg.lost_ts >= v_ini and neg.lost_ts < v_fim and coalesce(neg.grupo, '') <> 'cs' and neg.perda_ordem = c.ordem)::bigint,
           (select count(*) from vc where vc.ordem_venda = c.ordem)::bigint,
           count(b.negocio_id) filter (where not b.vendeu and b.lost_ts is null and b.max_ordem = c.ordem)::bigint
    from public.crm_etapas c left join b on b.ordem = c.ordem
    group by c.ordem, c.rotulo
    union all
    select null::int, 'Sem negócio no CRM antes da venda', 0::bigint, 0::bigint, null::numeric, 0::bigint,
           (select count(*) from vc where vc.ordem_venda is null)::bigint, 0::bigint
    where exists (select 1 from vc where vc.ordem_venda is null)
  ) x order by x.o nulls last;
end $$;
revoke execute on function public.cic_taxa_passagem(date, date, text) from public, anon;
grant execute on function public.cic_taxa_passagem(date, date, text) to authenticated;

create or replace function public.cic_ciclo_venda(p_inicio date, p_fim date, p_vendedor text default null)
returns table (tipo text, vendedor_slug text, vendedor_nome text, vendedor_ativo boolean, casos bigint, mediana_h numeric, media_h numeric,
               ate_1d bigint, de_1a3d bigint, de_3a7d bigint, mais_7d bigint, sem_historico bigint)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then raise exception 'sem permissão' using errcode = '42501'; end if;
  return query
  with neg as (select * from public.cic_negocios() n where p_vendedor is null or p_vendedor = '' or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor),
  vc as (select * from public.cic_vendas_crm(p_inicio, p_fim) v where p_vendedor is null or p_vendedor = '' or v.vendedor_slug = p_vendedor),
  c as (
    -- venda: venda comercial do período, crédito pelo utm; sem negócio antes da compra = sem histórico (h nulo)
    select 'venda'::text t, vc.vendedor_slug vs, extract(epoch from vc.sale_date - vc.entrada_ts) / 3600 h from vc
    union all
    select 'perda', neg.vendedor_slug, extract(epoch from neg.lost_ts - neg.entrada_ts) / 3600 from neg where neg.lost_ts >= v_ini and neg.lost_ts < v_fim and coalesce(neg.grupo, '') <> 'cs'
  ),
  g as (
    select c.t, case when grouping(c.vs) = 1 then '_time' else coalesce(c.vs, '_sem') end vs,
           count(*) filter (where c.h >= 0.1) casos,
           percentile_cont(0.5) within group (order by c.h) filter (where c.h >= 0.1) med,
           avg(c.h) filter (where c.h >= 0.1) med_a,
           count(*) filter (where c.h >= 0.1 and c.h <= 24) f1, count(*) filter (where c.h > 24 and c.h <= 72) f2,
           count(*) filter (where c.h > 72 and c.h <= 168) f3, count(*) filter (where c.h > 168) f4,
           count(*) filter (where c.h < 0.1 or c.h is null) sh
    from c group by c.t, rollup(c.vs)
  )
  select g.t, g.vs, case g.vs when '_time' then 'Time' when '_sem' then 'Sem vendedor' else vd.nome end, vd.ativo,
         g.casos::bigint, round(g.med::numeric, 1), round(g.med_a::numeric, 1), g.f1::bigint, g.f2::bigint, g.f3::bigint, g.f4::bigint, g.sh::bigint
  from g left join public.vendedores vd on vd.utm_slug = g.vs
  order by g.t desc, (g.vs = '_time') desc, g.casos desc;
end $$;

-- Meta do mês: venda sem evento de CRM antes da compra vai pro funil padrão.
-- Troca só esse trecho do corpo da 0025.
do $d$
declare d text := pg_get_functiondef('public.cic_meta_funil(date)'::regprocedure);
        a text := $x$coalesce(u.funil, 'Sem funil') funil$x$;
begin
  if position(a in d) = 0 then raise exception 'trecho da 0025 não encontrado em cic_meta_funil'; end if;
  d := replace(d, a, $x$coalesce(u.funil, coalesce((select cf.valor #>> '{}' from public.cic_config cf where cf.chave = 'funil_padrao'), 'Sem funil')) funil$x$);
  execute d;
end $d$;
