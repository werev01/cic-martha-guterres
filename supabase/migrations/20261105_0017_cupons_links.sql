-- =====================================================================
-- 0017 · Cupom junto dos links de venda
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (ofertas e cupons vigentes). Mapa: docs/banco.md
--
-- links_venda ganha cupom e cupom_desconto (texto, ex.: '5%').
-- cic_meus_links() passa a devolver os dois (tipo de retorno muda: drop e
-- create). Mesmo comportamento: security invoker, RLS de vendedores e
-- links_venda decide o que cada um vê.
-- =====================================================================

alter table public.links_venda add column cupom text;
alter table public.links_venda add column cupom_desconto text;

-- Cupons vigentes (pelo produto, não pelo id)
update public.links_venda set cupom = '5OFF', cupom_desconto = '5%'
 where produto = 'Ultra Black 2026';
update public.links_venda set cupom = 'DEZCONTO', cupom_desconto = '10%'
 where produto in ('Meal Prep Express', 'Meal Prep Express + Regina IA');

drop function public.cic_meus_links();
create function public.cic_meus_links()
returns table (vendedor_slug text, vendedor_nome text, produto text, rotulo text, url text,
               cupom text, cupom_desconto text)
language sql stable security invoker set search_path = '' as $$
  select v.utm_slug, v.nome, l.produto, l.rotulo,
         l.url_base || case when position('?' in l.url_base) > 0 then '&' else '?' end
                    || 'utm_source=' || v.utm_slug,
         l.cupom, l.cupom_desconto
  from public.vendedores v
  cross join public.links_venda l
  where v.ativo and l.ativo
  order by v.nome, l.ordem
$$;

revoke execute on function public.cic_meus_links() from public, anon;
grant execute on function public.cic_meus_links() to authenticated;
