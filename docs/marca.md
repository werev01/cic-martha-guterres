# Marca WeRev no CIC

Resumo do manual de rebranding da WeRev (28/10/2026) aplicado ao CIC. O PDF original
não vai pro repo; este arquivo é a referência pra construção.

Última atualização: 04/11/2026

## Posicionamento

Consultoria empresarial integrada (estratégia, gestão e tecnologia). A identidade
busca solidez, credibilidade e sofisticação: linguagem sóbria, contemporânea e
atemporal. No CIC isso se traduz em tela limpa, contraste alto, poucos acentos de cor
e nada de elemento decorativo gratuito.

## Cores

| Nome | Hex | Papel no CIC |
|---|---|---|
| Navy | `#1f2b38` | cor principal: menu lateral, títulos, texto forte |
| Whiskey | `#844420` | acento: botão principal, item ativo, destaque de número |
| Taupe | `#8e6e59` | acento secundário: ícones, estados de apoio |
| Grey | `#c6c6c6` | linhas, bordas, texto sobre navy |
| Linen | `#e6dfdd` | fundo neutro (login, áreas de respiro) |

Regras:
- Navy domina; Whiskey aparece pouco e sempre com função (ação, seleção, destaque).
- Fundo de leitura das telas de dados em tom claro derivado do Linen, pra não cansar.
- Cor de status (meta batida, alerta) usa tons da própria paleta antes de recorrer a
  verde/vermelho puros. Quando precisar de semáforo, usar versões dessaturadas.

## Tipografia

| Fonte | Uso | No CIC |
|---|---|---|
| Arsenal (Regular, Negrito) | títulos, assinatura | Google Fonts |
| Neue Montreal (Leve, Regular, Médio, Negrito) | texto corrido, interface | substituída por **Inter Tight** no CIC (decisão de 04/11/2026: fonte parecida é suficiente) |

Números de dashboard em fonte tabular (alinhamento de dígitos).

## Logo e símbolo

- Assinatura: `WEREV` em caixa alta, espaçamento largo, com ®. No CIC é texto
  (Arsenal), não imagem.
- Símbolo (versão atual, manual "Ampulheta v2"): duas letras V espelhadas formando uma
  ampulheta, com o encontro central interrompido. Traço grosso à esquerda e fino à
  direita, em contraste com a tipografia.
- Arquivos no repo (vetorizados a partir do PDF, não há SVG oficial):
  - `app/assets/marca/simbolo.svg`: símbolo em `currentColor` (assume a cor do texto);
  - `app/assets/marca/favicon.svg`: símbolo Linen sobre quadrado Navy, traço reforçado
    pra ler em 16 a 32 px;
  - `app/assets/marca/favicon-32.png` e `apple-touch-icon.png` (180 px).
- Aplicações: Navy sobre Linen (login), Linen sobre Navy (menu, ícone da aba).
- A versão anterior (dois R espelhados) saiu de uso.

## Ícones

- Proibido emoji.
- Ícones de traço fino (linha, sem preenchimento), estilo geométrico e discreto, na cor
  Grey sobre Navy e Taupe/Navy sobre fundo claro. Biblioteca: Lucide (versão fixada).
- Ícone só onde ajuda a achar algo (menu, ação). Nada de ícone decorativo em título.
