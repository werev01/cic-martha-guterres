-- =====================================================================
-- 0011 · unnichat_conversas_dia: template do vendedor por categoria
-- Projeto: CIC Martha Guterres (zrvrfxhzwzumvetgjure)
-- Contrato: docs/contrato-dados.md (unnichat_conversas_dia)
--
-- Desfaz a 0010. A API REST do Unnichat traz templateCategory em cada
-- mensagem de template (o MCP não trazia), então dá pra separar utilidade
-- de marketing no template enviado pelo vendedor.
-- tpl_vendedor_utl = UTILITY + AUTHENTICATION (mesmo preço) + sem categoria.
-- Preenche as linhas já gravadas a partir de
-- raw_payload->templates_por_categoria->vendedor.
-- =====================================================================
alter table public.unnichat_conversas_dia add column tpl_vendedor_utl integer;
alter table public.unnichat_conversas_dia add column tpl_vendedor_mkt integer;

update public.unnichat_conversas_dia
set tpl_vendedor_mkt = coalesce((raw_payload->'templates_por_categoria'->'vendedor'->>'MARKETING')::int, 0),
    tpl_vendedor_utl = coalesce(tpl_vendedor, 0)
                     - coalesce((raw_payload->'templates_por_categoria'->'vendedor'->>'MARKETING')::int, 0);

alter table public.unnichat_conversas_dia drop column tpl_vendedor;
