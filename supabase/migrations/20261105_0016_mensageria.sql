-- =====================================================================
-- 0016 · Mensageria (custo estimado de WhatsApp do comercial)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Mensageria, 05/11/2026). Mapa: docs/banco.md
--
-- Custo = templates ENTREGUES x preço da categoria (whatsapp_preco vigente)
--       + mensagens de serviço (não template) x preço SERVICE
--       - franquia de serviço (1.000 por número por mês, desconto no total do
--         mês, não rateado: vale pras primeiras 1.000 do mês, dia a dia).
-- Serviço: vendedores (msg_vendedor + msg_agendada de unnichat_conversas_dia),
-- respostas de broadcast (srv_entregues) e nodes de automação sem template.
-- Estimativa pelo rate card; a fatura do Unnichat é a referência final.
-- Escopo comercial: broadcasts com nome "COMERCIAL..."; automações = todas as
-- coletadas (a coleta já pega só as pastas do comercial: CHECKOUT, BANCO DE
-- EVENTOS e GERAL); vendedores do cadastro.
-- Automações: métricas acumuladas; volume do período = última foto no
-- período - última foto antes dele (sem foto anterior = 0), por node.
-- Copy: contatos com o codigo_copy em unnichat_eventos e quantos compraram
-- depois (venda paga na Hubla casada pelo telefone).
-- =====================================================================

-- Preço da categoria vigente numa data (interna)
create or replace function public.cic_preco_whatsapp(p_categoria text, p_dia date)
returns numeric language sql stable security definer set search_path = '' as $$
  select w.preco_brl from public.whatsapp_preco w
  where w.categoria = upper(p_categoria) and w.vigente_desde <= p_dia
  order by w.vigente_desde desc limit 1
$$;
revoke execute on function public.cic_preco_whatsapp(text, date) from public, anon, authenticated;

-- Mensagens de serviço por dia e origem (interna). Automação: diferença da
-- última foto do dia contra a última foto do dia anterior (sem foto anterior,
-- conta o acumulado da primeira foto).
create or replace function public.cic_servico_dia(p_inicio date, p_fim date)
returns table (dia date, origem text, chave text, qtd bigint)
language sql stable security definer set search_path = '' as $$
  select c.dia, 'vendedor', c.vendedor, sum(coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0))::bigint
  from public.unnichat_conversas_dia c
  where c.dia between p_inicio and p_fim and c.vendedor is not null
  group by 1, 3
  having sum(coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0)) > 0
  union all
  select (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date, 'broadcast', b.broadcast_id, coalesce(b.srv_entregues, 0)::bigint
  from public.unnichat_broadcasts b
  where b.nome ilike 'COMERCIAL%' and coalesce(b.srv_entregues, 0) > 0
    and (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim
  union all
  select x.dia, 'automacao', x.automacao_nome, sum(x.q)::bigint from (
    select d.dia, d.automacao_nome,
           greatest(d.entregues - coalesce(lag(d.entregues) over (partition by d.automacao_id, d.node_id order by d.dia), 0), 0) q
    from (
      select distinct on (m.automacao_id, m.node_id, (m.coletado_em at time zone 'America/Sao_Paulo')::date)
             m.automacao_id, m.node_id, m.automacao_nome, (m.coletado_em at time zone 'America/Sao_Paulo')::date dia, m.entregues
      from public.unnichat_automacoes_metricas m
      where m.node_id <> '_total' and coalesce(m.message_type, '') <> 'send_template'
        and (m.coletado_em at time zone 'America/Sao_Paulo')::date <= p_fim
      order by m.automacao_id, m.node_id, (m.coletado_em at time zone 'America/Sao_Paulo')::date, m.coletado_em desc
    ) d
  ) x
  where x.dia between p_inicio and p_fim and x.q > 0
  group by 1, 3
$$;
revoke execute on function public.cic_servico_dia(date, date) from public, anon, authenticated;

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
  bc as (
    select b.broadcast_id, b.nome, (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date dia,
           b.contatos, b.tpl_enviados, b.tpl_entregues, b.tpl_lidos, b.tpl_falhas,
           b.srv_enviados, b.srv_entregues, t.nome template, t.categoria,
           b.tpl_entregues * public.cic_preco_whatsapp(t.categoria, (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date)
           + coalesce(b.srv_entregues, 0) * public.cic_preco_whatsapp('SERVICE', (coalesce(b.started_at, b.send_at) at time zone 'America/Sao_Paulo')::date) custo
    from public.unnichat_broadcasts b
    left join public.unnichat_templates t on t.template_id = b.template_id
    where b.nome ilike 'COMERCIAL%'
      and coalesce(b.started_at, b.send_at) >= v_ini and coalesce(b.started_at, b.send_at) < v_fim
  ),
  fotos as (
    select m.automacao_id, m.node_id, m.automacao_nome, m.pasta, m.message_type,
           (array_agg(m.enviados  order by m.coletado_em desc) filter (where m.coletado_em >= v_ini and m.coletado_em < v_fim))[1] env_fim,
           (array_agg(m.entregues order by m.coletado_em desc) filter (where m.coletado_em >= v_ini and m.coletado_em < v_fim))[1] ent_fim,
           (array_agg(m.lidos     order by m.coletado_em desc) filter (where m.coletado_em >= v_ini and m.coletado_em < v_fim))[1] lid_fim,
           (array_agg(m.falhas    order by m.coletado_em desc) filter (where m.coletado_em >= v_ini and m.coletado_em < v_fim))[1] fal_fim,
           (array_agg(m.enviados  order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] env_ini,
           (array_agg(m.entregues order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] ent_ini,
           (array_agg(m.lidos     order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] lid_ini,
           (array_agg(m.falhas    order by m.coletado_em desc) filter (where m.coletado_em < v_ini))[1] fal_ini
    from public.unnichat_automacoes_metricas m
    where m.node_id <> '_total' and m.coletado_em < v_fim
    group by 1, 2, 3, 4, 5
  ),
  au as (
    select f.automacao_id, f.automacao_nome, f.pasta, f.node_id, f.message_type,
           n.categoria_cobranca categoria, n.template_nome,
           greatest(coalesce(f.env_fim, 0) - coalesce(f.env_ini, 0), 0) enviados,
           greatest(coalesce(f.ent_fim, 0) - coalesce(f.ent_ini, 0), 0) entregues,
           greatest(coalesce(f.lid_fim, 0) - coalesce(f.lid_ini, 0), 0) lidos,
           greatest(coalesce(f.fal_fim, 0) - coalesce(f.fal_ini, 0), 0) falhas,
           (f.message_type = 'send_template') eh_template
    from fotos f
    left join public.unnichat_automacoes_nodes n on n.automacao_id = f.automacao_id and n.node_id = f.node_id
    where f.env_fim is not null
  ),
  au2 as (
    select au.*, au.entregues * public.cic_preco_whatsapp(case when au.eh_template then au.categoria else 'SERVICE' end, p_fim) custo from au
  ),
  vd as (
    select v.utm_slug, v.nome,
           coalesce(sum(c.msg_vendedor), 0) msgs,
           coalesce(sum(c.tpl_vendedor_utl), 0) utl,
           coalesce(sum(c.tpl_vendedor_mkt), 0) mkt,
           count(distinct c.contact_id) filter (where c.msg_vendedor > 0) contatos,
           coalesce(sum(coalesce(c.tpl_vendedor_utl, 0) * public.cic_preco_whatsapp('UTILITY', c.dia)
                      + coalesce(c.tpl_vendedor_mkt, 0) * public.cic_preco_whatsapp('MARKETING', c.dia)), 0) custo_tpl,
           coalesce(sum(coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0)), 0) servico,
           coalesce(sum((coalesce(c.msg_vendedor, 0) + coalesce(c.msg_agendada, 0)) * public.cic_preco_whatsapp('SERVICE', c.dia)), 0) custo_srv
    from public.vendedores v
    left join public.unnichat_conversas_dia c on c.vendedor = v.nome and c.dia between p_inicio and p_fim
    where v.ativo
    group by 1, 2
  ),
  vd2 as (select vd.*, vd.custo_tpl + vd.custo_srv custo from vd),
  vendas as (select x.vendedor_slug, count(*) q from public.cic_vendas_validas(p_inicio, p_fim) x where x.vendedor_slug is not null group by 1),
  sv_mes as (select * from public.cic_servico_dia(date_trunc('month', p_inicio)::date, p_fim)),
  sv as (select sv_mes.*, sv_mes.qtd * public.cic_preco_whatsapp('SERVICE', sv_mes.dia) custo from sv_mes where sv_mes.dia >= p_inicio),
  sv_dia as (
    select t.dia, t.q,
           sum(t.q) over (partition by date_trunc('month', t.dia) order by t.dia) acum
    from (select sv_mes.dia, sum(sv_mes.qtd) q from sv_mes group by 1) t
  ),
  franquia as (
    select coalesce(sum((least(1000, sv_dia.acum) - least(1000, sv_dia.acum - sv_dia.q)) * public.cic_preco_whatsapp('SERVICE', sv_dia.dia)), 0) desconto,
           coalesce(sum(least(1000, sv_dia.acum) - least(1000, sv_dia.acum - sv_dia.q)), 0) msgs
    from sv_dia where sv_dia.dia >= p_inicio
  ),
  h as (
    select public.cic_fone_chave(v.payer_telefone) chave, v.sale_date, public.cic_vendedor_de_utm(v.utm_source) vend
    from public.hubla_vendas v
    where v.status in ('paid', 'refunded', 'chargeback', 'chargedback') and v.sale_date is not null
  ),
  cp as (
    select e.codigo_copy, public.cic_fone_chave(e.telefone) chave, min(e.event_ts) ts
    from public.unnichat_eventos e
    where e.codigo_copy is not null and e.event_ts >= v_ini and e.event_ts < v_fim
    group by 1, 2
  ),
  cp2 as (
    select cp.codigo_copy,
           count(*) contatos,
           count(*) filter (where exists (select 1 from h where h.chave = cp.chave and h.sale_date >= cp.ts and h.sale_date < v_fim)) vendas,
           count(*) filter (where exists (select 1 from h where h.chave = cp.chave and h.sale_date >= cp.ts and h.sale_date < v_fim and h.vend is not null)) vendas_comercial
    from cp group by 1
  ),
  cat as (
    select x.categoria, sum(x.entregues) entregues, sum(x.custo) custo from (
      select coalesce(bc.categoria, 'SEM CATEGORIA') categoria, bc.tpl_entregues entregues,
             bc.tpl_entregues * public.cic_preco_whatsapp(bc.categoria, bc.dia) from bc
      union all select coalesce(au2.categoria, 'SEM CATEGORIA'), au2.entregues, au2.custo from au2 where au2.eh_template
      union all select 'UTILITY', vd.utl, vd.utl * public.cic_preco_whatsapp('UTILITY', p_fim) from vd where vd.utl > 0
      union all select 'MARKETING', vd.mkt, vd.mkt * public.cic_preco_whatsapp('MARKETING', p_fim) from vd where vd.mkt > 0
      union all select 'SERVICE', sv.qtd, sv.custo from sv
    ) x group by 1
  ),
  tot as (
    select coalesce((select sum(bc.custo) from bc), 0) c_bc,
           coalesce((select sum(au2.custo) from au2), 0) c_au,
           coalesce((select sum(vd2.custo) from vd2), 0) c_vd,
           (select franquia.desconto from franquia) desc_fr,
           (select franquia.msgs from franquia) msgs_fr,
           coalesce((select sum(sv.qtd) from sv), 0) srv_tot,
           coalesce((select sum(sv.custo) from sv), 0) c_srv,
           coalesce((select sum(vendas.q) from vendas), 0) vendas_com,
           coalesce((select sum(bc.tpl_enviados) from bc), 0) + coalesce((select sum(au2.enviados) from au2 where au2.eh_template), 0) env,
           coalesce((select sum(bc.tpl_entregues) from bc), 0) + coalesce((select sum(au2.entregues) from au2 where au2.eh_template), 0) + coalesce((select sum(vd.utl + vd.mkt) from vd), 0) ent,
           coalesce((select sum(bc.tpl_lidos) from bc), 0) + coalesce((select sum(au2.lidos) from au2 where au2.eh_template), 0) lid,
           coalesce((select sum(bc.tpl_falhas) from bc), 0) + coalesce((select sum(au2.falhas) from au2 where au2.eh_template), 0) fal,
           coalesce((select sum(bc.srv_entregues) from bc), 0) srv_bc,
           coalesce((select sum(au2.entregues) from au2 where not au2.eh_template), 0) srv_au,
           coalesce((select sum(vd.msgs) from vd), 0) msgs_vd
  )
  select jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim,
    'resumo', (select jsonb_build_object(
        'templates_enviados', tot.env, 'templates_entregues', tot.ent, 'lidos', tot.lid, 'falhas', tot.fal,
        'taxa_entrega', case when tot.env > 0 then round(tot.ent::numeric / tot.env, 4) end,
        'taxa_leitura', case when tot.ent > 0 then round(tot.lid::numeric / tot.ent, 4) end,
        'custo_total', round(tot.c_bc + tot.c_au + tot.c_vd - tot.desc_fr, 2),
        'custo_servico_bruto', round(tot.c_srv, 2), 'servico_msgs', tot.srv_tot,
        'franquia_desconto', round(tot.desc_fr, 2), 'franquia_msgs', tot.msgs_fr,
        'custo_broadcast', round(tot.c_bc, 2), 'custo_automacao', round(tot.c_au, 2), 'custo_vendedor', round(tot.c_vd, 2),
        'vendas_comercial', tot.vendas_com,
        'custo_por_venda', case when tot.vendas_com > 0 then round((tot.c_bc + tot.c_au + tot.c_vd - tot.desc_fr) / tot.vendas_com, 2) end,
        'sessao_broadcast', tot.srv_bc, 'sessao_automacao', tot.srv_au, 'msgs_vendedores', tot.msgs_vd) from tot),
    'por_categoria', coalesce((select jsonb_agg(jsonb_build_object('categoria', cat.categoria, 'entregues', cat.entregues, 'custo', round(cat.custo, 2)) order by cat.custo desc nulls last) from cat), '[]'::jsonb),
    'broadcasts', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', bc.nome, 'dia', bc.dia, 'contatos', bc.contatos, 'enviados', bc.tpl_enviados, 'entregues', bc.tpl_entregues,
        'lidos', bc.tpl_lidos, 'falhas', bc.tpl_falhas, 'sessao_entregues', bc.srv_entregues,
        'template', bc.template, 'categoria', bc.categoria, 'custo', round(bc.custo, 2)) order by bc.dia desc, bc.nome) from bc), '[]'::jsonb),
    'automacoes', coalesce((select jsonb_agg(jsonb_build_object(
        'automacao', a.automacao_nome, 'pasta', a.pasta, 'templates_enviados', a.env, 'templates_entregues', a.ent,
        'sessao_entregues', a.srv, 'categoria', a.cat, 'custo', round(a.custo, 2)) order by a.custo desc nulls last, a.automacao_nome)
      from (select au2.automacao_nome, au2.pasta,
                   sum(au2.enviados) filter (where au2.eh_template) env, sum(au2.entregues) filter (where au2.eh_template) ent,
                   sum(au2.entregues) filter (where not au2.eh_template) srv,
                   string_agg(distinct au2.categoria, ', ') filter (where au2.eh_template) cat,
                   sum(au2.custo) custo
            from au2 group by 1, 2
            having sum(au2.enviados) > 0 or sum(au2.entregues) > 0) a), '[]'::jsonb),
    'vendedores', coalesce((select jsonb_agg(jsonb_build_object(
        'vendedor_slug', vd2.utm_slug, 'vendedor', vd2.nome, 'mensagens', vd2.msgs, 'servico', vd2.servico, 'tpl_utl', vd2.utl, 'tpl_mkt', vd2.mkt,
        'contatos', vd2.contatos, 'custo', round(vd2.custo, 2), 'vendas', coalesce(vendas.q, 0),
        'custo_por_venda', case when coalesce(vendas.q, 0) > 0 then round(vd2.custo / vendas.q, 2) end) order by vd2.custo desc, vd2.msgs desc)
      from vd2 left join vendas on vendas.vendedor_slug = vd2.utm_slug), '[]'::jsonb),
    'copy', coalesce((select jsonb_agg(jsonb_build_object('codigo_copy', cp2.codigo_copy, 'contatos', cp2.contatos,
        'vendas', cp2.vendas, 'vendas_comercial', cp2.vendas_comercial) order by cp2.contatos desc) from cp2), '[]'::jsonb),
    'preco', coalesce((select jsonb_agg(jsonb_build_object('categoria', w.categoria, 'preco', w.preco_brl, 'vigente_desde', w.vigente_desde, 'fonte', w.fonte) order by w.categoria)
      from public.whatsapp_preco w
      where w.vigente_desde = (select max(w2.vigente_desde) from public.whatsapp_preco w2 where w2.categoria = w.categoria and w2.vigente_desde <= p_fim)), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

revoke execute on function public.cic_mensageria(date, date) from public, anon;
grant execute on function public.cic_mensageria(date, date) to authenticated;
