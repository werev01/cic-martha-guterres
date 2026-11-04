-- =====================================================================
-- 0006 · Padrão de UTM com sublinhado + links de venda por vendedor
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Docs: docs/escopo.md, docs/contrato-dados.md, docs/banco.md
--
-- Decisão (04/11/2026): o utm_source oficial do vendedor é
--   comercial_nome-sobrenome   (sublinhado depois de "comercial")
-- igual aos links que o time já usa. Para não perder venda por variação de
-- digitação, a identificação do vendedor trata "_" e "-" como iguais e
-- ignora maiúscula/minúscula e espaços (função cic_vendedor_de_utm).
--
-- Links de venda: um link base por produto em links_venda; o CIC monta o
-- link de cada vendedor com o utm_source dele (função cic_meus_links).
-- =====================================================================

-- 1. Slug do vendedor passa pro padrão com sublinhado (perfis acompanha)
alter table public.perfis drop constraint perfis_vendedor_slug_fkey;
alter table public.perfis add constraint perfis_vendedor_slug_fkey
  foreign key (vendedor_slug) references public.vendedores(utm_slug) on update cascade;

alter table public.vendedores drop constraint vendedores_utm_slug_check;
update public.vendedores set utm_slug = regexp_replace(utm_slug, '^comercial-', 'comercial_');
alter table public.vendedores add constraint vendedores_utm_slug_check
  check (utm_slug ~ '^comercial_[a-z0-9]+(-[a-z0-9]+)*$');

update public.cic_config
   set valor = '{"campo": "utm_source", "prefixo": "comercial_", "formato": "comercial_nome-sobrenome"}',
       atualizado_em = now()
 where chave = 'utm_vendedor';

-- 2. Identificação do vendedor a partir do utm_source (tolerante a variação)
create or replace function public.cic_utm_chave(p_utm text)
returns text language sql immutable set search_path = '' as $$
  select nullif(replace(lower(btrim(p_utm)), '_', '-'), '')
$$;

create or replace function public.cic_vendedor_de_utm(p_utm text)
returns text language sql stable security definer set search_path = '' as $$
  select v.utm_slug from public.vendedores v
  where public.cic_utm_chave(v.utm_slug) = public.cic_utm_chave(p_utm)
  limit 1
$$;

revoke execute on function public.cic_vendedor_de_utm(text) from public, anon, authenticated;

-- 3. Links de venda (link base por produto)
create table public.links_venda (
  id         bigint generated always as identity primary key,
  produto    text not null,
  rotulo     text not null,                -- diferencia links do mesmo produto
  url_base   text not null unique check (url_base ~ '^https://'),
  ordem      smallint not null default 1,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

insert into public.links_venda (produto, rotulo, url_base, ordem) values
  ('Ultra Black 2026', 'Opção 1', 'https://pay.hub.la/RC45oJEeaYbzOsAiXc43', 1),
  ('Ultra Black 2026', 'Opção 2', 'https://pay.hub.la/GTRMaFhX5NkvgqqXJfmn', 2);

alter table public.links_venda enable row level security;
revoke all on public.links_venda from anon, authenticated;
grant select on public.links_venda to authenticated;
create policy links_venda_le on public.links_venda for select to authenticated
  using ((select public.cic_meu_papel()) is not null);

-- 4. Links prontos por vendedor. Roda com a permissão de quem chama:
--    vendedor só enxerga o próprio cadastro (RLS de vendedores), admin vê todos.
create or replace function public.cic_meus_links()
returns table (vendedor_slug text, vendedor_nome text, produto text, rotulo text, url text)
language sql stable security invoker set search_path = '' as $$
  select v.utm_slug, v.nome, l.produto, l.rotulo,
         l.url_base || case when position('?' in l.url_base) > 0 then '&' else '?' end
                    || 'utm_source=' || v.utm_slug
  from public.vendedores v
  cross join public.links_venda l
  where v.ativo and l.ativo
  order by v.nome, l.ordem
$$;

revoke execute on function public.cic_meus_links() from public, anon;
grant execute on function public.cic_meus_links() to authenticated;
