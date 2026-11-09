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
  `comercial_nome-sobrenome`, com sublinhado depois de "comercial" (ajustado em
  04/11/2026 pro padrão dos links que o time já usa). Variação de `_`/`-` e de
  maiúscula é tolerada na identificação.
- Links de venda (Hubla): Ultra Black 2026 (Aluno e Não Aluno) e Meal Prep Express +
  Regina IA (Oferta, desde 05/11/2026). O CIC monta o link de
  cada vendedor com o `utm_source` dele e mostra na Minha página, com botão de copiar.
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

### CIC fase 1: números (decidido em 05/11/2026)

- Venda válida: foi paga um dia (`status` paid, refunded, chargeback ou chargedback),
  data = `sale_date` em São Paulo. Overdue e unpaid ficam fora até pagar.
- Venda paga não regride nem é reescrita (trava no banco, 0012/0013): só pode virar
  refunded/chargeback, e aí muda só status e data; valores e UTM ficam os originais.
  Nenhuma linha é criada ou corrigida à mão.
- Valor: líquido (`seller_net_cents`). Bruto só como informação.
- Vendedor: `cic_vendedor_de_utm(utm_source)`; sem vendedor = orgânico.
- Meta do mês e comissão: só vendas com vendedor, sobre o líquido final (vendas menos
  reembolsos do mês). Ultra Black e Meal Prep contam igual.
- Dash mostra só o comercial em todas as telas, inclusive pro admin. Orgânico e
  reembolso de orgânico ficam no banco pra lista e análise, fora do dash (05/11/2026).
- Relatórios = lista de vendas pra conferência (o time não acessa a Hubla): nome e
  telefone do cliente aparecem só nela e na tela de Reembolsos. Vendedor vê só as dele.
- Reembolso: `invoice.refunded` em `hubla_reembolsos` (aceito não quer dizer
  realizado) OU a venda com status refunded/chargeback (o webhook de Vendas é o que
  chega hoje). Um por fatura; data = `refunded_at`, senão `invoice_modified_at`. Abate
  no mês do reembolso, do vendedor da venda original, pelo líquido da venda. Sem venda
  paga no banco, não há reembolso.
- Conversão: vendas pagas com vendedor ÷ contatos distintos (telefone) que entraram em
  "2. Em Contato" no período. Por vendedor: proprietário do card = `vendedores.nome`.
- Projeção do mês: ritmo por dia útil contado desde o dia da primeira venda paga do mês
  (hoje incluso), projetado até o fim do mês. Falta por dia útil usa os dias úteis
  depois de hoje.

## Home (decidido em 06/11/2026)

- Só comercial, com filtro de período (padrão: mês atual).
- Venda válida = foi paga um dia (0013), no dia do pagamento em SP; valor = líquido.
  Reembolso abate no dia do reembolso ("após reembolso" = líquido − reembolsos do período).
- Pessoa = telefone pela chave DDI + DDD + últimos 8 dígitos. Leads = pessoas únicas que
  entraram em "0. Base/Entrada"; Em Contato = em "2. Em Contato". Conversão = vendas ÷
  Em Contato, limitada a 100%. A mesma chave vale na conversão da Minha página, Meta do
  mês e Desempenho.
- Cards: faturamento bruto, líquido (e após reembolso), vendas, ticket bruto e líquido,
  conversão (com Em Contato e Leads), faturamento por plataforma (hoje só Hubla; TMB
  entra depois) e reembolso. Cada card tem a faixa HOJE (parcial) e ONTEM, que ignora o
  filtro.
- Venda por produto: vendas e líquido com % do total do período, tickets, e a quebra por
  oferta.
- Dia a dia: mês da data final do filtro, dias até hoje + TOTAL. Fim de semana e feriado
  pela `dim_calendario`; hoje marcado como parcial. TOTAL = pessoas únicas do mês e razão
  dos totais. Sem Discadora (Callix fora do escopo).
- Menu lateral recolhível (só ícones), estado guardado no navegador; sem storage, abre
  expandido. No celular segue o menu atual.

## Meta do mês: burn-up e funis (decidido em 06/11/2026)

- Burn-up: bronze, prata (meta oficial, tracejada) e ouro acumulados = meta ÷ dias úteis
  do mês × dias úteis acumulados (`dim_calendario`; plana em fim de semana e feriado).
  Realizado acumulado = líquido de vendas − reembolsos (mesma régua da Meta), até hoje.
  Sombreado = o que falta pra Prata.
- Matriz por funil, só Realizado (Meta e Δ entram quando houver meta por funil).
  "Dias + semanas" ou "Só semanas" (semana de segunda a domingo, cortada no mês; subtotal
  recalcula pessoas únicas).
- Funil = `unnichat_eventos.origem` (vazio = "Sem origem"). Lead e Em Contato contam no
  funil do próprio evento. Venda (só comercial) vai pro funil da origem mais recente da
  pessoa antes da compra (telefone DDI + DDD + 8); sem evento antes vai pro funil padrão
  (`cic_config.funil_padrao`, hoje "Disparos BF26"; antes de 09/11 era "Sem funil").
  "Sem origem" só aparece para eventos de 07/11 em diante (os anteriores foram corrigidos
  no banco em 09/11).
  Crédito único por venda. TOTAL: Leads = soma dos funis; Em Contato = pessoas únicas.
- Saíram da Meta do mês o gráfico por dia e o ranking dos vendedores.
- Pendente (Nirla): origem vazia em ~60% dos eventos e vendas sem evento no CRM antes da
  compra; ajuste na fonte (Unnichat).

## Ofertas e cupons vigentes (06/11/2026)

Links de venda na Minha página, cada um com o cupom e botão de copiar
(`links_venda`, `links_venda_cupons`, `cic_meus_links()`). Um link pode ter vários cupons:

| Produto | Oferta | Cupom |
|---|---|---|
| Ultra Black 2026 | Aluno | 5OFF (5%) e 10CONTO (10%) |
| Ultra Black 2026 | Não Aluno | 5OFF (5%) e 10CONTO (10%) |
| Meal Prep Express | 397 | DEZCONTO (10%) |
| Meal Prep Express + Regina IA | 497 | DEZCONTO (10%) |

## Mensageria: custo de WhatsApp (decidido em 05/11/2026)

- Escopo comercial: broadcasts com nome `COMERCIAL...`, automações das pastas coletadas
  (CHECKOUT, BANCO DE EVENTOS e GERAL, todas dentro da pasta comercial) e vendedores do
  cadastro. Conexão 0209.
- Custo é ESTIMATIVA pelo rate card (`whatsapp_preco`, preço vigente na data); a fatura
  do Unnichat é a referência final. A Meta cobra na entrega.
- Template: entregues x preço da categoria (broadcast pelo `template_id`, automação pelo
  node, vendedor por `tpl_vendedor_utl`/`_mkt`).
- Serviço (mensagem que não é template): R$ 0,035 por mensagem. Vendedor =
  `msg_vendedor` + `msg_agendada`; broadcast = respostas `srv_entregues`; automação =
  nodes sem template. Franquia de 1.000 por número por mês, desconto no total do mês
  (não rateado), aplicada às primeiras 1.000 do mês, dia a dia.
- Automações: volume do período = última foto no período - última foto antes dele; sem
  foto anterior, conta o acumulado da primeira foto.
- Cliques (06/11): só automações, `clicks.uniqueClicks` da foto horária, pela diferença
  das fotos no período. % = cliques ÷ entregues dos passos que têm botão. Broadcast mostra
  "–": a API do Unnichat não informa cliques de broadcast.
- Bloqueios (06/11): `unnichat_blocklist.bloqueado_em` no período; % sobre templates
  entregues. Copy do bloqueio = última `codigo_copy` da pessoa no CRM antes do bloqueio.
- Custo por dia (06/11): barras por origem (broadcast pela data do disparo, automação pela
  diferença das fotos do dia, vendedor por `unnichat_conversas_dia`, coletado às 23:40) e
  linha de templates entregues. Bruto, antes da franquia.
- Campanha (06/11): nome do broadcast sem o prefixo `COMERCIAL_`/`[COMERCIAL]` e sem o
  sufixo `_<n>_LT<n>`. Lotes = os broadcasts da campanha, com data e hora do disparo.
  Leads (E0) e em contato (E2) = pessoas únicas no CRM com a copy igual à campanha; venda
  e bloqueio pela última copy antes do fato. Substitui o painel "Por código de copy".
- Família de automação (06/11): copy sem o número de versão final (`_1.0.1`), só copies
  que não são campanha de broadcast. Mesmas métricas de CRM da campanha.
- Leads etapa 0 no resumo (09/11): pessoa única (`pessoa_chave`) que entrou em
  "0. Base/Entrada" no período com copy de campanha de broadcast do período ou de família de
  automação (mesma regra das tabelas). % = leads ÷ templates entregues de broadcasts +
  automações. Custo por lead E0 = custo de broadcasts + automações ÷ leads (vendedor fica
  de fora, é depois do lead); sem lead, "–". A soma das campanhas e famílias pode passar o
  total do resumo: quem passou por mais de uma copy conta uma vez no resumo.
- Campanhas (09/11): entregues e falhas com % sobre contatos (também nos lotes); leads E0
  com % sobre entregues; coluna Custo/lead E0 = custo da campanha ÷ leads E0.

## Filtros de data, Taxa de passagem por origem e Motivos de perda (decidido em 09/11/2026)

- Filtro de data (todas as telas com De/Até): presets Hoje, Ontem, Essa semana (segunda até
  hoje), Semana passada (segunda a domingo anteriores), Esse mês (dia 1 até hoje) e Mês
  passado (mês anterior inteiro). O preset ativo fica destacado; editar a data na mão
  desmarca. O "até" nunca passa de hoje (São Paulo).
- Taxa de passagem: funil geral e um quadro por origem (Disparos BF26, Recuperação BF26,
  Sem origem e outras, por volume de negócios), com a mesma contagem do funil geral
  particionada pela origem do negócio (último evento do negócio com origem). Venda pela
  origem do lead antes da compra; venda sem lead no funil padrão. Origem sem negócio no
  período não aparece. A soma das origens é o funil geral.
- Conversão etapa 2 > venda = vendas comerciais ÷ pessoas únicas (pessoa_chave) que
  passaram por "2. Em Contato" no período (origem do evento). No geral é a mesma conversão
  da Home.
- Motivos de perda: os motivos do grupo cs (Detrator/Blocklist, Reembolso/Cancelamento) são
  registrados pelo comercial e contam como motivo normal em toda a tela, sem separação.
  Todos os gráficos são pizza (donut), top 6 + "Outros motivos", legenda com motivo, qtd e
  %. Cards "Motivo de perda por origem" e "Motivos por vendedor" (total, % sobre o total
  do período, pizza); vendedor inativo aparece se tiver perda; perdas sem dono ficam em
  "Sem vendedor". Etapa da perda em pizza na ordem das etapas. Nas outras telas (Taxa de
  passagem, Ciclo, Desempenho) a perda comercial continua sem o grupo cs.
- Taxa de passagem e Motivos de perda seguem só para admin (vendedor recebe 42501).

## Regras gerais de contagem (decidido em 06/11/2026, auditoria)

- PADRÃO PARA QUALQUER TELA (09/11): venda = venda comercial válida na Hubla (paga, ou
  paga e depois reembolsada, regra da 0013), com vendedor pelo `utm_source` e crédito pelo
  utm, nunca pelo dono do negócio no CRM. Venda orgânica não entra em tela de CRM nem de
  gestão. Nas telas de CRM a venda é casada com o negócio da pessoa (último evento com
  negócio antes da compra) e com a etapa em que ele estava na compra (`cic_vendas_crm`).
  Venda sem negócio no CRM antes da compra: na Taxa de passagem fica numa linha à parte
  ("Sem negócio no CRM antes da venda"); no Ciclo entra em "sem histórico".
  Na Taxa de passagem, "Passaram" e "Abertos" também consideram só a venda comercial
  casada com o negócio.
- Rótulos: na Taxa de passagem, "Negócios que entraram" (um negócio por entrada no CRM; a
  mesma pessoa pode ter mais de um). Leads da Home = pessoas únicas pelo telefone.

- Ganho e perda contam por negócio: um `negocio_id` com o mesmo won/lost repetido (a
  automação do Unnichat dispara de novo, segundos depois) vale uma vez, pelo evento mais
  antigo, inclusive o motivo da perda. Linha bruta não é apagada. Ganho é sempre a venda
  paga na Hubla; nenhuma tela conta o status won do CRM.
- Dias úteis: toda conta "por dia útil" (média de vendas por dia, projeção da Meta do mês e
  da Minha página, reta das metas no burn-up, tendência) conta dias úteis a partir da 1ª
  venda comercial do mês. Em novembro/2026 a 1ª venda foi em 04/11, então 03/11 não conta.
  Mês ainda sem venda comercial: nada decorrido e projeção vazia; a reta da meta usa o mês
  inteiro.
- Vendedor inativo com atividade no período (evento de CRM, conversa ou venda) aparece no
  Desempenho, na Taxa de passagem (filtro), em Motivos de perda e no Ciclo, com a etiqueta
  "inativo". Continua sem link de venda e sem login.
- Mensageria: vendedor inativo que teve conversa no período entra no custo de vendedor, no
  custo por dia e na tabela de vendedores, com a etiqueta "inativo" (o custo existe do
  mesmo jeito).

## Desempenho individual e Minha página (decidido em 06/11/2026)

- Desempenho individual (só admin): tabela por vendedor ativo ordenada pelo faturamento
  líquido das vendas no período; medalha nos 3 primeiros, "#n" nos demais; selo "The King"
  só no 1º e só com faturamento > 0; participação = % do faturamento do time.
- Card por vendedor: faturamento, conversão (vendas ÷ Em Contato), Leads (negócios que
  entraram na base), Em Contato (pessoas únicas), LRT, leads em contato por venda, vendas,
  ticket médio e média de vendas por dia útil decorrido no período. Sem Discadora.
- LRT: minutos entre a última entrada em etapa anterior (Base ou Discadora) e a primeira
  entrada em "2. Em Contato" do mesmo negócio, com essa entrada no período. Crédito pro
  proprietario do evento de Em Contato (sem ele, o dono do negócio). Negativo ou sem etapa
  anterior fica de fora. Mediana; a dica mostra quantos passaram de 24 h.
- Minha página: gráfico do faturamento da comissão acumulado no mês (vendas − reembolsos
  por dia, a régua da comissão), projeção pelo ritmo de dia útil (realizado ÷ dias úteis
  decorridos × dias úteis do mês) e linhas tracejadas dos níveis que cabem até 1,15 × o
  maior entre realizado e projeção (os de fora aparecem numa nota).
- Insights (no máximo 3, nessa ordem): conversão abaixo do alvo (vendas a mais =
  (alvo − conversão) × Em Contato), ticket líquido abaixo do alvo, faltando até 15% pro
  próximo nível, tendência (queda ≥ 10% em conversão, ticket ou vendas por dia útil contra
  o mês anterior cortado no mesmo dia; só a partir de dezembro/2026). Alvos em
  `cic_config` (`conversao_alvo` e `insights`), nunca no código.

## Comissão do vendedor (decidido em 04/11/2026)

Base: faturamento LÍQUIDO individual no mês (vendedor = `utm_source`). Todos os
produtos contam igual pra meta e comissão (Ultra Black e Meal Prep, decidido em
05/11/2026).

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
- [ ] Mensageria: conferir o custo estimado (`cic_mensageria`) contra a primeira fatura do Unnichat.

### Pendente de teste e validação (n8n e Unnichat, criados às pressas em 04/11)
- [ ] Token errado nos webhooks: confirmar o status real (doc assume 403) com curl.
- [x] Blocklist: primeiras execuções reais ok em 05/11 (token validado).
- [ ] Custo de mensagens: conferir a view de custo contra a primeira fatura do Unnichat.
- [ ] Eventos CRM: conferir o primeiro evento real de cada uma das 7 automações
  `[EVENTO]` (header, `Acao` de Ganho e Perdido, campos que chegam).
- [ ] Eventos CRM: validar se `eventDate` é o momento do evento. Se não for, decidir
  entre hora do recebimento e outra fonte (efeito na chave em contrato-dados.md).
- [ ] Eventos CRM: ver se o payload real traz id único do evento pra virar chave.
- [ ] Hubla Reembolsos: validar os eventos `refund_request.*` no primeiro reembolso real
  (o teste do painel só mandou `invoice.refunded`).
- [ ] Hubla Vendas: conferir `payer_documento` na primeira venda real (teste não trazia).
- [ ] Hubla > Unnichat: as URLs `/a/start/...` dos fluxos ficam só no nó do n8n; no export
  do repo viram `<URL_UNNICHAT_...>`. Gambiarra por prazo: mover pra credencial ou
  variável do n8n.
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
