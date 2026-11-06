-- =====================================================================
-- 0022 · Desempenho individual refeito e Minha página com burn e insights
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Desempenho individual e Minha página, 06/11/2026)
--
-- 1. cic_config 'insights': alvos dos insights da Minha página (ticket,
--    distância pro próximo nível, queda da tendência e mês em que a
--    tendência começa). Conversão alvo continua em 'conversao_alvo'.
-- 2. cic_desempenho (só admin) ganha LRT, ticket, média de vendas por dia
--    útil e dias úteis decorridos. Muda o retorno, então drop + create.
--    LRT = minutos entre a última entrada em etapa anterior (ordem < 2) e a
--    primeira entrada em "2. Em Contato" do mesmo negócio, com a entrada em
--    Em Contato no período. Crédito pro proprietario do evento de Em Contato
--    (sem proprietario, o dono do negócio). Negativo ou sem etapa anterior
--    fica de fora. Mediana por vendedor; conta quantos passaram de 24 h.
-- 3. cic_minha_pagina(p_mes, p_vendedor): vendedor vê só o próprio (o
--    parâmetro é ignorado); admin escolhe. jsonb com burn (líquido acumulado
--    por dia, vendas − reembolsos, só até hoje), projeção pelo ritmo de dia
--    útil, níveis, números dos insights e mês anterior cortado no mesmo dia.
-- =====================================================================

insert into public.cic_config (chave, valor, descricao) values
  ('insights', '{"ticket_alvo": 700, "proximo_nivel_pct": 0.15, "queda_tendencia": 0.10, "tendencia_desde": "2026-12-01"}'::jsonb,
   'Insights da Minha página: ticket líquido alvo, distância máxima (fração do próximo nível) pra avisar, queda mínima pra tendência e mês em que a tendência começa')
on conflict (chave) do update set valor = excluded.valor, descricao = excluded.descricao, atualizado_em = now();

-- LRT por negócio (interna, sem grant)
create or replace function public.cic_lrt(p_inicio date, p_fim date)
returns table (negocio_id text, vendedor_slug text, minutos numeric)
language sql stable security definer set search_path = '' as $$
  with ev as (
    select e.negocio_id, e.event_ts, e.proprietario, c.ordem
    from public.unnichat_eventos e join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
    where e.negocio_id is not null
  ),
  e2 as (
    select distinct on (ev.negocio_id) ev.negocio_id, ev.event_ts ts2, ev.proprietario
    from ev where ev.ordem = 2 order by ev.negocio_id, ev.event_ts
  ),
  par as (
    select e2.negocio_id, e2.ts2, e2.proprietario,
           (select max(a.event_ts) from ev a where a.negocio_id = e2.negocio_id and a.ordem < 2 and a.event_ts <= e2.ts2) ts_ant
    from e2
    where e2.ts2 >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
      and e2.ts2 <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select par.negocio_id, coalesce(vd.utm_slug, n.vendedor_slug),
         round(extract(epoch from par.ts2 - par.ts_ant)::numeric / 60, 2)
  from par
  left join public.vendedores vd on vd.nome = par.proprietario
  left join public.cic_negocios() n on n.negocio_id = par.negocio_id and par.proprietario is null
  where par.ts_ant is not null and par.ts2 >= par.ts_ant
$$;
revoke execute on function public.cic_lrt(date, date) from public, anon, authenticated;

drop function if exists public.cic_desempenho(date, date, text);
create function public.cic_desempenho(p_inicio date, p_fim date, p_vendedor text default null)
returns table (
  vendedor_slug text, vendedor_nome text,
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
  -- dias úteis decorridos no período (até hoje)
  select count(*) filter (where d.dia_util) into v_du from public.dim_calendario d
  where d.data between p_inicio and least(p_fim, (now() at time zone 'America/Sao_Paulo')::date);
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
  lrt as (select l.vendedor_slug, percentile_cont(0.5) within group (order by l.minutos) med, count(*) n,
                 count(*) filter (where l.minutos > 1440) m24
          from public.cic_lrt(p_inicio, p_fim) l where l.vendedor_slug is not null group by 1),
  alvo as (select coalesce((select (cf.valor ->> 'pct')::numeric from public.cic_config cf where cf.chave = 'conversao_alvo'), 0.15) a)
  select vd.utm_slug, vd.nome,
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
  du as (select count(*) filter (where cal.dia_util) mes, count(*) filter (where cal.dia_util and cal.dia <= v_corte) dec from cal),
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
  ant_du as (select count(*) filter (where d.dia_util) n from ant, public.dim_calendario d where d.data between ant.ini and ant.fim)
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
