# Padrões do n8n (CIC Martha Guterres)

Vale pra todo workflow da operação. Se um caso não estiver coberto aqui, pergunte
antes de inventar e registre a decisão neste arquivo.

Última atualização: 03/11/2026

## Onde fica

- Instância: n8n cloud compartilhada da WeRev.
- Pasta: `cic-martha-guterres`. Todo workflow da Martha mora nela.
- Workflows criados do zero. Não duplicar nem importar workflow de outra operação.

## Nome dos workflows

Formato: `[MARTHA] <Fonte> · <Função>`

Exemplos:
- `[MARTHA] Hubla · Vendas`
- `[MARTHA] Hubla · Reembolsos`
- `[MARTHA] TMB · Vendas`
- `[MARTHA] Unnichat · Eventos CRM`
- `[MARTHA] Unnichat · Coleta de disparos`
- `[MARTHA] Callix · Ligações`
- `[MARTHA] Erros`

Fonte com inicial maiúscula, função curta e no plural quando fizer sentido.

## Tags

Todo workflow leva:
- `martha` (obrigatória, identifica o cliente);
- uma de fonte: `fonte:unnichat`, `fonte:callix`, `fonte:hubla`, `fonte:tmb`;
- uma de tipo: `tipo:webhook` (recebe push), `tipo:agendado` (puxa por cron) ou
  `tipo:erro`.

## Credenciais

Nunca compartilhar credencial com outra operação.

| Credencial | Tipo no n8n | Uso |
|---|---|---|
| `[MARTHA] Supabase service role` | Supabase API | gravar nas tabelas brutas |
| `[MARTHA] Unnichat` | Header Auth (token da conta da Martha) | chamadas à API do Unnichat |
| `[MARTHA] Callix` | Header Auth | chamadas à API da Callix |
| `[MARTHA] Hubla` | Header Auth | validar o token do webhook / chamadas à API |
| `[MARTHA] TMB` | Header Auth | idem |
| `[MARTHA] E-mail alertas` | SMTP ou Gmail | workflow de erro |

Regra: chave e token só dentro de credencial. Nunca colar chave em header, URL ou
campo de nó (isso vaza no export do JSON).

## Webhooks

Path: `/webhook/martha-guterres/<fonte>/<evento>`

| Fonte | Path |
|---|---|
| Hubla | `/webhook/martha-guterres/hubla/eventos` |
| TMB | `/webhook/martha-guterres/tmb/eventos` |
| Unnichat | `/webhook/martha-guterres/unnichat/eventos` |
| Callix | `/webhook/martha-guterres/callix/eventos` (se a Callix for por push) |

- Um path por fonte; o workflow separa o tipo de evento dentro (Switch pelo campo de
  tipo do payload). Se a fonte exigir um endpoint por evento, usar
  `/<fonte>/<evento>` (ex.: `/hubla/vendas`).
- Quando a fonte manda token de verificação (ex.: header da Hubla), o webhook valida
  e responde 401 se não bater.
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
- Manda e-mail para `ferramentas@werev.com.br`:
  - assunto: `[MARTHA] Erro em <nome do workflow>`;
  - corpo: workflow, nó que falhou, mensagem de erro, horário, link da execução.
- Os nós de gravação ficam com "Retry on fail" ligado (3 tentativas, 5 s de
  intervalo) antes de cair no workflow de erro.

## Export pro repo

- Depois de toda mudança relevante, exportar o JSON do workflow para
  `n8n/workflows/<nome-em-kebab>.json`. Ex.: `[MARTHA] Hubla · Vendas` vira
  `n8n/workflows/hubla-vendas.json`.
- Antes de commitar, conferir que o JSON não tem token, senha ou chave (só referência
  a credencial por nome/id). O repo é público via GitHub Pages.
- Mensagem de commit: `n8n: <nome do workflow> (<o que mudou>)`.

## Checklist de workflow novo

- [ ] Nome no padrão e dentro da pasta `cic-martha-guterres`
- [ ] Tags `martha`, `fonte:*`, `tipo:*`
- [ ] Credenciais `[MARTHA]`, nenhuma chave solta em nó
- [ ] Path de webhook com `martha-guterres`
- [ ] Upsert com `on_conflict` igual à chave do contrato
- [ ] Error workflow apontando pra `[MARTHA] Erros`
- [ ] Teste com payload real e conferência da linha no Supabase
- [ ] JSON exportado pro repo
