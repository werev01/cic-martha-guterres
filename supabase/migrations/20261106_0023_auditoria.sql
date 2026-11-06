-- =====================================================================
-- 0023 · Correções da auditoria de 06/11
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md ("Regras gerais de contagem", 06/11/2026)
--
-- Dias úteis: toda conta "por dia útil" (média de vendas por dia, projeções
--   da Meta do mês e da Minha página, reta da meta no burn-up) conta dias
--   úteis a partir da 1ª venda comercial do mês. Helpers cic_inicio_util e
--   cic_conta_dia_util.
-- Vendedor inativo com atividade no período (evento de CRM, conversa ou
--   venda) entra no Desempenho; Desempenho, Motivos e Ciclo devolvem
--   vendedor_ativo para a tela pôr a etiqueta "inativo".
-- Ganho/perda repetido: nada muda. Perda já é contada por negócio
--   (cic_negocios: lost_ts = evento lost mais antigo, motivo do mais antigo)
--   e ganho é sempre a venda na Hubla; nenhuma função conta status won.
-- =====================================================================

-- 1ª venda comercial do mês (null se ainda não houve)
create or replace function public.cic_inicio_util(p_mes date)
returns date
language sql stable security definer set search_path = '' as $$
  select min(x.dia)
  from public.cic_vendas_validas(date_trunc('month', p_mes)::date, (date_trunc('month', p_mes) + interval '1 month - 1 day')::date) x
  where x.vendedor_slug is not null
$$;

-- o dia conta como dia útil? (útil e a partir da 1ª venda comercial do mês dele)
create or replace function public.cic_conta_dia_util(p_dia date)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select d.dia_util from public.dim_calendario d where d.data = p_dia), false)
     and p_dia >= coalesce(public.cic_inicio_util(p_dia), 'infinity'::date)
$$;
revoke execute on function public.cic_inicio_util(date), public.cic_conta_dia_util(date) from public, anon, authenticated;

-- Desempenho: dias úteis pela regra nova e vendedor inativo com atividade
drop function if exists public.cic_desempenho(date, date, text);
create function public.cic_desempenho(p_inicio date, p_fim date, p_vendedor text default null)
returns table (
  vendedor_slug text, vendedor_nome text, vendedor_ativo boolean,
  vendas_qtd bigint, liquido numeric, ticket numeric, media_dia numeric, dias_uteis int,
  mes_liquido numeric, nivel smallint, nivel_nome text, pct numeric, comissao numeric,
  entradas_0 bigint, entradas_1 bigint, entradas_2 bigint, entradas_3 bigint, entradas_4 bigint,
  perdas_comerciais bigint, contatos bigint, conversao numeric, conversao_alvo numeric,
  lrt_mediana numeric, lrt_n bigint, lrt_mais24 bigint,
  msgs_vendedor bigint, tpl_vendedor bigint
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  v_du  int;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  -- dias úteis decorridos no período (até hoje), a partir da 1ª venda comercial de cada mês
  select count(*) filter (where public.cic_conta_dia_util(d.data)) into v_du from public.dim_calendario d
  where d.data between p_inicio and least(p_fim, (now() at time zone 'America/Sao_Paulo')::date);
  return query
  with neg as (select * from public.cic_negocios()),
  v as (select x.vendedor_slug, count(*) q, sum(x.liquido) l
        from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null group by 1),
  -- ativo ou inativo com atividade no período (evento de CRM, conversa ou venda)
  vd as (select x.utm_slug, x.nome, x.ativo from public.vendedores x
         where (p_vendedor is null or p_vendedor = '' or x.utm_slug = p_vendedor)
           and (x.ativo
                or exists (select 1 from public.unnichat_eventos e where e.proprietario = x.nome and e.event_ts >= v_ini and e.event_ts < v_fim)
                or exists (select 1 from public.unnichat_conversas_dia c where c.vendedor = x.nome and c.dia between p_inicio and p_fim
                             and coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0) + coalesce(c.tpl_vendedor_utl, 0) + coalesce(c.tpl_vendedor_mkt, 0) > 0)
                or exists (select 1 from v where v.vendedor_slug = x.utm_slug))),
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
  lrt as (select l.vendedor_slug, percentile_cont(0.5) within group (order by l.minutos) med, count(*) n,
                 count(*) filter (where l.minutos > 1440) m24
          from public.cic_lrt(p_inicio, p_fim) l where l.vendedor_slug is not null group by 1),
  alvo as (select coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15) a)
  select vd.utm_slug, vd.nome, vd.ativo,
         coalesce(v.q, 0)::bigint, round(coalesce(v.l, 0), 2),
         case when coalesce(v.q, 0) > 0 then round(v.l / v.q, 2) end,
         case when v_du > 0 then round(coalesce(v.q, 0)::numeric / v_du, 2) end, v_du,
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
         round(lrt.med::numeric, 1), coalesce(lrt.n, 0)::bigint, coalesce(lrt.m24, 0)::bigint,
         coalesce(cv.m, 0)::bigint, coalesce(cv.t, 0)::bigint
  from vd
  cross join alvo
  left join v on v.vendedor_slug = vd.utm_slug
  left join mes on mes.vendedor_slug = vd.utm_slug
  left join per on per.vendedor_slug = vd.utm_slug
  left join ct on ct.vendedor_slug = vd.utm_slug
  left join cv on cv.vendedor = vd.nome
  left join lrt on lrt.vendedor_slug = vd.utm_slug
  order by coalesce(v.l, 0) desc, vd.nome;
end $$;
revoke execute on function public.cic_desempenho(date, date, text) from public, anon;
grant execute on function public.cic_desempenho(date, date, text) to authenticated;

-- Minha página: dias úteis pela regra nova (projeção, vendas por dia e tendência)
create or replace function public.cic_minha_pagina(p_mes date, p_vendedor text default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini   date := date_trunc('month', p_mes)::date;
  v_fim   date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_corte date;
  v_slug  text;
  v_cfg   jsonb;
  v_res   jsonb;
begin
  v_slug := case when public.cic_eh_admin() then coalesce(nullif(p_vendedor, ''), public.cic_meu_vendedor()) else public.cic_meu_vendedor() end;
  if v_slug is null then raise exception 'sem vendedor' using errcode = '42501'; end if;
  v_corte := least(v_fim, v_hoje);
  v_cfg := coalesce((select c.valor from public.cic_config c where c.chave = 'insights'), '{}'::jsonb);
  with
  cal as (select d.data dia, d.dia_util from public.dim_calendario d where d.data between v_ini and v_fim),
  du as (select count(*) filter (where public.cic_conta_dia_util(cal.dia)) mes,
                count(*) filter (where public.cic_conta_dia_util(cal.dia) and cal.dia <= v_corte) dec from cal),
  vd as (select x.dia, count(*) q, sum(x.liquido) l from public.cic_vendas_validas(v_ini, v_fim) x where x.vendedor_slug = v_slug group by 1),
  rd as (select x.dia, sum(x.liquido) l from public.cic_reembolsos_validos(v_ini, v_fim) x where x.vendedor_slug = v_slug group by 1),
  burn as (
    select cal.dia, case when cal.dia <= v_corte then
             round(sum(coalesce(vd.l, 0) - coalesce(rd.l, 0)) over (order by cal.dia), 2) end acum
    from cal left join vd on vd.dia = cal.dia left join rd on rd.dia = cal.dia
  ),
  mes as (select * from public.cic_vendedor_mes(v_ini) m where m.vendedor_slug = v_slug),
  fx as (
    select f.nivel, f.nome, f.acima_de, f.pct from public.comissao_faixas f
    where f.vigencia_inicio = (select max(f2.vigencia_inicio) from public.comissao_faixas f2 where f2.vigencia_inicio <= v_ini)
  ),
  -- mês anterior cortado no mesmo dia (tendência)
  ant as (
    select (v_ini - interval '1 month')::date ini,
           least((v_ini - interval '1 month' + greatest(v_corte - v_ini, 0) * interval '1 day')::date, (v_ini - 1)) fim
  ),
  ant_v as (select count(*) q, sum(x.liquido) l from ant, public.cic_vendas_validas(ant.ini, ant.fim) x where x.vendedor_slug = v_slug),
  ant_c as (select x.contatos from ant, public.cic_contatos_em_contato(ant.ini, ant.fim) x where x.vendedor_slug = v_slug and not x.total_time),
  ant_du as (select count(*) filter (where public.cic_conta_dia_util(d.data)) n from ant, public.dim_calendario d where d.data between ant.ini and ant.fim)
  select jsonb_build_object(
    'mes', v_ini, 'hoje', v_hoje, 'vendedor_slug', v_slug,
    'vendedor_nome', (select m.vendedor_nome from mes m),
    'liquido_final', (select m.liquido_final from mes m),
    'vendas_qtd', (select m.vendas_qtd from mes m), 'vendas_liquido', (select m.vendas_liquido from mes m),
    'contatos', (select m.contatos from mes m), 'conversao', (select m.conversao from mes m),
    'ticket', (select case when m.vendas_qtd > 0 then round(m.vendas_liquido / m.vendas_qtd, 2) end from mes m),
    'nivel', (select m.nivel from mes m), 'proximo_nivel', (select m.proximo_nivel from mes m),
    'proximo_nome', (select m.proximo_nome from mes m), 'proximo_pct', (select m.proximo_pct from mes m),
    'falta_proximo', (select m.falta_proximo from mes m),
    'proximo_limite', (select f.acima_de from fx f join mes m on f.nivel = m.proximo_nivel),
    'dias_uteis_mes', (select du.mes from du), 'dias_uteis_dec', (select du.dec from du),
    'vendas_dia', (select case when du.dec > 0 then round(m.vendas_qtd::numeric / du.dec, 2) end from du, mes m),
    'projecao', (select case when du.dec > 0 and v_corte < v_fim then round(m.liquido_final / du.dec * du.mes, 2) end from du, mes m),
    'niveis', coalesce((select jsonb_agg(jsonb_build_object('nivel', f.nivel, 'nome', f.nome, 'acima_de', f.acima_de, 'pct', f.pct) order by f.acima_de) from fx f), '[]'::jsonb),
    'burn', coalesce((select jsonb_agg(jsonb_build_object('dia', b.dia, 'acum', b.acum) order by b.dia) from burn b), '[]'::jsonb),
    'alvos', v_cfg || jsonb_build_object('conversao_alvo',
               coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15)),
    'tendencia', case when v_ini >= coalesce((v_cfg ->> 'tendencia_desde')::date, '2999-01-01'::date) then
      (select jsonb_build_object('inicio', ant.ini, 'fim', ant.fim, 'vendas', ant_v.q,
              'ticket', case when ant_v.q > 0 then round(ant_v.l / ant_v.q, 2) end,
              'conversao', case when coalesce((select ant_c.contatos from ant_c), 0) > 0 then round(ant_v.q::numeric / (select ant_c.contatos from ant_c), 4) end,
              'vendas_dia', case when ant_du.n > 0 then round(ant_v.q::numeric / ant_du.n, 2) end)
       from ant, ant_v, ant_du) end
  ) into v_res;
  return v_res;
end $$;
revoke execute on function public.cic_minha_pagina(date, text) from public, anon;
grant execute on function public.cic_minha_pagina(date, text) to authenticated;

-- Meta do mês (burn-up): reta das metas distribuída a partir da 1ª venda comercial
create or replace function public.cic_meta_funil(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini  date := date_trunc('month', p_mes)::date;
  v_fim  date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_base date;
  v_res  jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  -- meta distribuída a partir da 1ª venda comercial do mês (sem venda ainda: o mês inteiro)
  v_base := coalesce(public.cic_inicio_util(v_ini), v_ini);

  with
  cal as (
    select d.data dia, d.dia_util, d.feriado,
           count(*) filter (where d.dia_util and d.data >= v_base) over (order by d.data) du_acum,
           count(*) filter (where d.dia_util and d.data >= v_base) over () du_mes
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

-- Meta do mês: projeção e dias úteis a partir da 1ª venda COMERCIAL do mês
-- (antes contava a 1ª venda de qualquer origem). dias_uteis_mes passa a ser
-- a janela (da 1ª venda ao fim do mês).
create or replace function public.cic_meta_mes(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini date := date_trunc('month', p_mes)::date;
  v_fim date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_primeira date;
  v_liq numeric; v_vq bigint; v_rl numeric; v_rq bigint;
  v_du_mes int; v_du_decorr int; v_du_rest int;
  v_proj numeric;
  v_res jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  v_primeira := public.cic_inicio_util(v_ini);

  select count(*), coalesce(sum(x.liquido), 0) into v_vq, v_liq
  from public.cic_vendas_validas(v_ini, v_fim) x where x.vendedor_slug is not null;
  select count(*), coalesce(sum(x.liquido), 0) into v_rq, v_rl
  from public.cic_reembolsos_validos(v_ini, v_fim) x where x.vendedor_slug is not null;
  v_liq := v_liq - v_rl;

  -- sem venda comercial ainda no mês: a janela é o mês inteiro (projeção fica vazia)
  select count(*) filter (where d.dia_util and d.data >= coalesce(v_primeira, v_ini)),
         count(*) filter (where public.cic_conta_dia_util(d.data) and d.data <= least(v_hoje, v_fim)),
         count(*) filter (where d.dia_util and d.data > v_hoje)
    into v_du_mes, v_du_decorr, v_du_rest
  from public.dim_calendario d where d.data between v_ini and v_fim;

  v_proj := case when v_du_decorr > 0 then round(v_liq / v_du_decorr * v_du_mes, 2) end;

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

-- Motivos de perda: devolve vendedor_ativo (etiqueta "inativo" na tela)
drop function if exists public.cic_motivos_perda(date, date, text);
create function public.cic_motivos_perda(p_inicio date, p_fim date, p_vendedor text default null)
returns table (tipo text, grupo text, motivo text, vendedor_slug text, vendedor_nome text, vendedor_ativo boolean, etapa_ordem integer, etapa text, qtd bigint)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then raise exception 'sem permissão' using errcode = '42501'; end if;
  return query
  select case when n.grupo = 'cs' then 'cs' else 'comercial' end, n.grupo, coalesce(n.motivo, 'Motivo não informado'),
         n.vendedor_slug, coalesce(vd.nome, 'Sem vendedor'), vd.ativo, n.perda_ordem, coalesce(c.rotulo, 'Sem etapa'), count(*)::bigint
  from public.cic_negocios() n
  left join public.vendedores vd on vd.utm_slug = n.vendedor_slug
  left join public.crm_etapas c on c.ordem = n.perda_ordem
  where n.lost_ts >= v_ini and n.lost_ts < v_fim
    and (p_vendedor is null or p_vendedor = '' or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor)
  group by 1, 2, 3, 4, 5, 6, 7, 8 order by 9 desc;
end $$;

-- Ciclo de venda: devolve vendedor_ativo
drop function if exists public.cic_ciclo_venda(date, date, text);
create function public.cic_ciclo_venda(p_inicio date, p_fim date, p_vendedor text default null)
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
  c as (
    select 'venda'::text t, neg.vendedor_slug vs, extract(epoch from neg.venda_ts - neg.entrada_ts) / 3600 h from neg where neg.venda_ts >= v_ini and neg.venda_ts < v_fim
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
           count(*) filter (where c.h < 0.1) sh
    from c group by c.t, rollup(c.vs)
  )
  select g.t, g.vs, case g.vs when '_time' then 'Time' when '_sem' then 'Sem vendedor' else vd.nome end, vd.ativo,
         g.casos::bigint, round(g.med::numeric, 1), round(g.med_a::numeric, 1), g.f1::bigint, g.f2::bigint, g.f3::bigint, g.f4::bigint, g.sh::bigint
  from g left join public.vendedores vd on vd.utm_slug = g.vs
  order by g.t desc, (g.vs = '_time') desc, g.casos desc;
end $$;

revoke execute on function public.cic_motivos_perda(date, date, text), public.cic_ciclo_venda(date, date, text) from public, anon;
grant execute on function public.cic_motivos_perda(date, date, text), public.cic_ciclo_venda(date, date, text) to authenticated;
