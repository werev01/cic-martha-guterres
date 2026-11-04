-- =====================================================================
-- 0005 · Régua de comissão do vendedor
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Docs: docs/escopo.md (seção Comissão), docs/banco.md
--
-- Regra (decidida em 04/11/2026, vale de nov/2026 em diante, igual pra todos):
--   faturamento LÍQUIDO individual no mês
--     até R$ 45.000            -> 1%
--     de R$ 45.000,01 a 70.000 -> 1,5%
--     acima de R$ 70.000       -> 2%
--   A porcentagem da faixa atingida vale SOBRE O TOTAL (não é por pedaço).
--
-- Faixa nova = linha nova com outra vigencia_inicio. Nada de regra no código.
-- =====================================================================

create table public.comissao_faixas (
  vigencia_inicio  date not null check (extract(day from vigencia_inicio) = 1),
  nivel            smallint not null check (nivel > 0),
  nome             text not null,
  acima_de         numeric(14,2) not null check (acima_de >= 0),  -- faixa vale quando faturamento > acima_de
  pct              numeric(6,4) not null check (pct >= 0 and pct < 1),
  criado_em        timestamptz not null default now(),
  primary key (vigencia_inicio, nivel),
  unique (vigencia_inicio, acima_de)
);

insert into public.comissao_faixas (vigencia_inicio, nivel, nome, acima_de, pct) values
  ('2026-11-01', 1, 'Nível 1', 0,     0.010),
  ('2026-11-01', 2, 'Nível 2', 45000, 0.015),
  ('2026-11-01', 3, 'Nível 3', 70000, 0.020);

insert into public.cic_config (chave, valor, descricao) values
  ('comissao_regra', '"sobre_total"',
   'Como a porcentagem da faixa se aplica: sobre_total (faixa atingida vale pro faturamento inteiro) ou por_faixa (cada pedaço na sua %)');

-- Calcula a comissão de um faturamento líquido num mês.
-- Devolve nível atual, %, comissão, próximo nível e quanto falta pra ele.
create or replace function public.cic_comissao(p_faturamento numeric, p_mes date)
returns table (
  nivel             smallint,
  nome              text,
  pct               numeric,
  comissao          numeric,
  proximo_nivel     smallint,
  proximo_nome      text,
  proximo_pct       numeric,
  falta_proximo     numeric
)
language sql stable security invoker set search_path = '' as $$
  with vig as (
    select max(f.vigencia_inicio) v
    from public.comissao_faixas f
    where f.vigencia_inicio <= date_trunc('month', p_mes)::date
  ),
  faixas as (
    select f.* from public.comissao_faixas f, vig where f.vigencia_inicio = vig.v
  ),
  regra as (
    select coalesce((select c.valor #>> '{}' from public.cic_config c where c.chave = 'comissao_regra'), 'sobre_total') r
  ),
  atual as (
    select * from faixas where greatest(p_faturamento, 0) > acima_de or acima_de = 0
    order by acima_de desc limit 1
  ),
  prox as (
    select * from faixas where acima_de >= greatest(p_faturamento, 0) and acima_de > 0
    order by acima_de limit 1
  ),
  por_faixa as (
    select sum(greatest(least(greatest(p_faturamento, 0), coalesce(t.teto, 'infinity'::numeric)) - t.acima_de, 0) * t.pct) v
    from (select acima_de, pct, lead(acima_de) over (order by acima_de) teto from faixas) t
  )
  select a.nivel, a.nome, a.pct,
         round(case when (select r from regra) = 'por_faixa' then (select v from por_faixa)
                    else greatest(p_faturamento, 0) * a.pct end, 2),
         p.nivel, p.nome, p.pct,
         case when p.acima_de is null then null else round(p.acima_de - greatest(p_faturamento, 0) + 0.01, 2) end
  from atual a left join prox p on true
$$;

alter table public.comissao_faixas enable row level security;
revoke all on public.comissao_faixas from anon, authenticated;
grant select on public.comissao_faixas to authenticated;
create policy comissao_faixas_le on public.comissao_faixas for select to authenticated
  using ((select public.cic_meu_papel()) is not null);

revoke execute on function public.cic_comissao(numeric, date) from public, anon;
grant execute on function public.cic_comissao(numeric, date) to authenticated;
