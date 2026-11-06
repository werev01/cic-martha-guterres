-- =====================================================================
-- 0025 · Performance das funções do CIC (nenhum número muda)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Mapa: docs/banco.md (0025, colunas geradas e regra de recálculo)
--
-- Causa (06/11): subconsultas correlacionadas varrendo CTEs inteiras por
-- linha, recalculando cic_fone_chave() e regexp a cada comparação
-- (cic_mensageria 12 s, cic_desempenho 6,4 s, cic_negocios 2,7 s).
-- Mudança: colunas geradas pessoa_chave/copy_familia + índices; agregação
-- numa passada em cic_negocios e cic_lrt; lateral com índice em
-- cic_mensageria e cic_meta_funil; 1ª venda do mês calculada uma vez
-- (cic_desempenho, cic_minha_pagina, cic_meta_mes).
-- Aceite: saída de todas as RPCs igual à de antes (tmp_claude.c20_snap_*).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Colunas geradas e índices
--    Se cic_fone_chave mudar, as colunas pessoa_chave NÃO se recalculam
--    sozinhas: rodar "update <tabela> set telefone = telefone" (ou recriar a
--    coluna) nas três tabelas. Idem copy_familia se a regra de família mudar.
-- ---------------------------------------------------------------------
alter table public.unnichat_eventos
  add column if not exists pessoa_chave text generated always as (public.cic_fone_chave(telefone)) stored,
  add column if not exists copy_familia text generated always as (regexp_replace(codigo_copy, '_\d+(\.\d+)*$', '')) stored;
alter table public.hubla_vendas
  add column if not exists pessoa_chave text generated always as (public.cic_fone_chave(payer_telefone)) stored;
alter table public.unnichat_blocklist
  add column if not exists pessoa_chave text generated always as (public.cic_fone_chave(telefone)) stored;

create index if not exists unnichat_eventos_pessoa_ts_idx on public.unnichat_eventos (pessoa_chave, event_ts);
create index if not exists unnichat_eventos_negocio_ts_idx on public.unnichat_eventos (negocio_id, event_ts);
create index if not exists hubla_vendas_pessoa_sale_idx on public.hubla_vendas (pessoa_chave, sale_date);
create index if not exists unnichat_blocklist_pessoa_idx on public.unnichat_blocklist (pessoa_chave);
-- (codigo_copy) já existe: unnichat_eventos_codigo_copy_idx

-- ---------------------------------------------------------------------
-- 2. cic_negocios sem subconsulta correlacionada
--    Mesma regra da 0015: entrada = 1º evento; perda = 1º lost (motivo dele);
--    etapa da perda = última etapa até a perda; dono = último proprietario do
--    negócio, senão o último proprietario da pessoa (8 dígitos finais da
--    chave); venda = 1ª venda paga da pessoa a partir da entrada.
-- ---------------------------------------------------------------------
create or replace function public.cic_negocios()
returns table (negocio_id text, entrada_ts timestamptz, lost_ts timestamptz, max_ordem integer, vendedor_slug text,
               motivo text, grupo text, perda_ordem integer, venda_ts timestamptz)
language sql stable security definer set search_path = '' as $$
  with ev as (
    select e.negocio_id, e.event_ts, e.status, e.proprietario, e.motivo_perda, c.ordem, e.pessoa_chave chave
    from public.unnichat_eventos e
    left join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
    where e.negocio_id is not null
  ),
  n as (
    select ev.negocio_id, min(ev.event_ts) entrada_ts,
           min(ev.event_ts) filter (where ev.status = 'lost') lost_ts,
           max(ev.ordem) max_ordem,
           (array_agg(ev.chave order by ev.event_ts desc) filter (where ev.chave is not null))[1] chave,
           (array_agg(ev.proprietario order by ev.event_ts desc) filter (where ev.proprietario is not null))[1] prop,
           (array_agg(ev.motivo_perda order by ev.event_ts) filter (where ev.status = 'lost'))[1] motivo
    from ev group by ev.negocio_id
  ),
  -- último proprietario por pessoa (8 dígitos finais), uma passada
  p8 as (
    select right(ev.chave, 8) k8, (array_agg(ev.proprietario order by ev.event_ts desc))[1] prop
    from ev where ev.proprietario is not null and ev.chave is not null group by 1
  ),
  -- última etapa até a perda, uma passada
  pe as (
    select ev.negocio_id, (array_agg(ev.ordem order by ev.event_ts desc))[1] ordem
    from ev join n on n.negocio_id = ev.negocio_id
    where ev.ordem is not null and ev.event_ts <= n.lost_ts
    group by 1
  )
  select n.negocio_id, n.entrada_ts, n.lost_ts, n.max_ordem, vd.utm_slug, n.motivo,
         substring(n.motivo from '^\s*\[([^\]]+)\]'),
         pe.ordem,
         hv.venda_ts
  from n
  left join p8 on n.prop is null and p8.k8 = right(n.chave, 8)
  left join public.vendedores vd on vd.nome = coalesce(n.prop, p8.prop)
  left join pe on pe.negocio_id = n.negocio_id
  left join lateral (
    select min(v.sale_date) venda_ts from public.hubla_vendas v
    where v.pessoa_chave = n.chave and v.status in ('paid', 'refunded', 'chargeback', 'chargedback')
      and v.sale_date is not null and v.sale_date >= n.entrada_ts) hv on true
$$;

-- ---------------------------------------------------------------------
-- 3. cic_lrt sem subconsulta correlacionada
-- ---------------------------------------------------------------------
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
  e2p as (
    select e2.* from e2
    where e2.ts2 >= (p_inicio::timestamp at time zone 'America/Sao_Paulo')
      and e2.ts2 <  ((p_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  ),
  par as (
    select e2p.negocio_id, e2p.ts2, e2p.proprietario, max(a.event_ts) ts_ant
    from e2p join ev a on a.negocio_id = e2p.negocio_id and a.ordem < 2 and a.event_ts <= e2p.ts2
    group by 1, 2, 3
  ),
  sem_dono as (select n.negocio_id, n.vendedor_slug from public.cic_negocios() n
               where n.negocio_id in (select par.negocio_id from par where par.proprietario is null))
  select par.negocio_id, coalesce(vd.utm_slug, sd.vendedor_slug),
         round(extract(epoch from par.ts2 - par.ts_ant)::numeric / 60, 2)
  from par
  left join public.vendedores vd on vd.nome = par.proprietario
  left join sem_dono sd on sd.negocio_id = par.negocio_id and par.proprietario is null
  where par.ts2 >= par.ts_ant
$$;
revoke execute on function public.cic_lrt(date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. pessoa_chave no lugar de cic_fone_chave(telefone) linha a linha
-- ---------------------------------------------------------------------
create or replace function public.cic_contatos_em_contato(p_inicio date, p_fim date)
returns table (vendedor_slug text, contatos bigint, total_time boolean)
language sql stable security definer set search_path = '' as $$
  with e as (
    select e.pessoa_chave pessoa, vd.utm_slug
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

create or replace function public.cic_kpis_comercial(p_inicio date, p_fim date)
returns jsonb
language sql stable security definer set search_path = '' as $$
  with v as (select * from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null),
  r as (select * from public.cic_reembolsos_validos(p_inicio, p_fim) x where x.vendedor_slug is not null),
  p as (
    select count(distinct e.pessoa_chave) filter (where e.etapa_crm = '0. Base/Entrada') leads,
           count(distinct e.pessoa_chave) filter (where e.etapa_crm = '2. Em Contato') em_contato
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

-- ---------------------------------------------------------------------
-- 5. Funções que chamavam a 1ª venda por dia ou cic_fone_chave por linha
-- ---------------------------------------------------------------------
create or replace function public.cic_desempenho(p_inicio date, p_fim date, p_vendedor text default null)
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
  -- 1ª venda comercial calculada uma vez por mês do período (não por dia)
  with m as (select x.mes, public.cic_inicio_util(x.mes) ini
             from (select distinct date_trunc('month', d.data)::date mes from public.dim_calendario d where d.data between p_inicio and p_fim) x)
  select count(*) filter (where d.dia_util and d.data >= coalesce(m.ini, 'infinity'::date)) into v_du
  from public.dim_calendario d join m on m.mes = date_trunc('month', d.data)::date
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
  v_iu    date;
  v_iu_ant date;
  v_res   jsonb;
begin
  v_slug := case when public.cic_eh_admin() then coalesce(nullif(p_vendedor, ''), public.cic_meu_vendedor()) else public.cic_meu_vendedor() end;
  if v_slug is null then raise exception 'sem vendedor' using errcode = '42501'; end if;
  v_corte := least(v_fim, v_hoje);
  -- 1ª venda comercial do mês e do mês anterior, uma vez só (antes era por dia)
  v_iu := coalesce(public.cic_inicio_util(v_ini), 'infinity'::date);
  v_iu_ant := coalesce(public.cic_inicio_util((v_ini - interval '1 month')::date), 'infinity'::date);
  v_cfg := coalesce((select c.valor from public.cic_config c where c.chave = 'insights'), '{}'::jsonb);
  with
  cal as (select d.data dia, d.dia_util from public.dim_calendario d where d.data between v_ini and v_fim),
  du as (select count(*) filter (where cal.dia_util and cal.dia >= v_iu) mes,
                count(*) filter (where cal.dia_util and cal.dia >= v_iu and cal.dia <= v_corte) dec from cal),
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
  ant_du as (select count(*) filter (where d.dia_util and d.data >= v_iu_ant) n from ant, public.dim_calendario d where d.data between ant.ini and ant.fim)
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
           e.pessoa_chave pessoa
    from public.unnichat_eventos e
    where e.etapa_crm in ('0. Base/Entrada', '2. Em Contato')
      and e.event_ts >= (v_ini::timestamp at time zone 'America/Sao_Paulo')
      and e.event_ts <  ((v_fim + 1)::timestamp at time zone 'America/Sao_Paulo')
  ),
  -- vendas do comercial com o funil da origem mais recente antes da venda
  vf as (
    -- funil = origem do evento mais recente da pessoa antes da venda (índice pessoa_chave, event_ts)
    select x.dia, x.liquido, coalesce(u.funil, 'Sem funil') funil
    from public.cic_vendas_validas(v_ini, v_fim) x
    join public.hubla_vendas h on h.invoice_id = x.invoice_id
    left join lateral (
      select coalesce(nullif(trim(e.origem), ''), 'Sem origem') funil
      from public.unnichat_eventos e
      where e.pessoa_chave = h.pessoa_chave and e.event_ts <= h.sale_date
      order by e.event_ts desc limit 1) u on true
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
         count(*) filter (where d.dia_util and d.data >= coalesce(v_primeira, 'infinity'::date) and d.data <= least(v_hoje, v_fim)),
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

create or replace function public.cic_mensageria(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  v_res jsonb;
begin
  if not public.cic_eh_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;

  with
  -- ---------------- broadcasts ----------------
  bc as (
    select b.broadcast_id, b.nome, coalesce(b.started_at, b.send_at) ts,
           (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date dia,
           regexp_replace(regexp_replace(b.nome, '^(COMERCIAL_|\[COMERCIAL\]\s*)', '', 'i'), '_\d+_LT\d+$', '') campanha,
           b.contatos, b.tpl_enviados, b.tpl_entregues, b.tpl_lidos, b.tpl_falhas,
           b.srv_enviados, b.srv_entregues, t.nome template, t.categoria,
           b.tpl_entregues * coalesce(public.cic_preco_whatsapp(t.categoria, (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date), 0) custo_tpl,
           coalesce(b.srv_entregues, 0) * public.cic_preco_whatsapp('SERVICE', (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date) custo_srv
    from public.unnichat_broadcasts b
    left join public.unnichat_templates t on t.template_id = b.template_id
    where b.nome ilike 'COMERCIAL%' or b.nome ilike '[COMERCIAL]%'
  ),
  bcp as (select bc.*, bc.custo_tpl + bc.custo_srv custo from bc where bc.ts >= v_ini and bc.ts < v_fim),
  -- ---------------- automações (fotos acumuladas) ----------------
  fotos as (
    select m.automacao_id, m.node_id, m.automacao_nome, m.pasta, m.message_type,
           (array_agg(m.enviados  order by m.coletado_em desc) filter (where m.coletado_em >= v_ini))[1] env_fim,
           (array_agg(m.entregues order by m.coletado_em desc) filter (where m.coletado_em >= v_ini))[1] ent_fim,
           (array_agg(m.lidos     order by m.coletado_em desc) filter (where m.coletado_em >= v_ini))[1] lid_fim,
           (array_agg(m.falhas    order by m.coletado_em desc) filter (where m.coletado_em >= v_ini))[1] fal_fim,
           (array_agg((m.raw_payload -> 'clicks' ->> 'uniqueClicks')::int order by m.coletado_em desc) filter (where m.coletado_em >= v_ini))[1] cli_fim,
           (array_agg(m.enviados  order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] env_ini,
           (array_agg(m.entregues order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] ent_ini,
           (array_agg(m.lidos     order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] lid_ini,
           (array_agg(m.falhas    order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] fal_ini,
           (array_agg((m.raw_payload -> 'clicks' ->> 'uniqueClicks')::int order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] cli_ini,
           bool_or(m.raw_payload ? 'clicks') tem_botao
    from public.unnichat_automacoes_metricas m
    where m.node_id <> '_total' and m.coletado_em < v_fim
    group by 1, 2, 3, 4, 5
  ),
  au as (
    select f.automacao_id, f.automacao_nome, f.pasta, f.node_id, f.message_type,
           n.categoria_cobranca categoria,
           greatest(coalesce(f.env_fim, 0) - coalesce(f.env_ini, 0), 0) enviados,
           greatest(coalesce(f.ent_fim, 0) - coalesce(f.ent_ini, 0), 0) entregues,
           greatest(coalesce(f.lid_fim, 0) - coalesce(f.lid_ini, 0), 0) lidos,
           greatest(coalesce(f.fal_fim, 0) - coalesce(f.fal_ini, 0), 0) falhas,
           greatest(coalesce(f.cli_fim, 0) - coalesce(f.cli_ini, 0), 0) cliques,
           coalesce(f.tem_botao, false) tem_botao,
           (f.message_type = 'send_template') eh_template
    from fotos f
    left join public.unnichat_automacoes_nodes n on n.automacao_id = f.automacao_id and n.node_id = f.node_id
    where f.env_fim is not null
  ),
  au2 as (
    select au.*, au.entregues * coalesce(public.cic_preco_whatsapp(case when au.eh_template then au.categoria else 'SERVICE' end, p_fim), 0) custo from au
  ),
  -- automações por dia (última foto do dia - última do dia anterior)
  au_dia as (
    select x.dia, sum(x.q * coalesce(public.cic_preco_whatsapp(case when x.eh_template then x.categoria else 'SERVICE' end, x.dia), 0)) custo,
           sum(x.q) filter (where x.eh_template) tpl
    from (
      select d.dia, d.eh_template, d.categoria,
             greatest(d.entregues - coalesce(lag(d.entregues) over (partition by d.automacao_id, d.node_id order by d.dia), 0), 0) q
      from (
        select distinct on (m.automacao_id, m.node_id, (m.coletado_em at time zone 'America/Sao_Paulo')::date)
               m.automacao_id, m.node_id, (m.coletado_em at time zone 'America/Sao_Paulo')::date dia, m.entregues,
               (m.message_type = 'send_template') eh_template, n.categoria_cobranca categoria
        from public.unnichat_automacoes_metricas m
        left join public.unnichat_automacoes_nodes n on n.automacao_id = m.automacao_id and n.node_id = m.node_id
        where m.node_id <> '_total' and m.coletado_em < v_fim
        order by m.automacao_id, m.node_id, (m.coletado_em at time zone 'America/Sao_Paulo')::date, m.coletado_em desc
      ) d
    ) x
    where x.dia between p_inicio and p_fim
    group by 1
  ),
  -- ---------------- vendedores ----------------
  vd as (
    select v.utm_slug, v.nome, v.ativo,
           coalesce(sum(c.msg_vendedor), 0) msgs,
           coalesce(sum(c.tpl_vendedor_utl), 0) utl,
           coalesce(sum(c.tpl_vendedor_mkt), 0) mkt,
           count(distinct c.contact_id) filter (where c.msg_vendedor > 0) contatos,
           coalesce(sum(coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0)), 0) servico,
           coalesce(sum(coalesce(c.tpl_vendedor_utl, 0) * public.cic_preco_whatsapp('UTILITY', c.dia)
                      + coalesce(c.tpl_vendedor_mkt, 0) * public.cic_preco_whatsapp('MARKETING', c.dia)
                      + (coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0)) * public.cic_preco_whatsapp('SERVICE', c.dia)), 0) custo
    from public.vendedores v
    left join public.unnichat_conversas_dia c on c.vendedor = v.nome and c.dia between p_inicio and p_fim
    -- inativo entra quando teve conversa no período (o custo existe do mesmo jeito)
    where v.ativo
       or exists (select 1 from public.unnichat_conversas_dia c2 where c2.vendedor = v.nome and c2.dia between p_inicio and p_fim
                    and coalesce(c2.msg_vendedor, 0) + coalesce(c2.msg_agendada, 0) + coalesce(c2.tpl_vendedor_utl, 0) + coalesce(c2.tpl_vendedor_mkt, 0) > 0)
    group by 1, 2, 3
  ),
  vd_dia as (
    select c.dia,
           sum(coalesce(c.tpl_vendedor_utl, 0) * public.cic_preco_whatsapp('UTILITY', c.dia)
             + coalesce(c.tpl_vendedor_mkt, 0) * public.cic_preco_whatsapp('MARKETING', c.dia)
             + (coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0)) * public.cic_preco_whatsapp('SERVICE', c.dia)) custo,
           sum(coalesce(c.tpl_vendedor_utl, 0) + coalesce(c.tpl_vendedor_mkt, 0)) tpl
    from public.unnichat_conversas_dia c
    join public.vendedores v on v.nome = c.vendedor
    where c.dia between p_inicio and p_fim
    group by 1
  ),
  vendas as (select x.vendedor_slug, count(*) q from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null group by 1),
  -- ---------------- serviço e franquia (igual à 0016) ----------------
  sv_mes as (select * from public.cic_servico_dia(date_trunc('month', p_inicio)::date, p_fim)),
  sv as (select sv_mes.*, sv_mes.qtd * public.cic_preco_whatsapp('SERVICE', sv_mes.dia) custo from sv_mes where sv_mes.dia >= p_inicio),
  sv_dia as (
    select t.dia, t.q, sum(t.q) over (partition by date_trunc('month', t.dia) order by t.dia) acum
    from (select sv_mes.dia, sum(sv_mes.qtd) q from sv_mes group by 1) t
  ),
  franquia as (
    select coalesce(sum((least(1000, sv_dia.acum) - least(1000, sv_dia.acum - sv_dia.q)) * public.cic_preco_whatsapp('SERVICE', sv_dia.dia)), 0) desconto,
           coalesce(sum(least(1000, sv_dia.acum) - least(1000, sv_dia.acum - sv_dia.q)), 0) msgs
    from sv_dia where sv_dia.dia >= p_inicio
  ),
  -- ---------------- CRM: copy, vendas e bloqueios ----------------
  evc as (
    select e.codigo_copy, e.copy_familia, e.etapa_crm, e.event_ts, e.pessoa_chave pessoa
    from public.unnichat_eventos e where e.codigo_copy is not null and e.event_ts < v_fim
  ),
  -- último copy da pessoa antes da venda / do bloqueio (índice pessoa_chave, event_ts)
  vcopy as (
    select u.copy
    from public.cic_vendas_validas(p_inicio, p_fim) x
    join public.hubla_vendas h on h.invoice_id = x.invoice_id
    left join lateral (
      select e.codigo_copy copy from public.unnichat_eventos e
      where e.pessoa_chave = h.pessoa_chave and e.codigo_copy is not null and e.event_ts <= h.sale_date and e.event_ts < v_fim
      order by e.event_ts desc limit 1) u on true
    where x.vendedor_slug is not null
  ),
  bl as (
    select b.bloqueado_em, u.copy
    from public.unnichat_blocklist b
    left join lateral (
      select e.codigo_copy copy from public.unnichat_eventos e
      where e.pessoa_chave = b.pessoa_chave and e.codigo_copy is not null and e.event_ts <= b.bloqueado_em and e.event_ts < v_fim
      order by e.event_ts desc limit 1) u on true
    where b.bloqueado_em >= v_ini and b.bloqueado_em < v_fim
  ),
  -- KPIs de CRM agregados uma vez por copy exato (campanha) e por família, depois juntados pela chave
  kpi_c as (select evc.codigo_copy chave,
                   count(distinct evc.pessoa) filter (where evc.etapa_crm = '0. Base/Entrada') e0,
                   count(distinct evc.pessoa) filter (where evc.etapa_crm = '2. Em Contato') e2
            from evc where evc.event_ts >= v_ini group by 1),
  kpi_f as (select evc.copy_familia chave,
                   count(distinct evc.pessoa) filter (where evc.etapa_crm = '0. Base/Entrada') e0,
                   count(distinct evc.pessoa) filter (where evc.etapa_crm = '2. Em Contato') e2
            from evc where evc.event_ts >= v_ini group by 1),
  vcopy2 as (select vcopy.copy, regexp_replace(vcopy.copy, '_\d+(\.\d+)*$', '') familia from vcopy where vcopy.copy is not null),
  bl2 as (select bl.copy, regexp_replace(bl.copy, '_\d+(\.\d+)*$', '') familia from bl where bl.copy is not null),
  crm as (
    select k.chave, k.tipo,
           coalesce(case k.tipo when 'campanha' then kc.e0 else kf.e0 end, 0) e0,
           coalesce(case k.tipo when 'campanha' then kc.e2 else kf.e2 end, 0) e2,
           case k.tipo when 'campanha' then (select count(*) from vcopy2 where vcopy2.copy = k.chave)
                       else (select count(*) from vcopy2 where vcopy2.familia = k.chave) end vendas,
           case k.tipo when 'campanha' then (select count(*) from bl2 where bl2.copy = k.chave)
                       else (select count(*) from bl2 where bl2.familia = k.chave) end bloqueios
    from (
      select distinct bcp.campanha chave, 'campanha'::text tipo from bcp
      union
      select distinct evc.copy_familia, 'familia' from evc
      where evc.event_ts >= v_ini
        and evc.codigo_copy not in (select bc.campanha from bc)
    ) k
    left join kpi_c kc on k.tipo = 'campanha' and kc.chave = k.chave
    left join kpi_f kf on k.tipo = 'familia' and kf.chave = k.chave
  ),
  camp as (
    select bcp.campanha, count(*) n, sum(bcp.contatos) contatos, sum(bcp.tpl_entregues) entregues, sum(bcp.tpl_lidos) lidos,
           sum(bcp.tpl_falhas) falhas, sum(bcp.custo) custo, max(bcp.ts) ultimo
    from bcp group by 1
  ),
  -- ---------------- totais ----------------
  tot as (
    select coalesce((select sum(bcp.custo) from bcp), 0) c_bc,
           coalesce((select sum(au2.custo) from au2), 0) c_au,
           coalesce((select sum(vd.custo) from vd), 0) c_vd,
           (select franquia.desconto from franquia) desc_fr,
           (select franquia.msgs from franquia) msgs_fr,
           coalesce((select sum(sv.qtd) from sv), 0) srv_tot,
           coalesce((select sum(sv.custo) from sv), 0) c_srv,
           coalesce((select sum(vendas.q) from vendas), 0) vendas_com,
           coalesce((select sum(bcp.tpl_enviados) from bcp), 0) + coalesce((select sum(au2.enviados) from au2 where au2.eh_template), 0) env,
           coalesce((select sum(bcp.tpl_entregues) from bcp), 0) + coalesce((select sum(au2.entregues) from au2 where au2.eh_template), 0)
             + coalesce((select sum(vd.utl + vd.mkt) from vd), 0) ent,
           coalesce((select sum(bcp.tpl_lidos) from bcp), 0) + coalesce((select sum(au2.lidos) from au2 where au2.eh_template), 0) lid,
           coalesce((select sum(bcp.tpl_falhas) from bcp), 0) + coalesce((select sum(au2.falhas) from au2 where au2.eh_template), 0) fal,
           coalesce((select sum(au2.cliques) from au2 where au2.tem_botao), 0) cli,
           coalesce((select sum(au2.entregues) from au2 where au2.tem_botao), 0) ent_botao,
           (select count(*) from bl) bloq,
           (select count(*) from bl where bl.copy is not null) bloq_copy,
           coalesce((select sum(bcp.srv_entregues) from bcp), 0) srv_bc,
           coalesce((select sum(au2.entregues) from au2 where not au2.eh_template), 0) srv_au,
           coalesce((select sum(vd.msgs) from vd), 0) msgs_vd
  ),
  cat as (
    select x.categoria, sum(x.entregues) entregues, sum(x.custo) custo from (
      select coalesce(bcp.categoria, 'SEM CATEGORIA') categoria, bcp.tpl_entregues entregues, bcp.custo_tpl custo from bcp
      union all select coalesce(au2.categoria, 'SEM CATEGORIA'), au2.entregues, au2.custo from au2 where au2.eh_template
      union all select 'UTILITY', vd.utl, vd.utl * public.cic_preco_whatsapp('UTILITY', p_fim) from vd where vd.utl > 0
      union all select 'MARKETING', vd.mkt, vd.mkt * public.cic_preco_whatsapp('MARKETING', p_fim) from vd where vd.mkt > 0
      union all select 'SERVICE', sv.qtd, sv.custo from sv
    ) x group by 1
  ),
  dias as (select generate_series(p_inicio, p_fim, interval '1 day')::date dia)
  select jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim,
    'resumo', (select jsonb_build_object(
        'templates_enviados', tot.env, 'templates_entregues', tot.ent, 'lidos', tot.lid, 'falhas', tot.fal,
        'taxa_entrega', case when tot.env > 0 then round(tot.ent::numeric / tot.env, 4) end,
        'taxa_leitura', case when tot.ent > 0 then round(tot.lid::numeric / tot.ent, 4) end,
        'cliques', tot.cli, 'taxa_cliques', case when tot.ent_botao > 0 then round(tot.cli::numeric / tot.ent_botao, 4) end,
        'bloqueios', tot.bloq, 'bloqueios_com_copy', tot.bloq_copy,
        'taxa_bloqueios', case when tot.ent > 0 then round(tot.bloq::numeric / tot.ent, 4) end,
        'custo_total', round(tot.c_bc + tot.c_au + tot.c_vd - tot.desc_fr, 2),
        'custo_servico_bruto', round(tot.c_srv, 2), 'servico_msgs', tot.srv_tot,
        'franquia_desconto', round(tot.desc_fr, 2), 'franquia_msgs', tot.msgs_fr,
        'custo_broadcast', round(tot.c_bc, 2), 'custo_automacao', round(tot.c_au, 2), 'custo_vendedor', round(tot.c_vd, 2),
        'vendas_comercial', tot.vendas_com,
        'custo_por_venda', case when tot.vendas_com > 0 then round((tot.c_bc + tot.c_au + tot.c_vd - tot.desc_fr) / tot.vendas_com, 2) end,
        'sessao_broadcast', tot.srv_bc, 'sessao_automacao', tot.srv_au, 'msgs_vendedores', tot.msgs_vd) from tot),
    'por_categoria', coalesce((select jsonb_agg(jsonb_build_object('categoria', cat.categoria, 'entregues', cat.entregues, 'custo', round(cat.custo, 2))
                                order by cat.custo desc nulls last) from cat), '[]'::jsonb),
    'custo_dia', coalesce((select jsonb_agg(jsonb_build_object(
        'dia', dias.dia,
        'broadcast', round(coalesce((select sum(bcp.custo) from bcp where bcp.dia = dias.dia), 0), 2),
        'vendedor', round(coalesce((select vd_dia.custo from vd_dia where vd_dia.dia = dias.dia), 0), 2),
        'automacao', round(coalesce((select au_dia.custo from au_dia where au_dia.dia = dias.dia), 0), 2),
        'templates', coalesce((select sum(bcp.tpl_entregues) from bcp where bcp.dia = dias.dia), 0)
                   + coalesce((select au_dia.tpl from au_dia where au_dia.dia = dias.dia), 0)
                   + coalesce((select vd_dia.tpl from vd_dia where vd_dia.dia = dias.dia), 0)) order by dias.dia) from dias), '[]'::jsonb),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
        'campanha', camp.campanha, 'broadcasts', camp.n, 'ultimo', camp.ultimo,
        'contatos', camp.contatos, 'entregues', camp.entregues, 'lidos', camp.lidos, 'falhas', camp.falhas,
        'custo', round(camp.custo, 2),
        'leads_e0', crm.e0, 'leads_e2', crm.e2, 'vendas', crm.vendas, 'bloqueios', crm.bloqueios,
        'lotes', (select jsonb_agg(jsonb_build_object(
                    'nome', bcp.nome, 'disparo', bcp.ts, 'contatos', bcp.contatos, 'entregues', bcp.tpl_entregues,
                    'lidos', bcp.tpl_lidos, 'falhas', bcp.tpl_falhas, 'template', bcp.template, 'categoria', bcp.categoria,
                    'custo', round(bcp.custo, 2)) order by bcp.ts desc)
                  from bcp where bcp.campanha = camp.campanha))
        order by camp.ultimo desc)
      from camp left join crm on crm.tipo = 'campanha' and crm.chave = camp.campanha), '[]'::jsonb),
    'automacoes', coalesce((select jsonb_agg(jsonb_build_object(
        'automacao', a.automacao_nome, 'pasta', a.pasta, 'templates_enviados', a.env, 'templates_entregues', a.ent,
        'sessao_entregues', a.srv, 'lidos', a.lid, 'cliques', a.cli,
        'taxa_cliques', case when a.ent_botao > 0 then round(a.cli::numeric / a.ent_botao, 4) end,
        'categoria', a.cat, 'custo', round(a.custo, 2)) order by a.custo desc nulls last, a.automacao_nome)
      from (select au2.automacao_nome, au2.pasta,
                   sum(au2.enviados) filter (where au2.eh_template) env, sum(au2.entregues) filter (where au2.eh_template) ent,
                   sum(au2.entregues) filter (where not au2.eh_template) srv,
                   sum(au2.lidos) filter (where au2.eh_template) lid,
                   sum(au2.cliques) filter (where au2.tem_botao) cli,
                   sum(au2.entregues) filter (where au2.tem_botao) ent_botao,
                   string_agg(distinct au2.categoria, ', ') filter (where au2.eh_template) cat,
                   sum(au2.custo) custo
            from au2 group by 1, 2
            having sum(au2.enviados) > 0 or sum(au2.entregues) > 0) a), '[]'::jsonb),
    'familias', coalesce((select jsonb_agg(jsonb_build_object(
        'familia', crm.chave, 'leads_e0', crm.e0, 'leads_e2', crm.e2, 'vendas', crm.vendas, 'bloqueios', crm.bloqueios)
        order by crm.e0 desc, crm.chave) from crm where crm.tipo = 'familia'), '[]'::jsonb),
    'vendedores', coalesce((select jsonb_agg(jsonb_build_object(
        'vendedor_slug', vd.utm_slug, 'vendedor', vd.nome, 'ativo', vd.ativo, 'mensagens', vd.msgs, 'servico', vd.servico, 'tpl_utl', vd.utl, 'tpl_mkt', vd.mkt,
        'contatos', vd.contatos, 'custo', round(vd.custo, 2), 'vendas', coalesce(vendas.q, 0),
        'custo_por_venda', case when coalesce(vendas.q, 0) > 0 then round(vd.custo / vendas.q, 2) end) order by vd.custo desc, vd.msgs desc)
      from vd left join vendas on vendas.vendedor_slug = vd.utm_slug), '[]'::jsonb),
    'preco', coalesce((select jsonb_agg(jsonb_build_object('categoria', w.categoria, 'preco', w.preco_brl, 'vigente_desde', w.vigente_desde, 'fonte', w.fonte) order by w.categoria)
      from public.whatsapp_preco w
      where w.vigente_desde = (select max(w2.vigente_desde) from public.whatsapp_preco w2 where w2.categoria = w.categoria and w2.vigente_desde <= p_fim)), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

revoke execute on function public.cic_mensageria(date, date) from public, anon;
grant execute on function public.cic_mensageria(date, date) to authenticated;
