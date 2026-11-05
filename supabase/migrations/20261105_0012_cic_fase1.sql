-- =====================================================================
-- 0012 · CIC fase 1: Minha página, Meta do mês e Home
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Decisões fechadas, 05/11/2026). Mapa: docs/banco.md
--
-- 1. Trava: venda paga nunca é alterada (status, valor, nada). Reembolso
--    é outra linha, em hubla_reembolsos.
-- 2. Funções internas (sem acesso do app): vendas válidas, reembolsos
--    válidos e contatos em "2. Em Contato".
-- 3. RPCs do app (security definer, filtro de perfil dentro):
--    cic_vendedor_mes, cic_meta_mes, cic_home.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Venda paga não muda
-- ---------------------------------------------------------------------
create or replace function public.hubla_vendas_trava_paga()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status = 'paid' then
    return null;  -- venda paga é definitiva: ignora qualquer atualização
  end if;
  return new;
end $$;

create trigger trg_hubla_vendas_trava_paga
  before update on public.hubla_vendas
  for each row execute function public.hubla_vendas_trava_paga();

-- ---------------------------------------------------------------------
-- 2. Funções internas
-- ---------------------------------------------------------------------
-- Venda válida: status = 'paid', data = sale_date em São Paulo,
-- valor = líquido (seller_net_cents/100). Vendedor pelo utm_source.
create or replace function public.cic_vendas_validas(p_inicio date, p_fim date)
returns table (invoice_id text, dia date, produto text, liquido numeric, bruto numeric, vendedor_slug text)
language sql stable security definer set search_path = '' as $$
  select v.invoice_id,
         (v.sale_date at time zone 'America/Sao_Paulo')::date,
         v.product_name,
         coalesce(v.seller_net_cents, 0) / 100.0,
         coalesce(v.total_cents, 0) / 100.0,
         public.cic_vendedor_de_utm(v.utm_source)
  from public.hubla_vendas v
  where v.status = 'paid'
    and v.sale_date >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
    and v.sale_date <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
$$;

-- Reembolso válido: só invoice.refunded, um por fatura, no dia do reembolso.
-- Sem venda paga no banco, não há reembolso. Abate o líquido da venda,
-- do vendedor da venda original.
create or replace function public.cic_reembolsos_validos(p_inicio date, p_fim date)
returns table (invoice_id text, dia date, liquido numeric, vendedor_slug text)
language sql stable security definer set search_path = '' as $$
  with r as (
    select h.invoice_id,
           min((coalesce(h.refunded_at, h.received_at) at time zone 'America/Sao_Paulo')::date) dia
    from public.hubla_reembolsos h
    where h.event_type = 'invoice.refunded'
    group by h.invoice_id
  )
  select r.invoice_id, r.dia,
         coalesce(v.seller_net_cents, 0) / 100.0,
         public.cic_vendedor_de_utm(v.utm_source)
  from r
  join public.hubla_vendas v on v.invoice_id = r.invoice_id and v.status = 'paid'
  where r.dia between p_inicio and p_fim
$$;

-- Contatos distintos (telefone) que entraram em "2. Em Contato" no período,
-- por proprietário do card (= vendedores.nome). Linha com vendedor_slug nulo
-- e por_vendedor = false é o total do time.
create or replace function public.cic_contatos_em_contato(p_inicio date, p_fim date)
returns table (vendedor_slug text, contatos bigint, total_time boolean)
language sql stable security definer set search_path = '' as $$
  with e as (
    select e.telefone, vd.utm_slug
    from public.unnichat_eventos e
    left join public.vendedores vd on vd.nome = e.proprietario
    where e.etapa_crm = '2. Em Contato'
      and e.event_ts >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
      and e.event_ts <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select utm_slug, count(distinct telefone), false from e where utm_slug is not null group by utm_slug
  union all
  select null, count(distinct telefone), true from e
$$;

revoke execute on function public.cic_vendas_validas(date, date),
                           public.cic_reembolsos_validos(date, date),
                           public.cic_contatos_em_contato(date, date)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. RPCs do app
-- ---------------------------------------------------------------------
-- 3.1 Minha página: por vendedor no mês. Admin vê todos; vendedor só o próprio.
create or replace function public.cic_vendedor_mes(p_mes date)
returns table (
  vendedor_slug text, vendedor_nome text,
  vendas_qtd bigint, vendas_liquido numeric, vendas_bruto numeric,
  reembolsos_qtd bigint, reembolsos_liquido numeric, liquido_final numeric,
  nivel smallint, nivel_nome text, pct numeric, comissao numeric,
  proximo_nivel smallint, proximo_nome text, proximo_pct numeric, falta_proximo numeric,
  contatos bigint, conversao numeric, conversao_alvo numeric
)
language sql stable security definer set search_path = '' as $$
  with per as (
    select date_trunc('month', p_mes)::date ini,
           (date_trunc('month', p_mes) + interval '1 month - 1 day')::date fim
  ),
  vend as (
    select vd.utm_slug, vd.nome from public.vendedores vd
    where vd.ativo and (public.cic_eh_admin() or vd.utm_slug = public.cic_meu_vendedor())
  ),
  v as (select x.vendedor_slug, count(*) q, sum(x.liquido) l, sum(x.bruto) b
        from per, public.cic_vendas_validas(per.ini, per.fim) x group by 1),
  r as (select x.vendedor_slug, count(*) q, sum(x.liquido) l
        from per, public.cic_reembolsos_validos(per.ini, per.fim) x group by 1),
  c as (select x.vendedor_slug, x.contatos
        from per, public.cic_contatos_em_contato(per.ini, per.fim) x where not x.total_time),
  alvo as (select coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15) a),
  base as (
    select vend.utm_slug, vend.nome,
           coalesce(v.q, 0) vq, coalesce(v.l, 0) vl, coalesce(v.b, 0) vb,
           coalesce(r.q, 0) rq, coalesce(r.l, 0) rl,
           coalesce(v.l, 0) - coalesce(r.l, 0) lf,
           coalesce(c.contatos, 0) ct
    from vend
    left join v on v.vendedor_slug = vend.utm_slug
    left join r on r.vendedor_slug = vend.utm_slug
    left join c on c.vendedor_slug = vend.utm_slug
  )
  select b.utm_slug, b.nome, b.vq, round(b.vl, 2), round(b.vb, 2), b.rq, round(b.rl, 2), round(b.lf, 2),
         k.nivel, k.nome, k.pct, k.comissao, k.proximo_nivel, k.proximo_nome, k.proximo_pct, k.falta_proximo,
         b.ct, case when b.ct > 0 then round(b.vq::numeric / b.ct, 4) end, alvo.a
  from base b
  cross join per
  cross join alvo
  left join lateral public.cic_comissao(b.lf, per.ini) k on true
  order by b.lf desc, b.nome
$$;

-- 3.2 Meta do mês (só admin). Comercial = vendas com vendedor, líquido final
-- (vendas - reembolsos do mês). Projeção: ritmo por dia útil contado desde o
-- dia da primeira venda paga do mês (hoje incluso) até o fim do mês.
-- Falta por dia útil: dias úteis depois de hoje.
create or replace function public.cic_meta_mes(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini date := date_trunc('month', p_mes)::date;
  v_fim date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_primeira date;
  v_liq numeric; v_vq bigint; v_rl numeric; v_rq bigint;
  v_du_mes int; v_du_decorr int; v_du_rest int; v_du_janela int;
  v_proj numeric;
  v_res jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  select min(x.dia) into v_primeira from public.cic_vendas_validas(v_ini, v_fim) x;

  select count(*), coalesce(sum(x.liquido), 0) into v_vq, v_liq
  from public.cic_vendas_validas(v_ini, v_fim) x where x.vendedor_slug is not null;
  select count(*), coalesce(sum(x.liquido), 0) into v_rq, v_rl
  from public.cic_reembolsos_validos(v_ini, v_fim) x where x.vendedor_slug is not null;
  v_liq := v_liq - v_rl;

  select count(*) filter (where d.dia_util),
         count(*) filter (where d.dia_util and d.data >= coalesce(v_primeira, v_hoje) and d.data <= least(v_hoje, v_fim)),
         count(*) filter (where d.dia_util and d.data > v_hoje),
         count(*) filter (where d.dia_util and d.data >= coalesce(v_primeira, v_hoje))
    into v_du_mes, v_du_decorr, v_du_rest, v_du_janela
  from public.dim_calendario d where d.data between v_ini and v_fim;

  v_proj := case when v_du_decorr > 0 then round(v_liq / v_du_decorr * v_du_janela, 2) end;

  select jsonb_build_object(
    'mes', v_ini,
    'liquido', round(v_liq, 2),
    'vendas_qtd', v_vq,
    'reembolsos_qtd', v_rq,
    'reembolsos_liquido', round(v_rl, 2),
    'primeira_venda', v_primeira,
    'dias_uteis_mes', v_du_mes,
    'dias_uteis_decorridos', v_du_decorr,
    'dias_uteis_restantes', v_du_rest,
    'projecao', v_proj,
    'metas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nivel', m.nivel, 'valor', m.valor,
               'pct', case when m.valor > 0 then round(v_liq / m.valor, 4) end,
               'falta', greatest(m.valor - v_liq, 0),
               'falta_dia_util', case when v_du_rest > 0 then round(greatest(m.valor - v_liq, 0) / v_du_rest, 2) end)
             order by m.valor)
      from public.metas m where m.mes = v_ini), '[]'::jsonb),
    'serie', coalesce((
      select jsonb_agg(jsonb_build_object('dia', s.dia, 'vendas_qtd', s.q, 'liquido', s.l, 'acumulado', s.ac) order by s.dia)
      from (
        select t.*, sum(t.l) over (order by t.dia) ac from (
          select d.data dia,
                 (select count(*) from public.cic_vendas_validas(d.data, d.data) x where x.vendedor_slug is not null) q,
                 round(coalesce((select sum(x.liquido) from public.cic_vendas_validas(d.data, d.data) x where x.vendedor_slug is not null), 0)
                     - coalesce((select sum(x.liquido) from public.cic_reembolsos_validos(d.data, d.data) x where x.vendedor_slug is not null), 0), 2) l
          from public.dim_calendario d
          where d.data between v_ini and least(v_hoje, v_fim)
        ) t
      ) s), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

-- 3.3 Home (só admin): total da operação no período, comercial e orgânico separados.
create or replace function public.cic_home(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  with v as (select * from public.cic_vendas_validas(p_inicio, p_fim)),
       r as (select * from public.cic_reembolsos_validos(p_inicio, p_fim)),
       dias as (select generate_series(p_inicio, p_fim, interval '1 day')::date dia),
       ct as (select x.contatos from public.cic_contatos_em_contato(p_inicio, p_fim) x where x.total_time)
  select jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim,
    'serie', (
      select jsonb_agg(jsonb_build_object(
               'dia', d.dia,
               'comercial_qtd',     (select count(*) from v where v.dia = d.dia and v.vendedor_slug is not null),
               'comercial_liquido', (select coalesce(round(sum(v.liquido), 2), 0) from v where v.dia = d.dia and v.vendedor_slug is not null),
               'comercial_bruto',   (select coalesce(round(sum(v.bruto), 2), 0) from v where v.dia = d.dia and v.vendedor_slug is not null),
               'organico_qtd',      (select count(*) from v where v.dia = d.dia and v.vendedor_slug is null),
               'organico_liquido',  (select coalesce(round(sum(v.liquido), 2), 0) from v where v.dia = d.dia and v.vendedor_slug is null),
               'organico_bruto',    (select coalesce(round(sum(v.bruto), 2), 0) from v where v.dia = d.dia and v.vendedor_slug is null),
               'reembolso_comercial', (select coalesce(round(sum(r.liquido), 2), 0) from r where r.dia = d.dia and r.vendedor_slug is not null),
               'reembolso_organico',  (select coalesce(round(sum(r.liquido), 2), 0) from r where r.dia = d.dia and r.vendedor_slug is null))
             order by d.dia)
      from dias d),
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'produto', p.produto,
               'comercial_qtd', p.cq, 'comercial_liquido', p.cl,
               'organico_qtd', p.oq, 'organico_liquido', p.ol) order by p.cl + p.ol desc)
      from (select coalesce(v.produto, '(sem produto)') produto,
                   count(*) filter (where v.vendedor_slug is not null) cq,
                   coalesce(round(sum(v.liquido) filter (where v.vendedor_slug is not null), 2), 0) cl,
                   count(*) filter (where v.vendedor_slug is null) oq,
                   coalesce(round(sum(v.liquido) filter (where v.vendedor_slug is null), 2), 0) ol
            from v group by 1) p), '[]'::jsonb),
    'conversao', jsonb_build_object(
      'vendas_comercial', (select count(*) from v where v.vendedor_slug is not null),
      'contatos', coalesce((select ct.contatos from ct), 0),
      'taxa', (select case when ct.contatos > 0
                           then round((select count(*) from v where v.vendedor_slug is not null)::numeric / ct.contatos, 4) end from ct),
      'alvo', coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15))
  ) into v_res;
  return v_res;
end $$;

revoke execute on function public.cic_vendedor_mes(date), public.cic_meta_mes(date), public.cic_home(date, date)
  from public, anon;
grant execute on function public.cic_vendedor_mes(date), public.cic_meta_mes(date), public.cic_home(date, date)
  to authenticated;
