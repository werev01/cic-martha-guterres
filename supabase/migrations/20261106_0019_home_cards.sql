-- =====================================================================
-- 0019 · Home: cards (período, hoje, ontem), venda por produto e dia a dia
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Home, 06/11/2026). Mapa: docs/banco.md
--
-- Só comercial. Venda válida = foi paga um dia (0013), no dia do pagamento
-- em SP; reembolso abate no dia do reembolso. Pessoa = telefone pela chave
-- DDI + DDD + últimos 8 dígitos (cic_fone_chave). Leads = pessoas únicas que
-- entraram em "0. Base/Entrada"; Em Contato = em "2. Em Contato".
-- Conversão = vendas ÷ Em Contato, limitada a 100%.
-- Também passa cic_contatos_em_contato pra mesma chave de pessoa (conversão
-- da Minha página, Meta do mês e Desempenho igual à da Home).
-- =====================================================================

-- Em Contato por pessoa (chave do telefone)
create or replace function public.cic_contatos_em_contato(p_inicio date, p_fim date)
returns table (vendedor_slug text, contatos bigint, total_time boolean)
language sql stable security definer set search_path = '' as $$
  with e as (
    select public.cic_fone_chave(e.telefone) pessoa, vd.utm_slug
    from public.unnichat_eventos e
    left join public.vendedores vd on vd.nome = e.proprietario
    where e.etapa_crm = '2. Em Contato'
      and e.event_ts >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
      and e.event_ts <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select utm_slug, count(distinct pessoa), false from e where utm_slug is not null group by utm_slug
  union all
  select null, count(distinct pessoa), true from e
$$;

-- Indicadores do comercial num intervalo (interna)
create or replace function public.cic_kpis_comercial(p_inicio date, p_fim date)
returns jsonb
language sql stable security definer set search_path = '' as $$
  with v as (select * from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null),
  r as (select * from public.cic_reembolsos_validos(p_inicio, p_fim) x where x.vendedor_slug is not null),
  p as (
    select count(distinct public.cic_fone_chave(e.telefone)) filter (where e.etapa_crm = '0. Base/Entrada') leads,
           count(distinct public.cic_fone_chave(e.telefone)) filter (where e.etapa_crm = '2. Em Contato') em_contato
    from public.unnichat_eventos e
    where e.etapa_crm in ('0. Base/Entrada', '2. Em Contato')
      and e.event_ts >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
      and e.event_ts <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  ),
  t as (
    select (select count(*) from v) vendas,
           (select coalesce(sum(v.bruto), 0) from v) bruto,
           (select coalesce(sum(v.liquido), 0) from v) liquido,
           (select count(*) from r) reemb_q,
           (select coalesce(sum(r.liquido), 0) from r) reemb
  )
  select jsonb_build_object(
    'vendas', t.vendas, 'bruto', round(t.bruto, 2), 'liquido', round(t.liquido, 2),
    'reembolso', round(t.reemb, 2), 'reembolso_qtd', t.reemb_q, 'liquido_apos_reembolso', round(t.liquido - t.reemb, 2),
    'ticket_bruto', case when t.vendas > 0 then round(t.bruto / t.vendas, 2) end,
    'ticket_liquido', case when t.vendas > 0 then round(t.liquido / t.vendas, 2) end,
    'leads', p.leads, 'em_contato', p.em_contato,
    'conversao', case when p.em_contato > 0 then least(1, round(t.vendas::numeric / p.em_contato, 4)) end)
  from t, p
$$;

revoke execute on function public.cic_kpis_comercial(date, date) from public, anon, authenticated;

-- Home (só admin)
create or replace function public.cic_home(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_mes_ini date := date_trunc('month', p_fim)::date;
  v_mes_fim date := least((date_trunc('month', p_fim) + interval '1 month - 1 day')::date, v_hoje);
  v_res jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  with v as (
    select x.*, h.offer_name oferta
    from public.cic_vendas_validas(p_inicio, p_fim) x
    join public.hubla_vendas h on h.invoice_id = x.invoice_id
    where x.vendedor_slug is not null
  ),
  tot as (select count(*) q, coalesce(sum(v.liquido), 0) l from v),
  prod as (
    select coalesce(v.produto, '(sem produto)') produto, count(*) q, sum(v.bruto) b, sum(v.liquido) l from v group by 1
  ),
  ofe as (
    select coalesce(v.produto, '(sem produto)') produto, coalesce(v.oferta, '(sem oferta)') oferta,
           count(*) q, sum(v.bruto) b, sum(v.liquido) l from v group by 1, 2
  ),
  dias as (
    select d.data, d.dia_util, d.feriado from public.dim_calendario d
    where d.data between v_mes_ini and v_mes_fim
  )
  select jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim, 'hoje', v_hoje,
    'periodo', public.cic_kpis_comercial(p_inicio, p_fim),
    'dia_hoje', public.cic_kpis_comercial(v_hoje, v_hoje),
    'dia_ontem', public.cic_kpis_comercial(v_hoje - 1, v_hoje - 1),
    -- pronto pra outras plataformas (TMB entra depois)
    'plataformas', jsonb_build_array(jsonb_build_object(
        'plataforma', 'Hubla',
        'vendas', (select count(*) from v),
        'bruto', (select round(coalesce(sum(v.bruto), 0), 2) from v),
        'liquido', (select round(coalesce(sum(v.liquido), 0), 2) from v))),
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'produto', prod.produto, 'vendas', prod.q,
               'pct_vendas', case when tot.q > 0 then round(prod.q::numeric / tot.q, 4) end,
               'liquido', round(prod.l, 2),
               'pct_liquido', case when tot.l > 0 then round(prod.l / tot.l, 4) end,
               'ticket_bruto', round(prod.b / prod.q, 2), 'ticket_liquido', round(prod.l / prod.q, 2),
               'ofertas', (select jsonb_agg(jsonb_build_object(
                              'oferta', ofe.oferta, 'vendas', ofe.q,
                              'pct_vendas', case when tot.q > 0 then round(ofe.q::numeric / tot.q, 4) end,
                              'liquido', round(ofe.l, 2),
                              'pct_liquido', case when tot.l > 0 then round(ofe.l / tot.l, 4) end,
                              'ticket_bruto', round(ofe.b / ofe.q, 2), 'ticket_liquido', round(ofe.l / ofe.q, 2))
                            order by ofe.l desc)
                           from ofe where ofe.produto = prod.produto))
             order by prod.l desc)
      from prod, tot), '[]'::jsonb),
    'matriz', jsonb_build_object(
      'mes', v_mes_ini,
      'dias', coalesce((
        select jsonb_agg(public.cic_kpis_comercial(dias.data, dias.data)
                         || jsonb_build_object('dia', dias.data, 'util', dias.dia_util, 'feriado', dias.feriado,
                                               'parcial', dias.data = v_hoje)
                         order by dias.data)
        from dias), '[]'::jsonb),
      'total', public.cic_kpis_comercial(v_mes_ini, v_mes_fim))
  ) into v_res;
  return v_res;
end $$;

revoke execute on function public.cic_home(date, date) from public, anon;
grant execute on function public.cic_home(date, date) to authenticated;
