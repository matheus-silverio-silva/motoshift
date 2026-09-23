# Prompt para o Claude Design — protótipo MotoShift

Um prompt só, para colar no Claude Design com o GitHub já conectado.

## O que eu encontrei no código antes de escrever isto

Vale você saber, porque muda o pedido:

**Não existe versão de PC hoje.** O `AppScaffold` faz uma coisa só em tela grande —
limita o conteúdo a `maxContentWidth = 640` e centraliza. O resultado é o app de
celular no meio do monitor, com duas faixas vazias dos lados. Não é um layout de
desktop ruim; é a ausência de um. Então "protótipo novo para PC" é de fato criar algo
que não existe, e o prompt trata assim.

**O design system está bem definido e é o que deve ser preservado.** Paleta teal com
Bricolage Grotesque nos títulos e Plus Jakarta Sans no corpo, cards claros sobre fundo
`surface2`, pílulas de status em quatro variantes, raios de 12–18px, sombras teal
suaves. Extraí os valores exatos do `app_theme.dart` e coloquei no prompt para o Claude
Design não inventar tokens novos.

**Tem um conflito embutido no seu pedido, e o prompt resolve assim.** O gesto visual
mais forte do app é o cabeçalho com gradiente teal e o card claro de cantos
arredondados subindo por cima dele. Isso é um idioma de celular — em 1440px vira uma
faixa colorida gigante no topo. A saída que pedi: o teal migra para a barra lateral
fixa, e o conteúdo fica claro. Mesma paleta, mesma sensação, sem esticar um gesto que
não escala. É o único ponto onde "não mudar muito" cede um pouco, e é de propósito.

---

## O prompt

```text
Preciso de um protótipo de alta fidelidade do MotoShift em duas versões: desktop
(que hoje não existe) e mobile (refinando o que já existe). O repositório está
conectado: matheus-silverio-silva/motoshift.

Leia primeiro, para trabalhar em cima do que existe e não do zero:
  Motoshift/lib/theme/app_theme.dart      -- design system completo
  Motoshift/lib/widgets/                  -- componentes já construídos
  Motoshift/lib/views/                    -- as telas atuais
  Motoshift/lib/routes/app_routes.dart    -- inventário de rotas

REGRA PRINCIPAL: preservar a identidade visual. Isto é refinamento e extensão,
não redesenho. Se você se pegar inventando uma cor, uma fonte ou um raio que não
está na lista abaixo, pare e use o que existe.

────────────────────────────────────────────────────────────
DESIGN SYSTEM — use exatamente estes valores
────────────────────────────────────────────────────────────
Cores
  teal        #0E8B8C   (primária)
  tealBright  #16B5B0
  tealDeep    #0A4D52
  ink         #062E33
  surface     #FFFFFF   surface2 #F2F6F5   surface3 #E7EFEE   line #E2EAE9
  text        #0F2C30   muted #6B8487
  amber       #F6A623   amberSoft #FFF1D6
  good        #1B9E73   goodSoft #DDF3EA
  tealSoft    #DEF1F0
  error       #BA1A1A   errorContainer #FFDAD6

Gradientes
  header   135°  teal -> tealDeep
  primary  135°  tealBright -> teal
  loginBg  180°  tealDeep -> #062E33 -> #04181B

Tipografia
  Títulos: Bricolage Grotesque, 700-800, line-height 1.2
           32 / 26 / 22 / 20 / 18 / 16 / 15
  Corpo:   Plus Jakarta Sans, 400-700
           14 / 13 / 11 (secundário usa muted)

Forma
  Raio: 12 campos e botões · 14 botões primários · 16-18 cards
  Sombra de card: rgba(10,77,82,0.04), blur 14, y+6
  Pílulas de status, 4 variantes: teal · amber (atenção) · good (sucesso)
                                  · ghost (neutro)

────────────────────────────────────────────────────────────
PARTE 1 — DESKTOP (1440 x 1024)
────────────────────────────────────────────────────────────
O problema: hoje o app só centraliza 640px de conteúdo numa tela de 1440.
Sobram duas faixas vazias e nenhuma densidade. Precisa virar um layout de
desktop de verdade.

Estrutura base, igual em todas as telas:
  - Barra lateral fixa de 240px à esquerda, com o gradiente header (teal ->
    tealDeep). Logo no topo, itens de navegação, avatar e saída embaixo.
    Ela substitui a bottom nav e passa a carregar o teal da marca.
      Lojista: Início · Agenda · Turnos · Carteira · Perfil
      Motoboy: Início · Turnos · Carteira · Avaliações · Perfil
  - Área de conteúdo em surface2, com barra superior clara: título da página à
    esquerda, sino de notificações com badge e avatar à direita.
  - Conteúdo com largura máxima de 1280px, gutter de 24px, grid de 12 colunas.
  - Cards em surface branco, exatamente como no mobile.

IMPORTANTE sobre o gesto visual: no mobile o cabeçalho tem gradiente teal e o
card claro sobe por cima com cantos arredondados. NÃO estique isso para 1440px —
vira uma faixa colorida enorme. No desktop, o teal vive na barra lateral e o
conteúdo é claro. Mesma paleta, mesma sensação de marca, densidade adequada.

Padrões por tipo de tela:
  - Dashboards: linha de 4 KPIs no topo (reusar o stat_card), depois duas
    colunas — gráfico à esquerda, lista de próximos turnos à direita.
  - Listas de turno: master-detail. Lista à esquerda (~380px), detalhe do item
    selecionado à direita, na mesma tela. Sem navegação empilhada no desktop.
  - Publicar turno: formulário em duas colunas, com um card de pré-visualização
    do turno ao lado, atualizando conforme se preenche.
  - Carteira: card de saldo à esquerda, extrato à direita.
  - Fluxos curtos (avaliar, recarregar, sacar): modal centralizado de 480px,
    não tela cheia.

────────────────────────────────────────────────────────────
PARTE 2 — MOBILE (390 x 844)
────────────────────────────────────────────────────────────
Aqui é refinamento, não redesenho. Mantenha: o AppScaffold com gradiente e card
sobreposto, a bottom nav de 4 itens, o shift_card, o stat_card, as pílulas.
Alguém que usa o app hoje tem que reconhecer todas as telas.

O que melhorar:
  - Densidade e ritmo vertical: hoje várias telas gastam muito espaço em cima e
    espremem o conteúdo embaixo. Padronize a escala de espaçamento (4/8/12/16/24)
    e aplique de forma consistente.
  - Hierarquia nos cards de turno: valor e horário são o que a pessoa procura
    primeiro; título e região vêm depois.
  - Estados vazios e de carregamento em todas as listas (existe um empty_state,
    use e amplie).
  - Área de toque mínima de 44px em tudo que é clicável.

────────────────────────────────────────────────────────────
TELAS (desenhe as duas versões de cada uma)
────────────────────────────────────────────────────────────
Já existem, refinar:
   1. Login
   2. Cadastro
   3. Dashboard do lojista
   4. Dashboard do motoboy
   5. Turnos disponíveis (com filtros)
   6. Detalhe do turno
   7. Publicar turno
   8. Meus turnos / turnos do lojista
   9. Agenda (calendário)
  10. Carteira e extrato
  11. Histórico de turnos
  12. Avaliação
  13. Minhas avaliações
  14. Perfil
  15. Perfil público
  16. Relatório / análise de score

Não existem ainda, precisam ser criadas:
  17. Central de notificações — lista com não lidas em destaque, agrupada por
      dia, e o sino com badge. Tipos: turno aceito, turno expirado, turno
      vencendo, pagamento recebido, avaliação pendente.
  18. Filtro por raio — slider de distância, mapa com o pino do usuário e os
      turnos ao redor, e a distância em km aparecendo em cada card da lista.
  19. Avaliar vários entregadores — um turno pode ter várias vagas, e o lojista
      precisa avaliar cada entregador. Mostre a lista de quem falta avaliar e o
      progresso (ex.: "2 de 3 avaliados").
  20. Recarga de saldo — valor, método, Pix copia-e-cola com QR, e tela de
      aguardando confirmação. É o lojista colocando dinheiro na carteira.
  21. Saldo do lojista — separando saldo disponível de saldo bloqueado em
      turnos publicados, com o aviso de saldo insuficiente ao publicar.

Acrescente também uma pílula de status "expirado" (use a variante ghost) ao
conjunto atual de aberto / aceito / em andamento / finalizado / cancelado.

────────────────────────────────────────────────────────────
COMO TRABALHAR
────────────────────────────────────────────────────────────
São muitos artboards. Vá em lotes e PARE ao fim de cada um para eu revisar,
antes de seguir:

  Lote 1  Fundações: barra lateral, barra superior, grid, e os componentes
          principais (card de turno, KPI, pílula, campo, botão) nas duas
          larguras. É o lote que define tudo — capriche aqui.
  Lote 2  Desktop: telas 3, 4, 5, 6 (os dois dashboards e o fluxo de turno).
  Lote 3  Desktop: telas 7 a 16.
  Lote 4  Desktop: telas novas, 17 a 21.
  Lote 5  Mobile: as 21 telas, refinadas.

Organize o canvas em faixas horizontais: uma faixa por lote, rotulada, com as
telas em ordem de fluxo. Use conteúdo realista em português do Brasil — nomes,
endereços de Curitiba, valores em reais entre R$ 80 e R$ 150 por turno,
horários plausíveis. Nada de "Lorem ipsum" nem "Card Title".

NÃO faça:
  - Cor, fonte ou raio fora da lista acima.
  - Modo escuro. O app é claro; não é hora de introduzir isso.
  - Biblioteca de ícones diferente. O app usa Material Icons outlined.
  - Redesenhar a marca ou o logo.
  - Esticar o layout de 640px para preencher 1440px.
```

---

## Depois que o protótipo estiver pronto

O `AppScaffold` vai precisar de um irmão para desktop — algo como `AdaptiveScaffold`
que decide entre bottom nav e barra lateral por breakpoint (`< 600` celular, `600–1023`
tablet, `>= 1024` desktop). Vale pedir isso ao Claude Code como tarefa separada, depois
que você aprovar o lote 1, porque é a peça de que todas as telas dependem.

E uma escolha que ninguém pode fazer por você: o master-detail no desktop muda a
navegação, não só o visual. Lista e detalhe passam a coexistir, então `/detalhe-turno`
deixa de ser uma rota empilhada em tela larga. Olhe com atenção como isso fica no lote
2 — se não convencer, é melhor descobrir ali do que com dezesseis telas prontas.
