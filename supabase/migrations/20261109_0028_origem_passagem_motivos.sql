-- =====================================================================
-- 0028 · Taxa de passagem por origem e origem nos motivos de perda
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (Taxa de passagem por origem e Motivos de perda, 09/11/2026)
--
-- Origem do negócio = origem mais recente (não vazia) dos eventos do negócio;
-- sem nenhuma = "Sem origem" (eventos de 07/11 em diante sem origem).
-- Origem da venda = origem do evento mais recente da pessoa antes da compra
-- (vazia = "Sem origem"); sem evento antes = funil padrão (cic_config.funil_padrao).
--
-- 1. cic_negocio_origem() (interna): origem de cada negócio.
-- 2. cic_taxa_passagem_origem(p_inicio, p_fim, p_vendedor), só admin: as linhas
--    do funil geral (origem nula) e as mesmas linhas por origem, com a mesma
--    regra de contagem do funil (0027) particionada pela origem do negócio; as
--    vendas pela origem da venda. Em cada linha, pessoas_e2 / vendas_total /
--    conversao do grupo: vendas comerciais ÷ pessoas únicas (pessoa_chave) que
--    passaram por "2. Em Contato" no período (origem do evento), a mesma
--    conversão da Home. Origem sem negócio no período não aparece.
--    cic_taxa_passagem (0027) continua igual.
-- 3. cic_motivos_perda ganha a coluna origem (origem do negócio), no fim.
-- =====================================================================

create or replace function public.cic_negocio_origem()
returns table (negocio_id text, origem text)
language sql stable security definer set search_path = '' as $$
  select e.negocio_id,
         coalesce((array_agg(trim(e.origem) order by e.event_ts desc) filter (where nullif(trim(e.origem), '') is not null))[1], 'Sem origem')
  from public.unnichat_eventos e
  where e.negocio_id is not null
  group by 1
$$;
revoke execute on function public.cic_negocio_origem() from public, anon, authenticated;

create or replace function public.cic_taxa_passagem_origem(p_inicio date, p_fim date, p_vendedor text default null)
returns table (origem text, ordem integer, etapa text, entraram bigint, avancaram bigint, passagem numeric, perdidos bigint,
               vendas bigint, abertos bigint, pessoas_e2 bigint, vendas_total bigint, conversao numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_ini    timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim    timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  v_padrao text := coalesce((select cf.valor #>> '{}' from public.cic_config cf where cf.chave = 'funil_padrao'), 'Sem funil');
  v_nome   text := (select vd.nome from public.vendedores vd where vd.utm_slug = p_vendedor);
begin
  if not public.cic_eh_admin() then raise exception 'sem permissão' using errcode = '42501'; end if;
  return query
  with neg as (
    select n.*, coalesce(o.origem, 'Sem origem') org
    from public.cic_negocios() n left join public.cic_negocio_origem() o on o.negocio_id = n.negocio_id
    where p_vendedor is null or p_vendedor = '' or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor
  ),
  ent as (select distinct e.negocio_id, c.ordem eo from public.unnichat_eventos e join public.crm_etapas c on c.nome_unnichat = e.etapa_crm
          where e.event_ts >= v_ini and e.event_ts < v_fim),
  vneg as (select distinct v.negocio_id from public.cic_vendas_crm('2000-01-01'::date, p_fim) v where v.negocio_id is not null),
  b as (select ent.eo, neg.*, (neg.negocio_id in (select vneg.negocio_id from vneg)) vendeu from ent join neg on neg.negocio_id = ent.negocio_id),
  -- vendas comerciais do período, crédito pelo utm, com a origem da venda
  vc as (
    select v.ordem_venda, coalesce(u.o, v_padrao) org
    from public.cic_vendas_crm(p_inicio, p_fim) v
    join public.hubla_vendas h on h.invoice_id = v.invoice_id
    left join lateral (
      select coalesce(nullif(trim(e.origem), ''), 'Sem origem') o from public.unnichat_eventos e
      where e.pessoa_chave = h.pessoa_chave and e.event_ts <= h.sale_date
      order by e.event_ts desc limit 1) u on true
    where p_vendedor is null or p_vendedor = '' or v.vendedor_slug = p_vendedor
  ),
  -- pessoas únicas em "2. Em Contato" no período, pela origem do evento
  e2 as (
    select distinct e.pessoa_chave p, coalesce(nullif(trim(e.origem), ''), 'Sem origem') org
    from public.unnichat_eventos e
    where e.etapa_crm = '2. Em Contato' and e.event_ts >= v_ini and e.event_ts < v_fim and e.pessoa_chave is not null
      and (p_vendedor is null or p_vendedor = '' or (p_vendedor = '_sem' and e.proprietario is null) or e.proprietario = v_nome)
  ),
  grupos as (
    select null::text g, 0 ord, null::bigint vol
    union all
    select b.org, 1, count(distinct b.negocio_id) from b group by b.org
  ),
  conv as (
    select gr.g, gr.ord, gr.vol,
           (select count(distinct e2.p) from e2 where gr.g is null or e2.org = gr.g) pe,
           (select count(*) from vc where gr.g is null or vc.org = gr.g) vt
    from grupos gr
  ),
  linhas as (
    select gr.g, gr.ord, gr.vol, c.ordem::int o, c.rotulo,
           count(b.negocio_id)::bigint ent_q,
           count(b.negocio_id) filter (where b.max_ordem > c.ordem or b.vendeu)::bigint av_q,
           (select count(*) from neg where neg.lost_ts >= v_ini and neg.lost_ts < v_fim and coalesce(neg.grupo, '') <> 'cs'
              and neg.perda_ordem = c.ordem and (gr.g is null or neg.org = gr.g))::bigint per_q,
           (select count(*) from vc where vc.ordem_venda = c.ordem and (gr.g is null or vc.org = gr.g))::bigint ven_q,
           count(b.negocio_id) filter (where not b.vendeu and b.lost_ts is null and b.max_ordem = c.ordem)::bigint ab_q
    from grupos gr cross join public.crm_etapas c
    left join b on b.eo = c.ordem and (gr.g is null or b.org = gr.g)
    group by gr.g, gr.ord, gr.vol, c.ordem, c.rotulo
    union all
    select gr.g, gr.ord, gr.vol, null::int, 'Sem negócio no CRM antes da venda', 0::bigint, 0::bigint, 0::bigint,
           (select count(*) from vc where vc.ordem_venda is null and (gr.g is null or vc.org = gr.g))::bigint, 0::bigint
    from grupos gr
    where exists (select 1 from vc where vc.ordem_venda is null and (gr.g is null or vc.org = gr.g))
  )
  select l.g, l.o, l.rotulo, l.ent_q, l.av_q,
         case when l.ent_q > 0 then round(l.av_q::numeric / l.ent_q, 4) end,
         l.per_q, l.ven_q, l.ab_q,
         cv.pe::bigint, cv.vt::bigint,
         case when cv.pe > 0 then least(1, round(cv.vt::numeric / cv.pe, 4)) end
  from linhas l join conv cv on cv.g is not distinct from l.g
  order by l.ord, l.vol desc nulls first, l.g, l.o nulls last;
end $$;
revoke execute on function public.cic_taxa_passagem_origem(date, date, text) from public, anon;
grant execute on function public.cic_taxa_passagem_origem(date, date, text) to authenticated;

drop function if exists public.cic_motivos_perda(date, date, text);
create function public.cic_motivos_perda(p_inicio date, p_fim date, p_vendedor text default null)
returns table (tipo text, grupo text, motivo text, vendedor_slug text, vendedor_nome text, vendedor_ativo boolean, etapa_ordem integer, etapa text,
               qtd bigint, origem text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.cic_eh_admin() then raise exception 'sem permissão' using errcode = '42501'; end if;
  return query
  select case when n.grupo = 'cs' then 'cs' else 'comercial' end, n.grupo, coalesce(n.motivo, 'Motivo não informado'),
         n.vendedor_slug, coalesce(vd.nome, 'Sem vendedor'), vd.ativo, n.perda_ordem, coalesce(c.rotulo, 'Sem etapa'), count(*)::bigint,
         coalesce(o.origem, 'Sem origem')
  from public.cic_negocios() n
  left join public.cic_negocio_origem() o on o.negocio_id = n.negocio_id
  left join public.vendedores vd on vd.utm_slug = n.vendedor_slug
  left join public.crm_etapas c on c.ordem = n.perda_ordem
  where n.lost_ts >= v_ini and n.lost_ts < v_fim
    and (p_vendedor is null or p_vendedor = '' or (p_vendedor = '_sem' and n.vendedor_slug is null) or n.vendedor_slug = p_vendedor)
  group by 1, 2, 3, 4, 5, 6, 7, 8, 10 order by 9 desc;
end $$;
revoke execute on function public.cic_motivos_perda(date, date, text) from public, anon;
grant execute on function public.cic_motivos_perda(date, date, text) to authenticated;
