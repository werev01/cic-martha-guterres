# Banco do CIC Martha Guterres

Mapa do que existe no Supabase (`zrvrfxhzwzumvetgjure`) e como mexer no dia a dia.
Toda mudança de estrutura vira migration em `supabase/migrations/`.

Última atualização: 04/11/2026

## Camadas

| Camada | O que é | Quem lê |
|---|---|---|
| Bruta | 19 tabelas alimentadas pelo n8n (`hubla_*`, `tmb_*`, `unnichat_*`, `callix_*`). Contrato em `contrato-dados.md` | ninguém do app (RLS sem policy, sem grant) |
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

## Tabelas de cadastro

| Tabela | Chave | Conteúdo atual |
|---|---|---|
| `cic_config` | `chave` | slug, nome, fuso, `tmb_fator_valor` = 0,5 (provisório), `utm_vendedor` (utm_source + `comercial-`), `conversao_alvo` (15% a partir da etapa 2) |
| `vendedores` | `utm_slug` | 4 vendedores (`comercial-nome-sobrenome`) |
| `perfis` | `email` | 4 admins + 4 vendedores; `user_id` se preenche sozinho quando o usuário é criado no Auth |
| `perfil_menus` | `papel, menu` | admin: 11 menus; vendedor: minhapagina, relatorios, reembolsos |
| `crm_etapas` | `ordem` | 0 a 4, com o nome exato do Unnichat |
| `motivos_perda` | `nome_unnichat` | 11 motivos, grupo = código entre colchetes |
| `metas` | `mes, nivel` | nov/2026: bronze 100k, prata 150k, ouro 200k |
| `dim_calendario` | `data` | nov e dez/2026; dia útil = seg a sex sem feriado nacional (19 em novembro) |

## Funções de papel

`cic_meu_papel()`, `cic_eh_admin()`, `cic_meu_vendedor()`: leem o perfil do usuário
logado. São `security definer` e chamáveis por usuário logado (o advisor do Supabase
avisa; é intencional, só devolvem dados do próprio usuário). anon não chama.

## Operações do dia a dia (SQL Editor)

```sql
-- Novo vendedor: cadastro + perfil (o vínculo com o login é automático pelo e-mail)
insert into vendedores (utm_slug, nome, email) values ('comercial-nome-sobrenome', 'Nome Sobrenome', 'email@x.com');
insert into perfis (email, nome, papel, vendedor_slug) values ('email@x.com', 'Nome Sobrenome', 'vendedor', 'comercial-nome-sobrenome');

-- Desligar alguém (perde o acesso na hora, sem apagar histórico)
update perfis set ativo = false where email = 'email@x.com';

-- Meta de um mês novo
insert into metas (mes, nivel, valor) values ('2026-12-01','bronze',0), ('2026-12-01','prata',0), ('2026-12-01','ouro',0);

-- Liberar mais um menu pro vendedor
insert into perfil_menus (papel, menu, ordem) values ('vendedor', 'desempenho', 4);

-- Mudar o fator da TMB
update cic_config set valor = '1', atualizado_em = now() where chave = 'tmb_fator_valor';
```

## tmp_claude

- View temporária sempre com comentário `expira_em=<timestamptz ISO sem espaço>`,
  ex.: `comment on view tmp_claude.x is 'expira_em=2026-11-04T22:00:00-03'`.
- Job `limpar-views-tmp-claude` (pg_cron, todo HH:05) apaga as vencidas e as sem
  carimbo.
