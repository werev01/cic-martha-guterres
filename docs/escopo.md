# Escopo do CIC Martha Guterres (MVP)

Fonte da verdade sobre telas, perfis e decisões do projeto. Antes de propor qualquer
coisa, leia este documento. Mudou decisão? Atualize aqui no mesmo commit.

Última atualização: 03/11/2026

## Contexto

- Operação de Black Friday da Martha Guterres. Abertura de carrinho em 04/11/2026,
  Black Friday em 27/11/2026. Depois segue como operação contínua.
- Uma segunda operação (outro cliente, conta própria no Unnichat) será plugada no
  mesmo app depois. Por isso, tudo que é do cliente fica numa config isolada e nada
  da Martha entra hardcoded na lógica.
- Este projeto é a base do modelo padrão do CIC para as próximas operações (ver
  "Modelo para próximas operações" no fim).

## Recursos (trava de isolamento)

| Recurso | Identificador |
|---|---|
| Repositório | `werev01/cic-martha-guterres` |
| Publicação | GitHub Pages do repo, sem domínio próprio por enquanto |
| Supabase | project ref `zrvrfxhzwzumvetgjure` (organização WeRev, sa-east-1) |
| n8n (cloud, compartilhado) | pasta `cic-martha-guterres`, workflows com prefixo `[MARTHA]` |
| Unnichat | conta própria da Martha |
| Slug do cliente | `martha-guterres` (sempre com sobrenome) |

Auth do Supabase: cadastro aberto desligado; Site URL aponta pro GitHub Pages do repo.

## Fontes de dados

| Fonte | O que entrega |
|---|---|
| Unnichat | eventos de CRM (etapas, motivos de perda, vendedor), disparos e conversas, com "Código Copy" |
| Callix | discadora: ligações, usuários/agentes, qualificações, resumos por hora |
| Hubla | vendas, reembolsos, carrinho abandonado, cartão recusado |
| TMB | vendas e reembolsos/cancelamentos (a operação também vende por lá) |

Detalhe de tabela, campo e chave única de cada fonte: `docs/contrato-dados.md`.

## Telas do MVP

Só entram as telas abaixo. Nada de copiar a estrutura do G2. A coluna "Referência no
G2" diz qual aba do `werev01/cic-g2` serve de base (ver `docs/referencia-g2.md`).

| # | Tela | Referência no G2 | Fica de fora |
|---|---|---|---|
| 1 | Home | `home` | |
| 2 | Meta do mês | `metadomes` | |
| 3 | Mensageria | `infraestrutura` | |
| 4 | Discadora | `discadora` | gráfico "Velocidade de atendimento ao lead" |
| 5 | Desempenho individual | `vendedores` | "Análise por Vendedor"; "Rondas do Dia" |
| 6 | Minha página | `minhapagina` | Bônus; Evolução e Comparativo (a Régua de níveis VOLTA, com a régua de comissão abaixo) |
| 7 | Relatórios | `relatorios` | |
| 8 | Taxa de passagem | `taxapassagem` | "O que fica e o que sai · equipe"; "Análise Inteligência Comercial WeRev"; "Conversão Real por vendedor"; "Conversão real do recorte"; "Evolução no tempo"; "Quantos leads/hora pra fazer 2 vendas/hora?" |
| 9 | Motivos de Perda | `motivosperda` | |
| 10 | Ciclo de Vendas | `ciclovenda` | |
| 11 | Reembolsos | `reembolsos` | |

Abas do G2 que NÃO entram: Recordes, Times, Faturamento, Evolução, Regras, Rotina,
Processos.

## Perfis

| Perfil | Menus | Dados |
|---|---|---|
| Admin | todos | todos os projetos/clientes |
| Vendedor | Minha página, Relatórios e Reembolsos (definido em 04/11/2026) | só o projeto em que atua e só os próprios números; se atua em dois, vê as duas views |

Regras:
- Login por e-mail e senha. Só a equipe WeRev cria usuários. Antes de criar qualquer
  usuário, pedir o e-mail ao Nirla.
- Cada operação tem seu próprio Supabase. Vendedor em dois projetos tem cadastro nos
  dois, com o mesmo e-mail, e o app mostra um seletor de projeto depois do login.
- Só Nirla e Mitsuo acessam as ferramentas (Supabase, n8n, GitHub, Unnichat). O resto
  acessa só o CIC.

## Decisões fechadas

- Camadas do banco: bruto (alimentado pelo n8n) -> tratado (views) -> app.
- Tabelas brutas sem permissão pro app; o app lê só views/tabelas tratadas, via RLS.
- Toda tabela bruta tem chave única, pro n8n fazer upsert sem duplicar.
- O front usa só a chave pública. A service role fica só nas credenciais do n8n.
- Disparos usam o campo "Código Copy" do Unnichat; a coluna `codigo_copy` existe desde
  a tabela bruta.
- Views de trabalho e diagnóstico ficam no schema `tmp_claude`, com validade de 12h e
  limpeza automática.
- Workflows do n8n criados do zero (não duplicar nem ler os do G2). Padrões em
  `docs/padroes-n8n.md`.
- O app não baixa tabela inteira no navegador: agrega no banco e pagina (armadilha
  vista no G2, ver `docs/referencia-g2.md`).

- Atribuição de venda ao vendedor: sempre pelo `utm_source`, padrão
  `comercial-nome-sobrenome` (decidido em 03/11/2026).
- Campanhas da Martha na Callix seguem o prefixo `[MARTHA]` no nome; é por ele que o
  n8n filtra.
- Metas de novembro/2026: bronze R$ 100 mil, prata R$ 150 mil, ouro R$ 200 mil.
- Conversão alvo: 15% de "2. Em Contato" para venda.
- Etapas do CRM: 0. Base/Entrada, 1. Discadora (Sem Resposta), 2. Em Contato,
  3. Negociação, 4. Forecast. Motivos de perda: 11, agrupados pelo código entre
  colchetes ([1] a [4] e [cs]). Cadastro em `docs/banco.md`.
- Blocklist do Unnichat entra no Supabase (`unnichat_blocklist`); a configuração no
  Unnichat fica com o Nirla.
- Metas são sobre faturamento LÍQUIDO (descontando reembolso), decidido em 04/11/2026.
- Publicação: a pasta `app/` sai no GitHub Pages por GitHub Actions
  (`.github/workflows/pages.yml`). Visual segue `docs/marca.md`; sem emoji.
- Acesso: convite pelo Supabase (Authentication > Users > Invite user). O link cai na
  tela "Defina sua senha" do CIC.
- Usuários: admins Matta, Nirla, Mitsuo e Godoy; vendedores Daniele Silva, Henrique
  Cabral, Lorena Ruas e Gabriel Poloni. Primeiros logins criados: Nirla e Mitsuo.
- Callix: conta da WeRev, compartilhada entre operações. Cada workflow filtra pelas
  campanhas da operação antes de gravar (ver `contrato-dados.md`).
- TMB: venda entra a 50% do valor, PROVISÓRIO até o Nirla definir. Fica como parâmetro
  da config do cliente; a bruta guarda o valor cheio.

## Comissão do vendedor (decidido em 04/11/2026)

Base: faturamento LÍQUIDO individual no mês (vendedor = `utm_source`).

| Nível | Faturamento líquido no mês | % |
|---|---|---|
| 1 | até R$ 45.000 | 1% |
| 2 | de R$ 45.000,01 a R$ 70.000 | 1,5% |
| 3 | acima de R$ 70.000 | 2% |

- A % do nível atingido vale **sobre o total** (ex.: R$ 80 mil = 2% de 80 mil =
  R$ 1.600). Atenção ao degrau: R$ 70.000 paga R$ 1.050 e R$ 70.000,01 paga R$ 1.400.
- Vale de novembro/2026 em diante, igual pra todos os vendedores.
- Faturamento líquido:
  - Hubla: valor líquido do vendedor (`seller_net`, já sem a taxa da Hubla);
  - TMB: valor x fator da config (0,5 provisório) ou o líquido da TMB, se vier no
    payload;
  - reembolso abate no mês em que acontece, não no mês da venda (mês fechado não
    muda).
- Onde aparece:
  - Minha página (vendedor): régua de níveis com faturamento líquido do mês, nível
    atual, quanto falta pro próximo e comissão estimada;
  - Desempenho individual (admin): a mesma conta pra todos os vendedores.
- Bônus continua fora.
- Banco: `comissao_faixas` (faixas por vigência) + `cic_config.comissao_regra` +
  função `cic_comissao(faturamento, mês)`.

## Em aberto

- [ ] Regra definitiva do valor TMB (hoje 50%). Cobrar o Nirla.
- [ ] Criar os usuários de Matta, Godoy e dos 4 vendedores (perfis já cadastrados).

### Pendente de teste e validação (n8n e Unnichat, criados às pressas em 04/11)
- [ ] Token errado nos webhooks: confirmar o status real (doc assume 403) com curl.
- [ ] Blocklist: conferir a primeira execução real (header `x-cic-token` no Unnichat
  não foi testado; se errar, o POST falha antes do opt-out).
- [ ] Eventos CRM: conferir o primeiro evento real de cada uma das 7 automações
  `[EVENTO]` (header, `Acao` de Ganho e Perdido, campos que chegam).
- [ ] Eventos CRM: validar se `eventDate` é o momento do evento. Se não for, decidir
  entre hora do recebimento e outra fonte (efeito na chave em contrato-dados.md).
- [ ] Eventos CRM: ver se o payload real traz id único do evento pra virar chave.
- [ ] Eventos CRM: apagar a linha de teste (`raw_payload->'data'->>'id' = 'teste-cic-evt-001'`)
  com aval.

## Ordem de execução

1. Docs (este, `padroes-n8n.md`, `referencia-g2.md`) e estrutura do repo.
2. Contrato de dados (etapa 6) junto com as tabelas brutas, pra ligar o n8n em 04/11.
3. Resto do banco: tratadas, views, perfis, vínculo vendedor x projeto, RLS,
   `tmp_claude`.
4. Login e usuários de teste (pedindo e-mail antes).
5. App com as 11 telas, menus por perfil, config isolada, deploy no GitHub Pages.
6. Teste ponta a ponta: registro de teste em cada bruta, conferir no CIC, validar RLS
   com vendedor.

## Modelo para próximas operações

- Tudo que for genérico nasce parametrizado; o que é do cliente fica na config isolada.
- O modelo sai do que foi montado e validado aqui, não do G2.
- Depois de 27/11, extrair um repo modelo (ex.: `werev01/cic-template`) com migrations
  base, app, padrões do n8n, contratos de dados e um `PLAYBOOK.md` de como plugar uma
  operação nova. Criar esse repo só com aval.
