-- =====================================================================
-- 0026 · Mensageria: leads da etapa 0 no resumo
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Mensageria, 09/11/2026)
--
-- cic_mensageria igual à 0025, com três campos novos em resumo:
--  leads_e0          pessoas únicas (pessoa_chave) que entraram em "0. Base/Entrada"
--                    no período com copy de campanha de broadcast do período ou de
--                    família de automação (mesma regra das tabelas de campanha e
--                    famílias);
--  taxa_leads_e0     leads_e0 ÷ templates entregues de broadcasts + automações;
--  custo_por_lead_e0 (custo de broadcasts + automações) ÷ leads_e0; vendedor fora.
-- Aplicada em 09/11 trocando só esses trechos do corpo da 0025 (mesmo resultado).
-- =====================================================================

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
           coalesce((select sum(vd.msgs) from vd), 0) msgs_vd,
           -- leads E0: pessoa única na Base com copy de campanha de broadcast do período ou de família de automação
           (select count(distinct evc.pessoa) from evc
             where evc.event_ts >= v_ini and evc.etapa_crm = '0. Base/Entrada'
               and (evc.codigo_copy in (select bcp.campanha from bcp) or evc.codigo_copy not in (select bc.campanha from bc))) leads_e0,
           -- base de entrega dos leads: templates entregues de broadcasts + automações (sem vendedores)
           coalesce((select sum(bcp.tpl_entregues) from bcp), 0) + coalesce((select sum(au2.entregues) from au2 where au2.eh_template), 0) ent_ba
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
        'sessao_broadcast', tot.srv_bc, 'sessao_automacao', tot.srv_au, 'msgs_vendedores', tot.msgs_vd,
        'leads_e0', tot.leads_e0, 'taxa_leads_e0', case when tot.ent_ba > 0 then round(tot.leads_e0::numeric / tot.ent_ba, 4) end,
        'custo_por_lead_e0', case when tot.leads_e0 > 0 then round((tot.c_bc + tot.c_au) / tot.leads_e0, 2) end) from tot),
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
