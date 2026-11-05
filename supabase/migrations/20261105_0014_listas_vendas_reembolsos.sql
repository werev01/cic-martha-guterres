-- =====================================================================
-- 0014 · Listas de vendas e reembolsos (telas Relatórios e Reembolsos)
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (CIC fase 1). Reaproveita cic_vendas_validas e
-- cic_reembolsos_validos (0013), sem duplicar regra.
--
-- Só comercial (venda com vendedor), inclusive pro admin: orgânico fica no
-- banco, fora do dash (05/11). Admin vê todos os vendedores; vendedor só as
-- dele; sem perfil, vazio. Nome e telefone do cliente só nestas listas, pra
-- conferência (o time não acessa a Hubla).
-- =====================================================================

-- Telefone como chegou, só dígitos, com +55 quando vem sem DDI (10 ou 11 dígitos)
create or replace function public.cic_fone(p text)
returns text language sql immutable set search_path = '' as $$
  select case
    when d is null or d = '' then null
    when length(d) in (10, 11) then '+55' || d
    else '+' || d
  end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') d) x
$$;

-- 1. Vendas válidas do período, uma por fatura
create or replace function public.cic_lista_vendas(p_inicio date, p_fim date)
returns table (
  invoice_id text, data date, hora time, cliente text, telefone text,
  vendedor_slug text, vendedor_nome text, produto text, oferta text,
  bruto numeric, liquido numeric, reembolsada boolean, reembolso_data date
)
language sql stable security definer set search_path = '' as $$
  with eu as (select public.cic_eh_admin() adm, public.cic_meu_vendedor() vend),
  v as (
    select x.* from public.cic_vendas_validas(p_inicio, p_fim) x, eu
    where x.vendedor_slug is not null
      and (eu.adm or x.vendedor_slug = eu.vend)
  ),
  r as (
    select y.invoice_id, y.dia
    from public.cic_reembolsos_validos(p_inicio, '9999-12-31') y
    where y.invoice_id in (select v.invoice_id from v)
  )
  select v.invoice_id,
         v.dia,
         (h.sale_date at time zone 'America/Sao_Paulo')::time(0),
         h.payer_nome,
         public.cic_fone(h.payer_telefone),
         v.vendedor_slug,
         vd.nome,
         v.produto,
         h.offer_name,
         round(v.bruto, 2),
         round(v.liquido, 2),
         r.invoice_id is not null,
         r.dia
  from v
  join public.hubla_vendas h on h.invoice_id = v.invoice_id
  left join public.vendedores vd on vd.utm_slug = v.vendedor_slug
  left join r on r.invoice_id = v.invoice_id
  order by h.sale_date desc
$$;

-- 2. Reembolsos efetivados no período (data do reembolso)
create or replace function public.cic_lista_reembolsos(p_inicio date, p_fim date)
returns table (
  invoice_id text, reembolso_data date, venda_data date, cliente text, telefone text,
  vendedor_slug text, vendedor_nome text, produto text, liquido numeric
)
language sql stable security definer set search_path = '' as $$
  with eu as (select public.cic_eh_admin() adm, public.cic_meu_vendedor() vend)
  select r.invoice_id,
         r.dia,
         (h.sale_date at time zone 'America/Sao_Paulo')::date,
         h.payer_nome,
         public.cic_fone(h.payer_telefone),
         r.vendedor_slug,
         vd.nome,
         h.product_name,
         round(r.liquido, 2)
  from public.cic_reembolsos_validos(p_inicio, p_fim) r
  cross join eu
  join public.hubla_vendas h on h.invoice_id = r.invoice_id
  left join public.vendedores vd on vd.utm_slug = r.vendedor_slug
  where r.vendedor_slug is not null
    and (eu.adm or r.vendedor_slug = eu.vend)
  order by r.dia desc, h.sale_date desc
$$;

revoke execute on function public.cic_fone(text) from public, anon, authenticated;
revoke execute on function public.cic_lista_vendas(date, date), public.cic_lista_reembolsos(date, date)
  from public, anon;
grant execute on function public.cic_lista_vendas(date, date), public.cic_lista_reembolsos(date, date)
  to authenticated;
