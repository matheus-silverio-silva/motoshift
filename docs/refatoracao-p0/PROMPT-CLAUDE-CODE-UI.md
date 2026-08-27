# Prompt para o Claude Code — implementar o protótipo v2

## O que eu fiz antes de escrever

O arquivo que você mandou é um bundle empacotado: o conteúdo real vem comprimido em
base64 dentro de um `<script type="__bundler/manifest">`. Extraí, descomprimi e li o
canvas inteiro. **O markup com os estilos inline é muito melhor do que qualquer
descrição que eu escrevesse em texto** — tem as medidas exatas de cada elemento. Então
salvei duas versões no repositório:

```
design/prototipos/v2/canvas-legivel.html          <- markup extraído, é o que o Claude Code lê
design/prototipos/v2/MotoShift-Prototipo-offline.html  <- o bundle original, para você abrir e ver
```

O prompt manda o Claude Code ler o primeiro. Isso muda o jogo: em vez de eu descrever
"o card tem cantos de 16px", ele lê `border-radius:16px` direto da fonte.

## O que o protótipo definiu

Confirmei lendo o markup, não por suposição:

| Elemento | Medida |
|---|---|
| Artboards | 21 desktop de 1440×, 22 mobile de 390× |
| Barra lateral | 240px fixos, `linear-gradient(135deg,#0E8B8C,#0A4D52)` |
| Barra superior | 72px, `#FFFFFF`, borda inferior 1.5px `#E2EAE9`, padding 0 24px |
| Conteúdo | `max-width:1280px`, centralizado, padding 24px |
| Grid | 12 colunas, `gap:24px` · KPIs em 4 colunas com o mesmo gap |
| Lista do master-detail | 380px fixos, branca, borda direita 1.5px `#E2EAE9` |
| Modal | 480px |
| Alvo de toque | 44px — aparece 138 vezes no canvas |

A paleta bateu 100% com o `app_theme.dart`. Ele acrescentou cinco tons para a barra
lateral e divisórias: `#EAFFFD`, `#BFE5E3`, `#C4D2D1`, `#BCCCCC`, `#FBE4E2`.

**O protótipo não define breakpoints** — é um canvas, mostra 1440 e 390 e mais nada.
Quem decide onde troca o layout é a implementação, então fixei no prompt.

## Três coisas que já verifiquei no código

`flutter_map`, `latlong2` e o widget `MapaRaio` **já existem** — a tela 18 aproveita o
que está lá. Mas **falta o `geolocator`**, e sem GPS não há "turnos perto de você".

O `api_service.dart` não tem **nenhum** método de notificação nem de filtro por raio.
Os endpoints existem no backend desde o PR #4; o cliente Dart nunca foi atualizado.

A **tela 20 (recarga de saldo) não pode ser implementada agora.** Ela depende dos
endpoints da etapa 4 do prompt de pagamentos, que ainda não existem — você está na
etapa 2. O prompt manda parar antes dela.

---

## O prompt

```text
Implementar o protótipo v2 do MotoShift: versão desktop (que não existe hoje) e
refinamento do mobile.

Repositório: C:\Projetos\stitch_log_stica_urbana_agendada
App Flutter em Motoshift/. Backend já pronto e mergeado na main.

PROTÓTIPO — leia antes de qualquer coisa:
  design/prototipos/v2/canvas-legivel.html

É o canvas do Claude Design com os estilos inline. Contém 21 artboards desktop de
1440px e 22 mobile de 390px, cada um rotulado ("Tela 5 · Turnos disponíveis...").
Use os valores que estão lá — cores, espaçamentos, raios, tamanhos de fonte — em
vez de estimar. Quando este prompt e o protótipo divergirem, o protótipo vence.

Leia também, para trabalhar em cima do que existe:
  Motoshift/lib/theme/app_theme.dart    -- design system; NÃO altere os tokens
  Motoshift/lib/widgets/                -- 20 componentes já construídos
  Motoshift/lib/widgets/app_scaffold.dart
  Motoshift/lib/routes/app_routes.dart
  Motoshift/lib/services/api_service.dart

Comece criando a branch feat/ui-desktop-responsivo a partir da main.
(A branch feat/carteira-liquidacao-automatica segue em paralelo e não conflita:
uma mexe em backend/, esta mexe em Motoshift/lib/.)

REGRA PRINCIPAL: o mobile atual funciona. Nada do que você fizer pelo desktop pode
regredir o mobile. Na dúvida, crie um widget novo em vez de alterar um existente.

════════════════════════════════════════════════════════════
FASE 0 — Fundações (é a fase que importa; capriche)
════════════════════════════════════════════════════════════
1. lib/theme/breakpoints.dart
     mobile   < 600
     tablet   600 .. 1023
     desktop  >= 1024
   Helpers: context.isMobile / isTablet / isDesktop via extension.
   O protótipo não define isso — é decisão de implementação, use estes valores.

2. lib/widgets/adaptive_scaffold.dart
   Escolhe o shell pelo breakpoint:
     - mobile e tablet -> o AppScaffold que já existe, INTOCADO
     - desktop         -> DesktopShell (novo)
   Mesma API do AppScaffold (header, body, bottomNav) para as telas migrarem
   trocando uma linha.

3. lib/widgets/desktop/app_sidebar.dart — 240px, gradiente 135° teal->tealDeep.
   Estrutura, conforme o canvas: logo (ícone two_wheeler + "Moto"/"Shift"),
   rótulo "NAVEGAÇÃO", itens de navegação com ícone Material outlined e badge
   opcional, e no rodapé o bloco do usuário (avatar com iniciais, nome, subtítulo)
   e "Sair".
     Lojista: Início · Agenda · Turnos · Carteira · Perfil
     Motoboy: Início · Turnos · Carteira · Avaliações · Perfil

4. lib/widgets/desktop/app_topbar.dart — 72px, fundo branco, borda inferior 1.5px
   #E2EAE9, padding horizontal 24. Título e subtítulo à esquerda; à direita ação
   primária, sino de notificações com badge e avatar.

5. lib/widgets/desktop/content_grid.dart — max-width 1280, centralizado,
   padding 24, grid de 12 colunas com gap 24. Um helper de span de colunas.

NÃO migre nenhuma tela ainda. PARE e me mostre o shell rodando com uma tela de
exemplo, nas três larguras.

════════════════════════════════════════════════════════════
FASE 1 — Dashboards (telas 3 e 4)
════════════════════════════════════════════════════════════
Desktop: linha de 4 KPIs (grid de 4 colunas, gap 24, reusando stat_card), depois
gráfico à esquerda e lista de próximos turnos à direita.
Mobile: 3 KPIs, conforme o artboard de fundações mobile do canvas.
Use fl_chart, que já está no pubspec.

PARE.

════════════════════════════════════════════════════════════
FASE 2 — Master-detail (telas 5, 6, 8)
════════════════════════════════════════════════════════════
Esta fase mexe em NAVEGAÇÃO, não só em layout. Leia inteiro antes de começar.

No desktop, lista (380px) e detalhe convivem na mesma tela. Ou seja,
/detalhe-turno deixa de ser uma rota empilhada quando a largura >= 1024.

Implemente assim:
  - Um TurnoSelecionadoProvider guarda o id selecionado.
  - Em mobile, tocar num card navega para /detalhe-turno como hoje.
  - Em desktop, tocar num card só troca o id no provider; o painel direito
    reage. Se alguém abrir /detalhe-turno direto por URL em tela larga,
    redirecione para a lista com aquele id já selecionado.
  - Estado vazio no painel direito quando nada está selecionado.

Não duplique a tela de detalhe. Extraia o conteúdo dela para um widget que sirva
tanto à rota mobile quanto ao painel do desktop.

PARE. Quero ver isso funcionando antes das outras telas.

════════════════════════════════════════════════════════════
FASE 3 — Demais telas desktop (7, 9 a 16)
════════════════════════════════════════════════════════════
Publicar turno (formulário em 2 colunas + pré-visualização ao vivo), agenda,
carteira, histórico, avaliação (modal de 480px), minhas avaliações, perfil,
perfil público, relatório. Siga os artboards.

PARE.

════════════════════════════════════════════════════════════
FASE 4 — Telas novas (17, 18, 19, 21)
════════════════════════════════════════════════════════════
Estas dependem de endpoints que JÁ EXISTEM na main mas que o api_service.dart
ainda não chama. Adicione os métodos primeiro.

17. Central de notificações
      GET  /api/notificacoes?usuarioId=&apenasNaoLidas=
      GET  /api/notificacoes/contagem?usuarioId=
      PUT  /api/notificacoes/{id}/lida
      PUT  /api/notificacoes/marcar-todas-lidas?usuarioId=
    Lista agrupada por dia, não lidas em destaque, badge no sino.
    Tipos: turno_aceito, turno_expirado, turno_vencendo, turno_lotado,
           turno_pendente_finalizacao, pagamento_confirmado, avaliacao_pendente

18. Filtro por raio
      GET /api/turnos/disponiveis?lat=&lng=&raioKm=&ordenarPor=distanciaAsc
    A resposta traz distanciaKm em cada turno — mostre no card.
    Adicione geolocator ao pubspec (não está lá) e trate a negativa de permissão
    com um estado explícito, não com um mapa vazio.
    O widget MapaRaio já existe e usa flutter_map — reaproveite.

19. Avaliar vários entregadores
      GET /api/avaliacoes/turno/{turnoId}/pendentes/{usuarioId}
    A resposta tem "precisaAvaliar" e a lista "pendentes" [{usuarioId, nome}].
    Mostre o progresso ("2 de 3 avaliados") e um POST por entregador, cada um
    com o avaliadoId certo.

21. Saldo do lojista — separando disponível de bloqueado.
    ATENÇÃO: exiba o que a API devolver. Se o backend ainda não expõe
    saldoBloqueado, monte a tela e deixe o campo preparado, mas NÃO invente
    número nem finja saldo. Me avise.

NÃO implemente a tela 20 (recarga de saldo). Os endpoints dela estão na etapa 4
do plano de pagamentos e ainda não existem. Pare e me avise quando chegar nela.

Acrescente a variante "expirado" à status_pill (use a variante ghost).

PARE.

════════════════════════════════════════════════════════════
FASE 5 — Refinamento mobile
════════════════════════════════════════════════════════════
Refinamento, não redesenho. Mantenha AppScaffold, bottom nav, shift_card,
stat_card e as pílulas — quem usa o app hoje tem que reconhecer tudo.
  - Escala de espaçamento 4/8/12/16/24 aplicada de forma consistente.
  - Hierarquia do card de turno: horário e valor primeiro, título e região depois.
  - Estados vazio e de carregamento em todas as listas (empty_state já existe).
  - Alvo de toque mínimo de 44px em tudo que é clicável.
  - Sino de notificações no header.

════════════════════════════════════════════════════════════
REGRAS GERAIS
════════════════════════════════════════════════════════════
- Um commit por fase, mensagem em português, escopo convencional.
- NÃO altere os tokens de app_theme.dart. Se precisar de um valor que não existe
  lá, primeiro procure no protótipo; se realmente for novo, acrescente ao
  AppColors com nome descritivo e me diga qual e por quê.
- Nada de modo escuro. Nada de trocar a biblioteca de ícones (Material outlined).
- `flutter analyze` limpo ao fim de cada fase. Rode `flutter test` — existem
  golden tests no projeto e eles VÃO quebrar com mudança de layout; regrave os
  goldens conscientemente, olhando o diff, não com --update-goldens no automático.
- Teste nas três larguras (390, 800, 1440) antes de dizer que uma fase terminou.
- Se o protótipo estiver ambíguo ou faltar um estado (erro, vazio, carregando),
  PERGUNTE em vez de inventar.
```

---

## Uma observação sobre os golden tests

O repositório tem goldens, e um commit anterior (`82136a7 test(goldens): regrava
baseline nesta maquina`) sugere que eles já foram regravados por diferença de máquina,
não por mudança intencional. Uma refatoração de layout vai quebrar todos. Deixei no
prompt a instrução de regravar olhando o diff — se rodar `--update-goldens` no
automático, eles param de proteger qualquer coisa e viram enfeite.
