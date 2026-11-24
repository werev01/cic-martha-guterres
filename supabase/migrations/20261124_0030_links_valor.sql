-- =====================================================================
-- 0030 · Links de venda: valor em coluna própria e ordem da lista
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
--
-- A Minha página passa a mostrar os links numa grade (oferta, valor, link, cupons).
-- 1. links_venda.valor: preço cheio do link em R$ (sem cupom). O valor sai do rótulo.
--    Ultra Black Aluno R$ 797 e Não Aluno R$ 987 conferidos nas vendas comerciais
--    sem cupom (hubla_vendas, ofertas "(COMERCIAL)").
-- 2. Rótulo fica só com a opção (Aluno, Anual...). Quando a única diferença entre
--    os links do produto é o preço, o rótulo fica vazio e o valor distingue.
-- 3. Ordem: Ultra Black (Aluno, Aluno boleto, Não Aluno, Não Aluno boleto),
--    Meal Prep, Meal Prep + Regina IA, Clubinho.
-- 4. cic_meus_links() devolve também o valor (a assinatura muda: drop + create).
-- =====================================================================

alter table public.links_venda add column if not exists valor numeric(10, 2);
comment on column public.links_venda.valor is 'Preço cheio do link em R$, sem cupom (mostrado na Minha página).';

update public.links_venda l set rotulo = v.rotulo, valor = v.valor, ordem = v.ordem
from (values
  (1::bigint,  'Aluno',                         797.00, 1::smallint),
  (9::bigint,  'Aluno · boleto parcelado',      897.00, 2::smallint),
  (2::bigint,  'Não Aluno',                     987.00, 3::smallint),
  (10::bigint, 'Não Aluno · boleto parcelado', 1087.00, 4::smallint),
  (5::bigint,  '',                              397.00, 5::smallint),
  (3::bigint,  '',                              297.00, 6::smallint),
  (6::bigint,  '',                              497.00, 7::smallint),
  (7::bigint,  'Anual',                         497.00, 8::smallint),
  (8::bigint,  'Semestral',                     248.00, 9::smallint)
) v(id, rotulo, valor, ordem)
where l.id = v.id;

drop function if exists public.cic_meus_links();
create function public.cic_meus_links()
returns table (vendedor_slug text, vendedor_nome text, produto text, rotulo text, valor numeric, url text, cupons jsonb)
language sql stable set search_path = '' as $$
  select v.utm_slug, v.nome, l.produto, l.rotulo, l.valor,
         l.url_base || case when position('?' in l.url_base) > 0 then '&' else '?' end
                    || 'utm_source=' || v.utm_slug,
         coalesce((select jsonb_agg(jsonb_build_object('cupom', c.cupom, 'desconto', c.desconto) order by c.ordem, c.id)
                   from public.links_venda_cupons c
                   where c.link_id = l.id and c.ativo), '[]'::jsonb)
  from public.vendedores v
  cross join public.links_venda l
  where v.ativo and l.ativo
  order by v.nome, l.ordem, l.id
$$;
revoke execute on function public.cic_meus_links() from public, anon;
grant execute on function public.cic_meus_links() to authenticated;
