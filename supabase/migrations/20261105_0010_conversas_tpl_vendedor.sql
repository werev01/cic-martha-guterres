-- =====================================================================
-- 0010 · unnichat_conversas_dia: template do vendedor numa coluna só
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Contrato: docs/contrato-dados.md (unnichat_conversas_dia)
--
-- A mensagem do Unnichat não informa qual template o vendedor mandou
-- (type = template, text nulo, sem id): não dá pra separar utilidade de
-- marketing. Troca tpl_vendedor_utl/tpl_vendedor_mkt por tpl_vendedor.
-- Custo estimado pelo preço de utilidade até haver como saber a categoria
-- (decidido em 05/11/2026; validar com o tempo).
-- Tabela vazia e sem views dependentes no momento da troca.
-- =====================================================================
alter table public.unnichat_conversas_dia add column tpl_vendedor integer;
alter table public.unnichat_conversas_dia drop column tpl_vendedor_utl;
alter table public.unnichat_conversas_dia drop column tpl_vendedor_mkt;
