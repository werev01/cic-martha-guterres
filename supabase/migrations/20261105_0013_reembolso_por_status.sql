-- =====================================================================
-- 0013 · Reembolso também pelo status da venda
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (CIC fase 1). Corrige a 0012.
--
-- Diagnóstico (05/11): hubla_reembolsos vazia; o único reembolso real chegou
-- pelo webhook de Vendas (invoice.status_updated -> refunded). Com a trava da
-- 0012, paid não vira mais refunded e nenhum reembolso abateria comissão.
--
-- 1. Trava: venda paga só aceita ir pra refunded, chargeback ou chargedback,
--    e aí muda só status, event_type e invoice_modified_at (valores, UTM e
--    payload da venda ficam os originais). Qualquer outra mudança de uma
--    linha paid é ignorada. Linha refunded/chargeback não muda mais.
-- 2. Venda válida = foi paga um dia (paid, refunded, chargeback, chargedback),
--    no mês do sale_date.
-- 3. Reembolso = hubla_reembolsos (invoice.refunded) OU status
--    refunded/chargeback/chargedback na venda. Um por invoice_id. Data =
--    refunded_at do reembolso; sem ele, invoice_modified_at da venda.
--    Valor = líquido da venda. Abate no mês do reembolso.
-- 4. cic_home só com o comercial (orgânico fica no banco, fora do dash).
-- =====================================================================

-- 1. Trava
create or replace function public.hubla_vendas_trava_paga()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status in ('refunded', 'chargeback', 'chargedback') then
    return null;  -- reembolso/chargeback é final
  end if;
  if old.status = 'paid' then
    if new.status in ('refunded', 'chargeback', 'chargedback') then
      -- muda só o status e a data; valores, UTM e payload da venda ficam os originais
      old.status := new.status;
      old.event_type := new.event_type;
      old.invoice_modified_at := new.invoice_modified_at;
      return old;
    end if;
    return null;  -- paid não regride (overdue, unpaid, pending...) nem é reescrita
  end if;
  return new;
end $$;

-- 2. Venda válida: foi paga um dia
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
  where v.status in ('paid', 'refunded', 'chargeback', 'chargedback')
    and v.sale_date >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
    and v.sale_date <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
$$;

-- 3. Reembolso de qualquer fonte, um por fatura
create or replace function public.cic_reembolsos_validos(p_inicio date, p_fim date)
returns table (invoice_id text, dia date, liquido numeric, vendedor_slug text)
language sql stable security definer set search_path = '' as $$
  with ree as (
    select h.invoice_id, min(coalesce(h.refunded_at, h.received_at)) ts
    from public.hubla_reembolsos h
    where h.event_type = 'invoice.refunded'
    group by h.invoice_id
  ),
  r as (
    select v.invoice_id,
           coalesce(ree.ts, case when v.status in ('refunded', 'chargeback', 'chargedback') then v.invoice_modified_at end) ts,
           coalesce(v.seller_net_cents, 0) / 100.0 liquido,
           public.cic_vendedor_de_utm(v.utm_source) vendedor_slug
    from public.hubla_vendas v
    left join ree on ree.invoice_id = v.invoice_id
    where v.status in ('paid', 'refunded', 'chargeback', 'chargedback')
      and v.sale_date is not null
      and (ree.invoice_id is not null or v.status in ('refunded', 'chargeback', 'chargedback'))
  )
  select r.invoice_id, (r.ts at time zone 'America/Sao_Paulo')::date, r.liquido, r.vendedor_slug
  from r
  where r.ts is not null
    and (r.ts at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim
$$;

revoke execute on function public.cic_vendas_validas(date, date),
                           public.cic_reembolsos_validos(date, date)
  from public, anon, authenticated;

-- 4. Home só com o comercial (decidido em 05/11): orgânico e reembolso de
--    orgânico ficam no banco (listas e análise), fora do dash.
create or replace function public.cic_home(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  with v as (select * from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null),
       r as (select * from public.cic_reembolsos_validos(p_inicio, p_fim) x where x.vendedor_slug is not null),
       dias as (select generate_series(p_inicio, p_fim, interval '1 day')::date dia),
       ct as (select x.contatos from public.cic_contatos_em_contato(p_inicio, p_fim) x where x.total_time)
  select jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim,
    'serie', (
      select jsonb_agg(jsonb_build_object(
               'dia', d.dia,
               'vendas_qtd', (select count(*) from v where v.dia = d.dia),
               'liquido',    (select coalesce(round(sum(v.liquido), 2), 0) from v where v.dia = d.dia),
               'bruto',      (select coalesce(round(sum(v.bruto), 2), 0) from v where v.dia = d.dia),
               'reembolsos_qtd', (select count(*) from r where r.dia = d.dia),
               'reembolsos',     (select coalesce(round(sum(r.liquido), 2), 0) from r where r.dia = d.dia))
             order by d.dia)
      from dias d),
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object('produto', p.produto, 'vendas_qtd', p.q, 'liquido', p.l, 'bruto', p.b) order by p.l desc)
      from (select coalesce(v.produto, '(sem produto)') produto, count(*) q,
                   round(sum(v.liquido), 2) l, round(sum(v.bruto), 2) b
            from v group by 1) p), '[]'::jsonb),
    'conversao', jsonb_build_object(
      'vendas_comercial', (select count(*) from v),
      'contatos', coalesce((select ct.contatos from ct), 0),
      'taxa', (select case when ct.contatos > 0 then round((select count(*) from v)::numeric / ct.contatos, 4) end from ct),
      'alvo', coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15))
  ) into v_res;
  return v_res;
end $$;
