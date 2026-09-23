# MotoShift — Revisão de UI/UX e navegação + prompt para o Claude Code

Revisão feita pela leitura do código do app Flutter em `main` (`d0dd7fa`, depois do merge do PR #7), 19/09/2026.
Não rodei o app: cada item abaixo aponta o arquivo e a linha, para você conferir clicando.

> Mesma observação da revisão do financeiro: a pasta local está atrás de `main`. `git checkout main && git pull` antes.
> Se o prompt do financeiro já tiver sido aplicado, os botões de "confirmar pagamento" citados aqui já terão saído —
> o prompt abaixo trata disso.

---

## 1. Por que o app parece confuso

O problema não é visual, é de **arquitetura de navegação**. Três causas explicam quase tudo:

1. **Cada tela reimplementa a barra inferior na mão.** Há sete `switch (i)` copiados (`_onNav` em dashboard, agenda,
   turnos, carteira, perfil…). Quando uma cópia erra, só aquela tela quebra — e ninguém percebe.
2. **O menu lateral usa `pushReplacementNamed` para telas que não têm menu.** Você entra numa tela, ela substitui a
   anterior, e a tela nova só tem a seta de voltar — que não tem para onde voltar.
3. **As ações depois do turno estão espalhadas em quatro telas.** Finalizar fica em "Turnos", pagamento em "Histórico",
   avaliação em "Avaliações", nota em "Notas fiscais". O detalhe do turno, que seria o lugar natural, não oferece
   nenhuma delas.

---

## 2. Links e botões que não funcionam ou levam ao lugar errado

| # | Onde | O que acontece | Gravidade |
|---|------|----------------|-----------|
| 1 | Menu lateral no **celular** → Notas fiscais, Avaliações, Histórico, Notificações, Saldo | `app_nav_drawer.dart` faz `pushReplacementNamed`; essas telas não têm barra inferior, então o `AdaptiveScaffold` não lhes dá menu. Fica só a seta, e `_BackButton` faz `Navigator.pop()` na **única** rota da pilha → tela em branco. O usuário fica preso. | Alta |
| 2 | **Agenda** do motoboy, no celular | `agenda_screen.dart:131` monta `AppBottomNav(userType: UserType.lojista)` para todo mundo, e o `_onNav` só tem rotas de lojista. Para o motoboy, "Início" e "Turnos" caem em rotas de lojista, o `AuthGuard` redireciona para o dashboard do motoboy — **os dois botões levam para a mesma página**. E os rótulos da barra são os do lojista. | Alta |
| 3 | Toque numa **notificação** | `notificacoes_screen.dart:47` só marca como lida. O comentário diz que falta rota para buscar o turno pelo id, mas `GET /api/turnos/{id}` **já existe** no backend — falta só o método no `turno_api.dart`. "Turno finalizado — avalie a outra parte" não leva à avaliação. | Alta |
| 4 | Botão **"Contatar"** no detalhe do turno do lojista | `turno_lojista_conteudo.dart:512` — `onTap: () {}`. Não faz nada. | Média |
| 5 | **"Sacar via Pix"** no dashboard do motoboy (desktop) | Vai para `/sacar-pix`, que é o stub "Em breve" — enquanto a Carteira **já tem saque funcionando**. | Média |
| 6 | Clicar num turno **encerrado** no desktop (Histórico, dashboard) | `detalhe_turno_screen` e `turno_lojista_screen` redirecionam para a lista de turnos. No lojista, a seleção é resolvida contra a lista **filtrada**: se o filtro não for "Todos", o turno não é encontrado e aparece "Selecione um turno". Cancelados não estão em aba nenhuma além de "Todos". | Média |
| 7 | **Histórico no desktop** | `historico_turnos_screen.dart` passa `onAvaliar` e `onPagar` só para a versão mobile. No desktop não dá para avaliar nem pagar pelo Histórico. | Média |
| 8 | **Avaliação feita pelo motoboy** | `meus_turnos_screen.dart:664` e `minhas_avaliacoes_screen.dart` passam `nomeAvaliado: turno.titulo`. O cabeçalho diz que você está avaliando "Entrega Almoço Centro" em vez do nome da loja. | Média |
| 9 | Item destacado errado no menu | `saldo_lojista_screen.dart:84` destaca `carteira` (que nem existe no menu do lojista → nada fica destacado). `historico_turnos_screen.dart:350` destaca `perfil`, com um comentário dizendo que Histórico não está no menu — mas agora está. | Baixa |
| 10 | "Esqueceu a senha?" no login | Tela "Em breve". Aceitável, mas é o primeiro contato de quem abre o app. | Baixa |
| 11 | "Ver todos" em "Turnos aceitos" (dashboard do motoboy) | `pushNamed` para a tela de turnos, que abre em "Turnos disponíveis" — a lista de aceitos fica mais abaixo. E, por ser `pushNamed`, a pilha cresce: depois, a barra inferior faz `pushReplacement` por cima dela. | Baixa |
| 12 | Rotas duplicadas | `/meus-turnos` = `/turnos-disponiveis` e `/agendar-turno` = `/publicar-turno` (legadas, mesma tela). Aumentam a chance de alguém navegar para a errada. | Baixa |

---

## 3. Avaliações: por que é difícil chegar lá

Hoje existem **cinco portas** para avaliar, cada uma com um comportamento diferente:

| Porta | Motoboy | Lojista |
|-------|---------|---------|
| Logo depois de finalizar | abre a avaliação (com o nome errado, item 8) | **nada** — o lojista nem finaliza pelo app |
| Painel "Pendências" do início | leva a Avaliações | leva a Avaliações |
| Histórico | só no celular | só no celular |
| Menu → Reputação → Avaliações | lista pendentes no topo | lista pendentes → tela de avaliar entregadores |
| Notificação "avalie a outra parte" | não abre nada | não abre nada |

E há outros problemas de desenho:

- **"Avaliações" no menu fica em "Reputação"** e o título sugere "o que falaram de mim". Quem quer *avaliar* não procura
  ali.
- **O detalhe do turno não tem botão "Avaliar"**, nem para o lojista nem para o motoboy — e é para lá que qualquer pessoa
  vai depois de um turno.
- **A tela de avaliar entregadores (lojista) só abre pela central de Avaliações.** Não há entrada pelo turno.
- **O detalhe do turno do lojista mostra um entregador só**, mesmo em turno de várias vagas.
- **A avaliação no desktop** é um "modal" numa rota opaca (o próprio código admite): fundo escuro e liso, sem a tela de
  origem por trás. Parece uma página quebrada.

---

## 4. Outras observações de UX

- **Nomes diferentes para a mesma coisa:** "Turnos", "Meus turnos", "Turnos disponíveis", "Histórico". Para o motoboy,
  "Turnos" é a busca e os aceitos; "Histórico" são os encerrados. Vale um nome por conceito, igual no menu, no título e
  no botão.
- **Detalhe do turno sem ações de ciclo de vida:** o motoboy só consegue *aceitar* pelo detalhe. Finalizar e cancelar
  ficam nos cards da lista.
- **Lojista não finaliza turno pelo app.** Só o motoboy tem o botão. Se o motoboy esquecer, o lojista não tem o que fazer
  (e, com o pagamento automático do prompt financeiro, finalizar passa a ser o gatilho do dinheiro).
- **Estado vazio e erro** variam de tela para tela (texto solto, `EmptyState`, `InlineEmpty`).

---

## 5. PROMPT — correção de navegação, avaliações e botões mortos

````text
Contexto: MotoShift (TCC). App Flutter web em Motoshift/, responsivo (celular com barra inferior + gaveta; desktop com
sidebar e master-detail). Trabalhe a partir de main atualizada, numa branch nova: fix/navegacao-ux.

Leia antes de planejar: lib/app.dart, lib/routes/app_routes.dart, lib/widgets/{adaptive_scaffold,app_scaffold,
app_header,app_bottom_nav,app_nav_drawer,auth_guard,painel_pendencias}.dart, lib/widgets/desktop/{app_sidebar,
desktop_shell,app_topbar,master_detail}.dart, e as telas em lib/views/ citadas abaixo. Veja também test/navegacao/ e o
menu_completo_test.

## Problemas a corrigir (confira cada um no código antes de mexer)

### A. Navegação estrutural
A1. Celular: itens da gaveta que abrem telas sem barra inferior (Notas fiscais, Avaliações, Histórico, Notificações,
    Saldo) usam pushReplacementNamed; a tela nova não tem gaveta, e a seta faz pop da única rota → tela em branco.
A2. agenda_screen.dart monta AppBottomNav(userType: UserType.lojista) e um _onNav só com rotas de lojista também para o
    motoboy: "Início" e "Turnos" caem no AuthGuard e voltam ao mesmo dashboard.
A3. Sete telas têm um switch de barra inferior copiado à mão.
A4. Rotas legadas duplicadas: /meus-turnos e /agendar-turno.
A5. desktopSelectedRoute errado em saldo_lojista (aponta para carteira) e historico_turnos (aponta para perfil).

Solução esperada:
- Uma única fonte de verdade para a navegação por papel: um NavConfig (ou equivalente) que define as seções do menu e
  quais 4 itens vão para a barra inferior. AppSidebar, AppNavDrawer e AppBottomNav leem dele. Nenhuma tela escreve
  switch de navegação; a tela informa só a rota atual.
- Regra de navegação documentada no código e seguida por todos:
  * item de menu/barra inferior = troca de seção → substitui a pilha (pushNamedAndRemoveUntil até a raiz);
  * detalhe, formulário ou sub-página = empilha (pushNamed) e volta com pop.
- Toda tela alcançável pelo menu tem, no celular, o botão de menu (gaveta) quando não há para onde voltar. Nunca mais
  uma seta que faz pop na última rota: AppHeader.back cai no menu, ou no dashboard do papel, se canPop() for falso.
- Remova as rotas legadas (ou mantenha como alias que redireciona, com teste), e o destaque do menu deriva da rota atual.

### B. Botões e links sem destino
B1. notificacoes_screen._abrir só marca como lida. Implemente TurnoApi.buscarTurno(id) (GET /api/turnos/{id}, que já
    existe) e navegue pelo referenciaTipo: turno → detalhe do turno (com a ação pendente em destaque),
    carteira → Carteira/Saldo, nota_fiscal → detalhe da nota. Tipo desconhecido: só marca como lida.
    Notificação "avaliacao_pendente" abre direto a avaliação daquele turno.
B2. turno_lojista_conteudo.dart:512, botão "Contatar" com onTap vazio. Verifique o que o perfil público entrega depois do
    P0 de LGPD. Se o telefone não for exposto a participantes do mesmo turno, NÃO o exponha só para este botão: troque
    o botão por "Ver perfil" (perfil público do entregador). Se já for exposto, abra tel:/WhatsApp com url_launcher.
    Me diga no plano qual dos dois casos é.
B3. "Sacar via Pix" no dashboard do motoboy aponta para o stub /sacar-pix, mas a Carteira já tem saque. Aponte para a
    Carteira abrindo o diálogo de saque (argumento de rota) e apague SacarPixScreen e a rota.
B4. Clique em turno encerrado no desktop (vindo do Histórico, dashboard ou notificação) cai em "Selecione um turno"
    quando o filtro da lista não inclui aquele status. Ao chegar por deep-link, a lista troca para um filtro que contenha
    o turno (ou "Todos"). Acrescente a aba "Cancelados" na lista do lojista.
B5. "Ver todos" de "Turnos aceitos" deve abrir a tela de turnos já posicionada nos aceitos.
B6. "Esqueceu a senha?": mantenha a tela, mas com texto útil (o que fazer agora — ex.: falar com o suporte/e-mail de
    contato) em vez de só "Em breve".
B7. Faça uma varredura final: grep por onTap: () {}, onPressed: () {}, rotas que não existem em app.dart,
    pushNamed sem os arguments que a tela exige, e telas que dependem de arguments mas abrem sem eles
    (devem mostrar estado de erro com botão de voltar, nunca uma tela vazia). Liste o que encontrou no resumo final.

### C. Avaliações fáceis de achar
C1. O detalhe do turno (motoboy e lojista, celular e desktop) vira o hub pós-turno. Para turno FINALIZADO mostre um bloco
    "O que falta" com as ações pendentes daquele usuário: Avaliar, Nota fiscal (e pagamento, se ainda existir no fluxo —
    se o prompt financeiro já removeu a dupla confirmação, não recrie os botões). Ação concluída vira item marcado.
C2. Lojista: o detalhe do turno lista TODOS os inscritos (multi-vaga), cada um com nota média, status e botão "Avaliar"
    que abre a tela de avaliar entregadores já com o turno. O lojista também ganha o botão "Finalizar turno" no detalhe,
    com confirmação, nos mesmos estados em que o backend aceita.
C3. Motoboy: o detalhe do turno ganha "Finalizar" e "Cancelar" (hoje só estão nos cards) e, depois de finalizado,
    "Avaliar loja".
C4. Corrija nomeAvaliado: é o nome do lojista, não o título do turno (meus_turnos_screen e minhas_avaliacoes_screen).
    Se o Turno do app não trouxer o nome do lojista, use o dado que o backend já devolve ou o perfil público — não
    invente campo sem verificar TurnoResponse.
C5. Depois de finalizar, abra a avaliação para os DOIS papéis (hoje só o motoboy).
C6. Menu: a seção vira "AVALIAÇÕES" com o item "Avaliações" e um badge com o número de pendentes (igual ao das
    notificações). Dentro da tela, duas abas: "Para avaliar" (padrão quando houver pendentes) e "Recebidas".
C7. Histórico no desktop ganha as mesmas ações do celular (avaliar, e pagar se ainda existir).
C8. Avaliação no desktop: abra como diálogo de verdade (showDialog ou rota transparente com PageRouteBuilder opaque:
    false), com a tela de origem visível por trás. No celular, mantém tela cheia.
C9. Confira a regra de "pendente" do lojista em turno multi-vaga: turnosAvaliados não pode esconder o turno quando só
    parte dos entregadores foi avaliada.

### D. Consistência
D1. Um nome por conceito, igual em menu, título, botão e barra inferior. Proponha a tabela de nomes no plano (ex.:
    "Buscar turnos" / "Meus turnos" / "Histórico") e aplique.
D2. Estados de carregando, vazio e erro com os mesmos componentes em todas as telas tocadas (EmptyState/InlineEmpty),
    sempre com uma ação (recarregar, voltar, ir para…).
D3. Não mude a identidade visual (cores, fontes, gradiente) nem o layout das telas que não fazem parte destes itens.

## Testes (obrigatórios)
- Teste de navegação por papel e por largura (celular 390px e desktop 1280px): para cada item do menu e da barra
  inferior, a tela certa abre, o item certo fica destacado, e existe saída (voltar ou menu) — nenhuma rota termina em
  pilha vazia.
- Teste que falha se alguma tela voltar a declarar um switch próprio de barra inferior (ou se AppBottomNav receber
  papel diferente do usuário logado).
- Notificação de cada referenciaTipo abre o destino certo.
- Motoboy e lojista chegam a "avaliar" a partir de: detalhe do turno, notificação, painel de pendências, Avaliações e
  Histórico (desktop e celular).
- Teste que varre os widgets das telas e falha em onTap/onPressed vazio.
- Atualize o menu_completo_test e regrave só os goldens das telas alteradas.

## Documentação
docs/ux/NAVEGACAO.md: mapa de telas por papel (diagrama Mermaid), a regra push × replace, a tabela de nomes, e onde fica
cada ação pós-turno. Atualize o README se citar rotas removidas.

## Forma de trabalho
1. Plano primeiro: arquivos a criar/alterar, o NavConfig, a tabela de nomes, a decisão do botão Contatar (B2) e
   qualquer ponto que dependa do backend. Espere minha aprovação.
2. Commits temáticos em português (navegação estrutural; botões mortos; hub pós-turno e avaliações; consistência; testes
   e docs).
3. Final: flutter analyze sem avisos novos, flutter test verde, e um resumo com a lista da varredura B7.
````

---

## 6. Ordem sugerida com os outros prompts

1. **Este (navegação/UX)** primeiro: é só app, não depende do backend novo e destrava a navegação para testar o resto.
2. **Financeiro** depois. Ele remove a dupla confirmação; o item C1 deste prompt já está escrito para não recriar esses
   botões.
3. **Fiscal** por último.

Se preferir o financeiro antes, funciona igual: o prompt de UX verifica o estado do fluxo de pagamento antes de mexer.
