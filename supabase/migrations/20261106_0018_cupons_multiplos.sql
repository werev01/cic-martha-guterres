-- =====================================================================
-- 0018 · Mais de um cupom por link de venda
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Regras: docs/escopo.md (ofertas e cupons vigentes). Mapa: docs/banco.md
--
-- Cupons saem de links_venda (colunas da 0017) e vão pra links_venda_cupons
-- (vários por link). cic_meus_links() devolve `cupons jsonb`
-- ([{cupom, desconto}], só ativos, na ordem). As colunas antigas são
-- removidas no fim pra não ter duas fontes.
-- =====================================================================

create table public.links_venda_cupons (
  id         bigint generated always as identity primary key,
  link_id    bigint not null references public.links_venda (id) on delete cascade,
  cupom      text not null,
  desconto   text,                              -- ex.: '10%'
  ordem      smallint not null default 1,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  unique (link_id, cupom)
);
comment on table public.links_venda_cupons is
  'CADASTRO: cupons de cada link de venda (vários por link). Lido pelo app via cic_meus_links().';

-- RLS igual à de links_venda: só leitura, pra quem tem perfil
alter table public.links_venda_cupons enable row level security;
revoke all on public.links_venda_cupons from anon, authenticated;
grant select on public.links_venda_cupons to authenticated;
create policy links_venda_cupons_le on public.links_venda_cupons for select to authenticated
  using ((select public.cic_meu_papel()) is not null);

-- Migra o cupom atual de cada link (um por link)
insert into public.links_venda_cupons (link_id, cupom, desconto, ordem)
select l.id, l.cupom, l.cupom_desconto, 1
from public.links_venda l
where l.cupom is not null;

-- 10CONTO 10% nos links ativos do Ultra Black, depois do 5OFF
insert into public.links_venda_cupons (link_id, cupom, desconto, ordem)
select l.id, '10CONTO', '10%', 2
from public.links_venda l
where l.produto = 'Ultra Black 2026' and l.ativo
on conflict (link_id, cupom) do nothing;

-- Função com a lista de cupons
drop function public.cic_meus_links();
create function public.cic_meus_links()
returns table (vendedor_slug text, vendedor_nome text, produto text, rotulo text, url text, cupons jsonb)
language sql stable security invoker set search_path = '' as $$
  select v.utm_slug, v.nome, l.produto, l.rotulo,
         l.url_base || case when position('?' in l.url_base) > 0 then '&' else '?' end
                    || 'utm_source=' || v.utm_slug,
         coalesce((select jsonb_agg(jsonb_build_object('cupom', c.cupom, 'desconto', c.desconto) order by c.ordem, c.id)
                   from public.links_venda_cupons c
                   where c.link_id = l.id and c.ativo), '[]'::jsonb)
  from public.vendedores v
  cross join public.links_venda l
  where v.ativo and l.ativo
  order by v.nome, l.ordem
$$;

revoke execute on function public.cic_meus_links() from public, anon;
grant execute on function public.cic_meus_links() to authenticated;

-- Uma fonte só
alter table public.links_venda drop column cupom;
alter table public.links_venda drop column cupom_desconto;
