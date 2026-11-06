-- =====================================================================
-- 0020 · Meta do mês: burn-up e matriz por funil
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Meta do mês, 06/11/2026). Mapa: docs/banco.md
--
-- cic_meta_funil(p_mes), só admin, jsonb:
--  burn:   por dia do mês, metas acumuladas (meta ÷ dias úteis do mês × dias
--          úteis acumulados; plana em fim de semana e feriado) e realizado
--          acumulado (líquido de vendas − reembolsos do dia, só até hoje).
--  colunas: dias, semanas (segunda a domingo, cortadas no mês) e o mês, cada
--          uma com os números por funil e o TOTAL.
-- Funil = unnichat_eventos.origem (vazio = "Sem origem"). Lead e Em Contato
-- contam no funil do próprio evento (pessoas únicas pela chave do telefone).
-- Venda (só comercial) vai pro funil da origem do evento mais recente da
-- pessoa antes da venda; sem evento = "Sem funil". Crédito único por venda.
-- TOTAL: Leads = soma dos funis; Em Contato = pessoas únicas no geral.
-- =====================================================================

create or replace function public.cic_meta_funil(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini  date := date_trunc('month', p_mes)::date;
  v_fim  date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_res  jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  with
  cal as (
    select d.data dia, d.dia_util, d.feriado,
           count(*) filter (where d.dia_util) over (order by d.data) du_acum,
           count(*) filter (where d.dia_util) over () du_mes
    from public.dim_calendario d where d.data between v_ini and v_fim
  ),
  metas as (select m.nivel, m.valor from public.metas m where m.mes = v_ini),
  vd as (select x.dia, sum(x.liquido) l from public.cic_vendas_validas(v_ini, v_fim) x where x.vendedor_slug is not null group by 1),
  rd as (select x.dia, sum(x.liquido) l from public.cic_reembolsos_validos(v_ini, v_fim) x where x.vendedor_slug is not null group by 1),
  burn as (
    select cal.dia, cal.dia_util, cal.feriado,
           (select round(m.valor / nullif(cal.du_mes, 0) * cal.du_acum, 2) from metas m where m.nivel = 'bronze') bronze,
           (select round(m.valor / nullif(cal.du_mes, 0) * cal.du_acum, 2) from metas m where m.nivel = 'prata') prata,
           (select round(m.valor / nullif(cal.du_mes, 0) * cal.du_acum, 2) from metas m where m.nivel = 'ouro') ouro,
           case when cal.dia <= v_hoje then
             round(sum(coalesce(vd.l, 0) - coalesce(rd.l, 0)) over (order by cal.dia), 2) end realizado
    from cal left join vd on vd.dia = cal.dia left join rd on rd.dia = cal.dia
  ),
  -- eventos de etapa (lead e em contato) com funil e pessoa
  ev as (
    select (e.event_ts at time zone 'America/Sao_Paulo')::date dia, e.etapa_crm,
           coalesce(nullif(trim(e.origem), ''), 'Sem origem') funil,
           public.cic_fone_chave(e.telefone) pessoa
    from public.unnichat_eventos e
    where e.etapa_crm in ('0. Base/Entrada', '2. Em Contato')
      and e.event_ts >= (v_ini::timestamp at time zone 'America/Sao_Paulo')
      and e.event_ts <  ((v_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  ),
  -- vendas do comercial com o funil da origem mais recente antes da venda
  vf as (
    select x.dia, x.liquido,
           coalesce((select coalesce(nullif(trim(e.origem), ''), 'Sem origem')
                     from public.unnichat_eventos e
                     where public.cic_fone_chave(e.telefone) = public.cic_fone_chave(h.payer_telefone)
                       and e.event_ts <= h.sale_date
                     order by e.event_ts desc limit 1), 'Sem funil') funil
    from public.cic_vendas_validas(v_ini, v_fim) x
    join public.hubla_vendas h on h.invoice_id = x.invoice_id
    where x.vendedor_slug is not null
  ),
  -- colunas: dia, semana (segunda a domingo, cortada no mês) e mês
  cols as (
    select 'dia'::text tipo, cal.dia chave_ini, cal.dia chave_fim, to_char(cal.dia, 'DD') rotulo, cal.dia_util, cal.dia = v_hoje parcial, cal.dia > v_hoje futuro
    from cal
    union all
    select 'semana', greatest(date_trunc('week', cal.dia)::date, v_ini), least((date_trunc('week', cal.dia) + interval '6 days')::date, v_fim),
           null, null, null, null
    from cal group by date_trunc('week', cal.dia)
    union all
    select 'mes', v_ini, v_fim, 'MÊS', null, null, null
  ),
  funis as (
    select distinct funil from ev union select distinct funil from vf
  ),
  celula as (
    select c.tipo, c.chave_ini, c.chave_fim, f.funil,
           (select count(distinct ev.pessoa) from ev where ev.funil = f.funil and ev.etapa_crm = '0. Base/Entrada' and ev.dia between c.chave_ini and c.chave_fim) leads,
           (select count(distinct ev.pessoa) from ev where ev.funil = f.funil and ev.etapa_crm = '2. Em Contato' and ev.dia between c.chave_ini and c.chave_fim) em_contato,
           (select count(*) from vf where vf.funil = f.funil and vf.dia between c.chave_ini and c.chave_fim) vendas,
           (select coalesce(sum(vf.liquido), 0) from vf where vf.funil = f.funil and vf.dia between c.chave_ini and c.chave_fim) liquido
    from cols c cross join funis f
  ),
  col_json as (
    select c.tipo, c.chave_ini, c.chave_fim,
           jsonb_build_object(
             'tipo', c.tipo, 'inicio', c.chave_ini, 'fim', c.chave_fim,
             'rotulo', coalesce(c.rotulo, to_char(c.chave_ini, 'DD') || '–' || to_char(c.chave_fim, 'DD')),
             'util', c.dia_util, 'parcial', c.parcial,
             'futuro', coalesce(c.futuro, c.chave_ini > v_hoje),
             'funis', (select jsonb_object_agg(ce.funil, jsonb_build_object(
                          'leads', ce.leads, 'em_contato', ce.em_contato, 'vendas', ce.vendas, 'liquido', round(ce.liquido, 2),
                          'conversao', case when ce.em_contato > 0 then least(1, round(ce.vendas::numeric / ce.em_contato, 4)) end,
                          'ticket', case when ce.vendas > 0 then round(ce.liquido / ce.vendas, 2) end))
                       from celula ce where ce.tipo = c.tipo and ce.chave_ini = c.chave_ini and ce.chave_fim = c.chave_fim),
             'total', (select jsonb_build_object(
                          'leads', sum(ce.leads),
                          'em_contato', (select count(distinct ev.pessoa) from ev where ev.etapa_crm = '2. Em Contato' and ev.dia between c.chave_ini and c.chave_fim),
                          'vendas', sum(ce.vendas), 'liquido', round(sum(ce.liquido), 2))
                       from celula ce where ce.tipo = c.tipo and ce.chave_ini = c.chave_ini and ce.chave_fim = c.chave_fim)
           ) j
    from cols c
  )
  select jsonb_build_object(
    'mes', v_ini, 'hoje', v_hoje,
    'metas', coalesce((select jsonb_object_agg(m.nivel, m.valor) from metas m), '{}'::jsonb),
    'burn', coalesce((select jsonb_agg(jsonb_build_object('dia', b.dia, 'util', b.dia_util, 'feriado', b.feriado,
                         'bronze', b.bronze, 'prata', b.prata, 'ouro', b.ouro, 'realizado', b.realizado) order by b.dia) from burn b), '[]'::jsonb),
    'funis', coalesce((select jsonb_agg(f.funil order by (f.funil in ('Sem origem', 'Sem funil')), f.funil) from funis f), '[]'::jsonb),
    'colunas', coalesce((select jsonb_agg(
                   cj.j || jsonb_build_object('total', (cj.j -> 'total') || jsonb_build_object(
                     'conversao', case when (cj.j -> 'total' ->> 'em_contato')::int > 0
                                       then least(1, round((cj.j -> 'total' ->> 'vendas')::numeric / (cj.j -> 'total' ->> 'em_contato')::int, 4)) end,
                     'ticket', case when (cj.j -> 'total' ->> 'vendas')::int > 0
                                    then round((cj.j -> 'total' ->> 'liquido')::numeric / (cj.j -> 'total' ->> 'vendas')::int, 2) end))
                   order by case when cj.tipo = 'dia' then cj.chave_ini else cj.chave_fim end,
                            case cj.tipo when 'dia' then 0 when 'semana' then 1 else 2 end)
                 from col_json cj), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

revoke execute on function public.cic_meta_funil(date) from public, anon;
grant execute on function public.cic_meta_funil(date) to authenticated;
