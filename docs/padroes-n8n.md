# Padrões do n8n (CIC Martha Guterres)

Vale pra todo workflow da operação. Se um caso não estiver coberto aqui, pergunte
antes de inventar e registre a decisão neste arquivo.

Última atualização: 13/11/2026

## Onde fica

- Instância: n8n self-hosted na VPS da TurboCloud, URL base `https://n8n.werev.com.br`.
  Não há projetos de equipe: tudo fica no projeto pessoal
  `Nirlando Junior <ferramentas@werev.com.br>`.
- Edição: Community registrada (chave gratuita, em Settings > Usage and plan). Sem o
  registro, a instância não tem pastas. Numa VPS nova, registrar antes de criar
  workflows.
- Pastas: uma por operação, com o nome do repo (`cic-martha-guterres`,
  `cic-vanessa-oliveira`), na raiz do projeto pessoal. Todo workflow da operação mora
  na pasta dela. Mover workflow de pasta não muda id, path de webhook nem status ativo.
- Workflows criados do zero. Não duplicar nem importar workflow de outra operação.

## Nome dos workflows

Formato: `[MARTHA] <Fonte> · <Função>`

Exemplos:
- `[MARTHA] Hubla · Vendas`
- `[MARTHA] Hubla · Reembolsos`
- `[MARTHA] Hubla · Carrinho`
- `[MARTHA] Unnichat · Eventos CRM`
- `[MARTHA] Unnichat · Coleta de broadcasts`
- `[MARTHA] Unnichat · Coleta de automações`
- `[MARTHA] Erros`

Fonte com inicial maiúscula, função curta e no plural quando fizer sentido.

## Tags

Todo workflow leva:
- `martha` (obrigatória, identifica o cliente);
- uma de fonte: `fonte:unnichat`, `fonte:hubla`;
- uma de tipo: `tipo:webhook` (recebe push), `tipo:agendado` (puxa por cron),
  `tipo:manual` (roda só pelo editor, fica desativado) ou `tipo:erro`.

## Credenciais

Nunca compartilhar credencial com outra operação.

| Credencial | Tipo no n8n | Uso |
|---|---|---|
| `[MARTHA] Supabase service role` | Supabase API (chave `service_role` legada, JWT) | gravar nas tabelas brutas |
| `[MARTHA] Unnichat MG0209` | Header Auth (token da conexão 0209) | chamadas à API do Unnichat (coletas e eventos) |
| `[MARTHA] Unnichat MG8538` | Header Auth (token da conexão 8538) | sem uso por enquanto |
| `[MARTHA] Hubla` | Header Auth | validar o token do webhook / chamadas à API |
| `[MARTHA] E-mail alertas` | Gmail OAuth2, autorizado com `mitsuo@werev.com.br` | workflow de erro (envia para o grupo `ferramentas@werev.com.br`) |
| `[MARTHA] Webhook token` | Header Auth (`x-cic-token`) | validar webhooks chamados pelo Unnichat |

Credencial do Unnichat é uma por conexão, no padrão `[CLIENTE] Unnichat <iniciais><final da
conexão>` (ex.: `[MARTHA] Unnichat MG0209`). Trocar o token não muda o id da credencial,
então os workflows não precisam ser editados.

Regra: chave e token só dentro de credencial. Nunca colar chave em header, URL ou
campo de nó (isso vaza no export do JSON).

## Webhooks

URL completa: `https://n8n.werev.com.br/webhook/<slug>/<fonte>/<evento>`
(slug da Martha: `martha-guterres`).

| Workflow | Path |
|---|---|
| `[MARTHA] Hubla · Vendas` | `/webhook/martha-guterres/hubla/vendas` |
| `[MARTHA] Hubla · Carrinho` | `/webhook/martha-guterres/hubla/carrinho` |
| `[MARTHA] Hubla · Recusadas` | `/webhook/martha-guterres/hubla/recusadas` |
| `[MARTHA] Hubla · Reembolsos` | `/webhook/martha-guterres/hubla/reembolsos` |
| `[MARTHA] Unnichat · Eventos CRM` | `/webhook/martha-guterres/unnichat/eventos` |
| `[MARTHA] Unnichat · Blocklist` | `/webhook/martha-guterres/unnichat/blocklist` |
| `[MARTHA] Unnichat · Conversas do dia` | `/webhook/martha-guterres/unnichat/conversas-dia/reprocessar` |

- Um endpoint por evento quando a fonte manda cada evento separado (caso da Hubla).
  Quando a fonte manda tudo num endpoint só, o workflow separa o tipo dentro (Switch
  pelo campo de tipo do payload).
- Quando a fonte manda token de verificação (ex.: header da Hubla), o webhook valida
  pela autenticação do próprio nó Webhook (Header Auth) e recusa se não bater. Com
  Header Auth, o n8n devolve 403 (esperado pelo comportamento padrão do n8n; ainda
  não verificado com curl nesta instância). O workflow não chega a executar.
- Webhooks chamados pelo Unnichat usam a credencial `[MARTHA] Webhook token`
  (header `x-cic-token`). No Unnichat, o opt-out nativo é obrigatoriamente o último
  passo da automação, então o POST pro n8n vem antes dele: se o token estiver errado,
  o bloqueio no banco não acontece. Conferir a primeira execução real após ativar.
- Responder 200 rápido; o processamento vem depois do nó de resposta quando for
  pesado.
- Fuso do workflow: `America/Sao_Paulo`. No banco, tudo em `timestamptz`.

## Gravação no Supabase (upsert por chave única)

Padrão: nó HTTP Request para a API REST do Supabase (PostgREST), autenticado com a
credencial predefinida `[MARTHA] Supabase service role`.

```
POST {SUPABASE_URL}/rest/v1/<tabela_bruta>?on_conflict=<colunas_da_chave>
Prefer: resolution=merge-duplicates,return=minimal
Content-Type: application/json
Body: objeto ou array de objetos com os campos do contrato
```

- `<colunas_da_chave>` é a chave única da tabela, definida em
  `docs/contrato-dados.md`. Precisa existir constraint UNIQUE com essas colunas no
  banco, senão o upsert falha.
- Reenvio do mesmo evento atualiza a linha em vez de duplicar.
- Toda tabela bruta recebe também `raw_payload` (o JSON original, inteiro) e
  `received_at` (preenchido pelo banco). Se faltar campo no mapeamento, o dado ainda
  está no `raw_payload`.
- Lotes (coletas agendadas): mandar array, até 500 linhas por chamada.
- Plano B: se algum caso precisar de lógica no meio (gravar em duas tabelas na mesma
  transação, por exemplo), usar o nó Postgres com `INSERT ... ON CONFLICT DO UPDATE`.
  Registrar aqui quando acontecer.

## Workflow de erro

- Workflow `[MARTHA] Erros`, com tag `tipo:erro`, começando pelo nó Error Trigger.
- Configurado como "Error workflow" nas settings de TODOS os outros workflows da
  Martha.
- Manda e-mail para o grupo `ferramentas@werev.com.br` (credencial Gmail autorizada
  com `mitsuo@werev.com.br`):
  - assunto: `[MARTHA] Erro em <nome do workflow>`;
  - corpo: workflow, nó que falhou, mensagem de erro, horário, link da execução.
- O error workflow só dispara em execução de produção (trigger ativo), não em
  execução manual pelo editor. Teste sempre com o workflow publicado.
- Os nós de gravação ficam com "Retry on fail" ligado (3 tentativas, 5 s de
  intervalo) antes de cair no workflow de erro.

## Export pro repo

- Depois de toda mudança relevante, exportar o JSON do workflow para
  `n8n/workflows/<nome-em-kebab>.json`. Ex.: `[MARTHA] Hubla · Vendas` vira
  `n8n/workflows/hubla-vendas.json`.
- Antes de commitar, conferir que o JSON não tem token, senha ou chave (só referência
  a credencial por nome/id). O repo é público via GitHub Pages.
- Mensagem de commit: `n8n: <nome do workflow> (<o que mudou>)`.

## Histórico da migração (10/11/2026)

- Os workflows saíram do n8n cloud e foram para a VPS (`n8n.werev.com.br`), com os
  mesmos nomes, tags, credenciais e paths.
- `[MARTHA] Unnichat · Blocklist` fica ativo nos dois lados (cloud e VPS) até os
  broadcasts antigos do Unnichat pararem de chamar a URL do cloud.
- Os 4 eventos da Hubla (Vendas, Carrinho, Recusadas e Reembolsos) foram confirmados
  chegando na VPS em 10/11/2026. Os workflows da Hubla no cloud ficam liberados para
  desativar.
- Backup diário do banco do n8n na pasta `n8n-backups-werev` do Google Drive.

### Incidente de 12/11/2026: coletas paradas sem alerta

- O que houve: às 12:15 de 12/11 o token da credencial do Unnichat (conexão 0209) passou a
  dar 401. Coleta de broadcasts, Coleta de automações e Conversas do dia falharam por quase
  21 h e ninguém foi avisado.
- Por que não houve alerta: na migração para a VPS, os workflows perderam a configuração
  "Error workflow". O `[MARTHA] Erros` estava ativo, mas nenhum workflow apontava para ele.
- Correção (13/11): token trocado, dados recuperados, credencial renomeada para
  `[MARTHA] Unnichat MG0209` (mesmo id) e Error workflow = `[MARTHA] Erros` configurado
  nos 10 workflows da pasta. Ajustar só a configuração não cria versão nova nem tira o
  workflow do ar.
- Teste (13/11): workflow temporário com gatilho agendado e nó que falha de propósito.
  O `[MARTHA] Erros` rodou em modo error e o Gmail enviou o alerta. Gatilho manual não
  serve para esse teste, porque o error workflow só dispara em execução de produção.

## Checklist de workflow novo

- [ ] Nome no padrão e dentro da pasta da operação na VPS (`cic-martha-guterres`)
- [ ] Tags `martha`, `fonte:*`, `tipo:*`
- [ ] Credenciais `[MARTHA]`, nenhuma chave solta em nó
- [ ] Path de webhook com `martha-guterres`
- [ ] Upsert com `on_conflict` igual à chave do contrato
- [ ] **Obrigatório:** Settings > Error workflow = `[MARTHA] Erros`. Ao importar ou
  migrar workflow para outra instância, essa configuração se perde: conferir sempre
  depois.
- [ ] Teste com payload real e conferência da linha no Supabase
- [ ] JSON exportado pro repo
