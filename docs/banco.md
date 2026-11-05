# Banco do CIC Martha Guterres

Mapa do que existe no Supabase (`zrvrfxhzwzumvetgjure`) e como mexer no dia a dia.
Toda mudança de estrutura vira migration em `supabase/migrations/`.

Última atualização: 05/11/2026

## Camadas

| Camada | O que é | Quem lê |
|---|---|---|
| Bruta | 22 tabelas alimentadas pelo n8n (`hubla_*`, `tmb_*`, `unnichat_*`, `callix_*`). Contrato em `contrato-dados.md` | ninguém do app (RLS sem policy, sem grant) |
| Cadastro | config, vendedores, perfis, menus, etapas, motivos, metas, calendário | app, via RLS |
| Tratada | views que o app consome (ainda não criadas: entram com os primeiros payloads) | app, via RLS |
| `tmp_claude` | views de trabalho/diagnóstico, validade de 12h | só ferramentas |

## Migrations aplicadas

| Arquivo | O que fez |
|---|---|
| `20261103_0001_brutas.sql` | 18 tabelas brutas |
| `20261103_0002_revoke_rls_auto_enable.sql` | fechou a chamada pública da `rls_auto_enable()` |
| `20261104_0003_unnichat_blocklist.sql` | bruta `unnichat_blocklist` |
| `20261104_0004_base.sql` | cadastros, funções de papel, RLS, `tmp_claude` + pg_cron |
| `20261104_0005_comissao.sql` | régua de comissão (`comissao_faixas`, `cic_comissao()`) |
| `20261104_0006_links_venda_utm.sql` | UTM com sublinhado, `cic_vendedor_de_utm()`, `links_venda`, `cic_meus_links()` |
| `20261104_0007_ajustes_primeiros_eventos.sql` | guarda contra evento Hubla fora de ordem, `negocio_id`/`etapa_desde` no CRM, correção dos primeiros eventos |
| `20261105_0008_unnichat_coletas.sql` | brutas `unnichat_automacoes_metricas` (foto horária) e `unnichat_automacoes_nodes` (template e categoria de cobrança), `template_id` em `unnichat_broadcasts`, config `whatsapp_preco` com os preços da Meta de 01/10/2026 |
| `20261105_0009_unnichat_templates.sql` | bruta `unnichat_templates` (id da Meta -> nome e categoria), alimentada pela coleta de automações |
| `20261105_0010_conversas_tpl_vendedor.sql` | `unnichat_conversas_dia`: `tpl_vendedor_utl`/`_mkt` viram `tpl_vendedor` (desfeita na 0011) |
| `20261105_0011_conversas_tpl_vendedor_categoria.sql` | volta `tpl_vendedor_utl`/`_mkt` (a API REST traz a categoria do template) e remove `tpl_vendedor` |

## Tabelas de cadastro

| Tabela | Chave | Conteúdo atual |
|---|---|---|
| `cic_config` | `chave` | slug, nome, fuso, `tmb_fator_valor` = 0,5 (provisório), `utm_vendedor` (utm_source + `comercial_`), `conversao_alvo` (15% a partir da etapa 2) |
| `vendedores` | `utm_slug` | 4 vendedores (`comercial_nome-sobrenome`, igual ao `utm_source` dos links) |
| `links_venda` | `id` | link base por produto: Ultra Black 2026 (Aluno e Não Aluno) e Meal Prep Express + Regina IA (Oferta), todos Hubla; o link de cada vendedor sai de `cic_meus_links()` |
| `perfis` | `email` | 4 admins + 4 vendedores; `user_id` se preenche sozinho quando o usuário é criado no Auth |
| `perfil_menus` | `papel, menu` | admin: 11 menus; vendedor: minhapagina, relatorios, reembolsos |
| `crm_etapas` | `ordem` | 0 a 4, com o nome exato do Unnichat |
| `motivos_perda` | `nome_unnichat` | 11 motivos, grupo = código entre colchetes |
| `metas` | `mes, nivel` | nov/2026: bronze 100k, prata 150k, ouro 200k |
| `whatsapp_preco` | `categoria, vigente_desde` | preço Meta por mensagem entregue desde 01/10/2026: MARKETING 0,3217; UTILITY, AUTHENTICATION e SERVICE 0,035 (SERVICE com 1.000 grátis por número/mês). Sem acesso do app; leitura via view |
| `comissao_faixas` | `vigencia_inicio, nivel` | nov/2026: nível 1 (> 0) 1%, nível 2 (> 45 mil) 1,5%, nível 3 (> 70 mil) 2%; regra `sobre_total` em `cic_config` |
| `dim_calendario` | `data` | nov e dez/2026; dia útil = seg a sex sem feriado nacional (19 em novembro) |

## Funções de papel

`cic_meu_papel()`, `cic_eh_admin()`, `cic_meu_vendedor()`: leem o perfil do usuário
logado. São `security definer` e chamáveis por usuário logado (o advisor do Supabase
avisa; é intencional, só devolvem dados do próprio usuário). anon não chama.

## Operações do dia a dia (SQL Editor)

```sql
-- Novo vendedor: cadastro + perfil (o vínculo com o login é automático pelo e-mail)
insert into vendedores (utm_slug, nome, email) values ('comercial_nome-sobrenome', 'Nome Sobrenome', 'email@x.com');
insert into perfis (email, nome, papel, vendedor_slug) values ('email@x.com', 'Nome Sobrenome', 'vendedor', 'comercial_nome-sobrenome');

-- Links de venda de todos os vendedores (copiar e mandar pro time)
select vendedor_nome, rotulo, url from cic_meus_links();

-- Link novo de produto (todo vendedor ganha o seu na hora)
insert into links_venda (produto, rotulo, url_base, ordem) values ('Produto', 'Opção 3', 'https://pay.hub.la/XXXX', 3);

-- Desligar alguém (perde o acesso na hora, sem apagar histórico)
update perfis set ativo = false where email = 'email@x.com';

-- Meta de um mês novo
insert into metas (mes, nivel, valor) values ('2026-12-01','bronze',0), ('2026-12-01','prata',0), ('2026-12-01','ouro',0);

-- Liberar mais um menu pro vendedor
insert into perfil_menus (papel, menu, ordem) values ('vendedor', 'desempenho', 4);

-- Simular comissão (faturamento líquido, mês)
select * from cic_comissao(80000, '2026-11-01');

-- Régua nova a partir de um mês (não altera os meses anteriores)
insert into comissao_faixas (vigencia_inicio, nivel, nome, acima_de, pct) values
  ('2027-01-01',1,'Nível 1',0,0.01), ('2027-01-01',2,'Nível 2',45000,0.015), ('2027-01-01',3,'Nível 3',70000,0.02);

-- Mudar o fator da TMB
update cic_config set valor = '1', atualizado_em = now() where chave = 'tmb_fator_valor';
```

## tmp_claude

- View temporária sempre com comentário `expira_em=<timestamptz ISO sem espaço>`,
  ex.: `comment on view tmp_claude.x is 'expira_em=2026-11-04T22:00:00-03'`.
- Job `limpar-views-tmp-claude` (pg_cron, todo HH:05) apaga as vencidas e as sem
  carimbo.
