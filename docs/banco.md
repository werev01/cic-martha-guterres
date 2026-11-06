# Banco do CIC Martha Guterres

Mapa do que existe no Supabase (`zrvrfxhzwzumvetgjure`) e como mexer no dia a dia.
Toda mudança de estrutura vira migration em `supabase/migrations/`.

Última atualização: 05/11/2026

## Camadas

| Camada | O que é | Quem lê |
|---|---|---|
| Bruta | 22 tabelas alimentadas pelo n8n (`hubla_*`, `tmb_*`, `unnichat_*`, `callix_*`). Contrato em `contrato-dados.md` | ninguém do app (RLS sem policy, sem grant) |
| Cadastro | config, vendedores, perfis, menus, etapas, motivos, metas, calendário | app, via RLS |
| Tratada | funções RPC `security definer` com o filtro de perfil dentro (0012) | app, via `rpc()` |
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
| `20261105_0012_cic_fase1.sql` | trava de venda paga em `hubla_vendas`, funções internas e RPCs da fase 1 (`cic_vendedor_mes`, `cic_meta_mes`, `cic_home`) |
| `20261105_0013_reembolso_por_status.sql` | trava libera paid -> refunded/chargeback (só status e data); venda válida = foi paga um dia; reembolso também pelo status da venda; `cic_home` só com o comercial |
| `20261105_0014_listas_vendas_reembolsos.sql` | RPCs `cic_lista_vendas` e `cic_lista_reembolsos` (telas Relatórios e Reembolsos, só comercial) e função interna `cic_fone` |
| `20261105_0015_gestao.sql` | telas de gestão: `cic_desempenho`, `cic_taxa_passagem`, `cic_motivos_perda`, `cic_ciclo_venda` (só admin); internas `cic_negocios`, `cic_fone_chave`; motivo "[2] Já é cliente" sem o CMP; Daniel Godoy vendedor (segue admin) |
| `20261105_0016_mensageria.sql` | `cic_mensageria` (só admin, custo estimado de WhatsApp do comercial) e internas `cic_preco_whatsapp`, `cic_servico_dia` |
| `20261105_0017_cupons_links.sql` | `cupom` e `cupom_desconto` em `links_venda` (5OFF no Ultra Black, DEZCONTO no Meal Prep); `cic_meus_links()` devolve os dois |
| `20261106_0018_cupons_multiplos.sql` | cupons saem de `links_venda` e vão pra `links_venda_cupons` (vários por link); 10CONTO no Ultra Black; `cic_meus_links()` devolve `cupons jsonb` |
| `20261106_0019_home_cards.sql` | `cic_home` nova (cards do período, hoje e ontem, plataformas, produtos com ofertas, matriz dia a dia); interna `cic_kpis_comercial`; `cic_contatos_em_contato` conta pessoa pela chave do telefone |

## Camada tratada (RPCs do app)

Regras em `escopo.md` (CIC fase 1). Todas `security definer`, `stable`,
`search_path = ''`; execute só pra `authenticated`.

| Função | Quem | Devolve |
|---|---|---|
| `cic_vendedor_mes(p_mes)` | admin: todos os vendedores ativos; vendedor: só ele; sem perfil: vazio | por vendedor: vendas (qtd, líquido, bruto), reembolsos do mês (qtd, líquido), líquido final, nível/%/comissão e falta pro próximo (`cic_comissao`), contatos em "2. Em Contato", conversão e alvo |
| `cic_meta_mes(p_mes)` | só admin (senão erro 42501) | jsonb: líquido comercial final, vendas, reembolsos, primeira venda, dias úteis (mês, decorridos, restantes), projeção, `metas[]` (% , falta, falta por dia útil), `serie[]` diária com acumulado |
| `cic_home(p_inicio, p_fim)` | só admin (senão erro 42501) | jsonb, só comercial: `periodo`, `dia_hoje`, `dia_ontem` (bruto, líquido, reembolso, líquido após reembolso, vendas, tickets, leads, Em Contato, conversão), `plataformas[]` (hoje só Hubla; TMB entra depois), `produtos[]` com `ofertas[]` (qtd, líquido, % do total, tickets), `matriz` (mês da data final: `dias[]` com `util`/`feriado`/`parcial` e `total` com pessoas únicas do mês) |

| `cic_lista_vendas(p_inicio, p_fim)` | admin: todos os vendedores; vendedor: só as dele; sem perfil: vazio | uma linha por venda válida com vendedor: data e hora (SP), cliente, telefone (`+55...`), vendedor, produto, oferta, bruto, líquido, reembolsada e data do reembolso; mais recente primeiro |
| `cic_lista_reembolsos(p_inicio, p_fim)` | idem | uma linha por reembolso efetivado de venda com vendedor: data do reembolso e da venda, cliente, telefone, vendedor, produto, líquido abatido |

| `cic_desempenho(p_inicio, p_fim, p_vendedor)` | só admin | por vendedor ativo: vendas e líquido (Hubla), nível/comissão do mês de `p_inicio`, entradas por etapa 0 a 4, perdas comerciais, contatos, conversão, mensagens e templates do vendedor |
| `cic_taxa_passagem(p_inicio, p_fim, p_vendedor)` | só admin | por etapa 0 a 4: entraram, passaram (etapa posterior ou venda), %, perdidos parados, vendas, abertos; `p_vendedor` = slug, `_sem` ou nulo (time) |
| `cic_motivos_perda(p_inicio, p_fim, p_vendedor)` | só admin | linhas por tipo (comercial/cs), grupo, motivo, vendedor e etapa da perda, com quantidade |
| `cic_ciclo_venda(p_inicio, p_fim, p_vendedor)` | só admin | por tipo (venda/perda) e vendedor, mais a linha `_time`: casos, mediana e média em horas, faixas (até 1 dia, 1 a 3, 3 a 7, mais de 7) e `sem_historico` (desfecho a menos de 6 min da entrada, fora da conta) |

| `cic_mensageria(p_inicio, p_fim)` | só admin | jsonb: `resumo` (entregues, lidos, falhas, taxas, custo total com franquia, custo por origem, serviço bruto, franquia, custo por venda), `por_categoria`, `broadcasts`, `automacoes`, `vendedores`, `copy`, `preco` (fonte e vigência) |

Regras das telas de gestão em `contrato-dados.md` (unnichat_eventos) e `escopo.md`.

Só comercial em todas as RPCs, inclusive pro admin; orgânico fica no banco pra lista
e análise (05/11/2026).

Internas, sem acesso do app: `cic_kpis_comercial`, `cic_preco_whatsapp`, `cic_servico_dia`, `cic_negocios`, `cic_fone_chave`, `cic_fone`, `cic_vendas_validas`, `cic_reembolsos_validos`,
`cic_contatos_em_contato` (todas por período `p_inicio, p_fim`).

Trava (`trg_hubla_vendas_trava_paga`): linha `paid` só aceita virar `refunded`,
`chargeback` ou `chargedback`, e aí muda só `status`, `event_type` e
`invoice_modified_at`. Qualquer outra atualização de linha paga é ignorada; linha
refunded/chargeback não muda mais. Overdue/unpaid virando paid continua passando.

## Tabelas de cadastro

| Tabela | Chave | Conteúdo atual |
|---|---|---|
| `cic_config` | `chave` | slug, nome, fuso, `tmb_fator_valor` = 0,5 (provisório), `utm_vendedor` (utm_source + `comercial_`), `conversao_alvo` (15% a partir da etapa 2) |
| `vendedores` | `utm_slug` | 4 vendedores (`comercial_nome-sobrenome`, igual ao `utm_source` dos links) |
| `links_venda` | `id` | link base por oferta. Ativos: Ultra Black 2026 (Aluno, Não Aluno), Meal Prep Express (397) e Meal Prep Express + Regina IA (497); todos Hubla. O link de cada vendedor (com os cupons) sai de `cic_meus_links()`; vendedor inativo não recebe link |
| `links_venda_cupons` | `id` (único `link_id, cupom`) | cupons de cada link, vários por link, com `desconto`, `ordem` e `ativo`. Hoje: 5OFF (5%) e 10CONTO (10%) no Ultra Black; DEZCONTO (10%) no Meal Prep |
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

-- Cupom novo em todos os links ativos de um produto (entra depois dos que já existem)
insert into links_venda_cupons (link_id, cupom, desconto, ordem)
select l.id, 'NOVO10', '10%', coalesce((select max(c.ordem) from links_venda_cupons c where c.link_id = l.id), 0) + 1
from links_venda l where l.produto = 'Ultra Black 2026' and l.ativo
on conflict (link_id, cupom) do nothing;

-- Tirar um cupom de circulação (some da Minha página na hora, sem apagar)
update links_venda_cupons set ativo = false
where cupom = 'NOVO10' and link_id in (select id from links_venda where produto = 'Ultra Black 2026');

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
