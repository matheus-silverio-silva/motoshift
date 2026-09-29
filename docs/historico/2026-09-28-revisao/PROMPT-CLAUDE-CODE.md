# Prompt — papéis do lojista e do entregador, nova massa e exportação em PDF

Revisão feita em 28/09/2026 sobre `feat/fiscal-extrato` (`826580e`, já com o
merge do PR #8), pela leitura do código. Não rodei o app. Os achados estão
no próprio prompt, em cada fase, com arquivo e trecho.

Cole tudo abaixo da linha no Claude Code, na raiz do repositório.

---

Você vai trabalhar no MotoShift (TCC; backend Spring Boot 3 em `backend/`, app
Flutter em `Motoshift/`). Estou no Windows: use `backend\mvnw.cmd` e `flutter`.
Leia antes: `README.md`, `docs/README.md`, `docs/financeiro/FISCAL.md`,
`docs/financeiro/FLUXO-FINANCEIRO.md`, `docs/ux/NAVEGACAO.md`.

## Regra que orienta tudo

**O entregador é prestador de serviço. O lojista é uma loja que contrata o
serviço.** Nenhuma tela deve mostrar a um deles um número, botão, filtro ou
rótulo que só faz sentido para o outro. Quando um componente é compartilhado,
ele recebe o papel e decide o que mostrar. Um valor zerado com o rótulo do
outro papel não resolve: esse valor simplesmente não aparece.

## Como trabalhar

- Crie a branch `feat/revisao-papeis-e-massa` a partir de `feat/fiscal-extrato`.
- Uma fase = um commit (mensagem em português, sem acento, no padrão do
  histórico). Ao fim de cada fase, rode `backend\mvnw.cmd test` e `flutter test`
  em `Motoshift/`. Só avance com tudo verde.
- Goldens: o CI roda em `windows-latest` com Flutter **3.41.5**. Regrave apenas
  os goldens cuja mudança for intencional, com essa mesma versão, e liste no
  commit quais foram regravados e por quê.
- Não relaxe nenhuma regra de negócio para a massa caber. A massa passa pelos
  serviços reais sempre que puder.
- Atualize a documentação de cada comportamento que mudar (FISCAL.md,
  GUIA_DEFESA.md, README, comentários de classe que ficarem mentindo).
- No final, me entregue um resumo por fase: o que mudou, o que você decidiu
  sozinho e o que ficou pendente.

## Fase 1 — Só o lojista emite a nota fiscal

Hoje os dois emitem, e só o prestador cancela:

- `NotaFiscalService.emitir`, `emitirParaPagamento` e `exigirParticipante`
  aceitam qualquer um dos lados.
- `NotaFiscalService.cancelar` exige o prestador.
- `DocumentoFiscalService.emitir` (`POST /api/carteira/transacoes/{id}/documento`)
  emite a NFS-e para quem chamar, inclusive o entregador pelo
  `pagamento_recebido`. No app, quem chama é `widgets/documento/botao_documento.dart`
  (`carteira.gerarDocumento`), no detalhe do lançamento, para os dois papéis.
- No app: a seção "A emitir" e o botão "Emitir" (`notas_fiscais_screen.dart`),
  `o_que_falta.dart`, `painel_pendencias.dart` e `pendencias_provider.dart`
  contam "notas a emitir" também para o entregador. `nota_fiscal_detalhe.dart`
  mostra "Cancelar" para `souPrestador`.
- A massa emite as notas como o entregador (`MassaDemonstracao.emitirNota`).

O que deve passar a valer:

1. **Emitir e cancelar: só o lojista (tomador) do turno.** O entregador que
   tentar recebe 403 com mensagem clara, tanto em `/api/notas-fiscais` quanto
   em `/api/carteira/transacoes/{id}/documento`.
2. **O documento continua com o entregador como prestador e o lojista como
   tomador.** O que muda é quem dispara a emissão. Registre isso em FISCAL.md:
   no mundo real, a NFS-e sai do prestador (MEI). Aqui a plataforma emite por
   conta dele, a pedido do tomador. Isso vai ser pergunta da banca.
3. **O entregador só visualiza, baixa o PDF e imprime.** Quando a nota do
   pagamento dele ainda não existe, a tela mostra "Aguardando emissão pelo
   lojista", sem botão. Para o entregador, o `botao_documento` usa o GET
   (`buscarDocumento`) e nunca o POST. Comprovantes (recarga, saque etc.)
   continuam como estão.
4. Nas pendências do entregador, "notas a emitir" deixa de existir. Se fizer
   sentido, troque por um contador informativo "aguardando emissão" que não
   pede ação.
5. Notificações: o entregador é avisado quando a nota dele é emitida e quando é
   cancelada (hoje o cancelamento avisa o tomador, com o texto "cancelada pelo
   prestador").
6. Testes: backend (403 para o entregador em emitir, cancelar e documento; o
   lojista emite e cancela) e app (entregador sem botões de emitir/cancelar).

## Fase 2 — Cada papel vê só o que é dele

Achados concretos:

- **Relatórios** (`relatorios_financeiros_screen.dart`, `_cartoesDeResumo`):
  os cartões "A receber" (só do entregador) e "Comprometido" (só do lojista)
  aparecem para os dois, zerados para quem não os tem. "Entradas/Saídas" também
  confundem: a "entrada" do lojista é recarga, não receita, e a "saída" do
  entregador é saque, não custo.
- **Filtro do extrato** (`extrato_filtros.dart` usa `TipoTransacao.filtraveis`):
  o entregador vê Recarga, Reserva, Liberação de reserva e Pagamento enviado; o
  lojista vê Pagamento recebido. Nenhum desses lançamentos existe para quem os
  vê.
- `ResumoFinanceiro` (app) e o `/resumo` (backend) servem os dois perfis com
  campos zerados.

O que deve passar a valer:

- **Entregador (prestador):** recebido por serviços, retenções (se
  `MOTOSHIFT_FISCAL_RETER_NA_FONTE` estiver ligado), sacado, disponível e a
  receber (turnos aceitos ainda não finalizados). Filtros: pagamento recebido,
  saque, estorno e retenções.
- **Lojista (tomador):** recarregado, pago a entregadores, devolvido
  (liberação de reserva e estorno), disponível e comprometido em turnos.
  Filtros: recarga, reserva, liberação de reserva, pagamento enviado e estorno.
- Tire a lista de tipos por papel de um lugar só no app (por exemplo,
  `TipoTransacao.filtraveisPara(papel)`) e use-a no filtro, no relatório e na
  exportação.
- Faça uma varredura das outras telas financeiras (`carteira_screen.dart`,
  `saldo_lojista_screen.dart`, os dashboards, o informe anual e o extrato no
  desktop) com a mesma regra. Liste o que encontrou e o que mudou. Se alguma
  coisa for ambígua, me pergunte em vez de decidir.

## Fase 3 — Exportar também em PDF

Hoje há três pontos de exportação, todos só em CSV:

- extrato (`extrato_screen.dart`, `/api/carteira/extrato/exportar`);
- relatórios (`relatorios_financeiros_screen.dart`, que reaproveita o CSV do
  extrato);
- informe anual (`notas_fiscais_screen.dart`, `/api/notas-fiscais/resumo/exportar`).

O que fazer:

- Troque cada botão "Exportar CSV" por um "Exportar" com duas opções:
  **Planilha (Excel/CSV)**, que mantém o que existe, e **PDF**.
- Gere o PDF no app com os pacotes `pdf` e `printing`, que já estão no projeto
  (veja `services/documento_pdf.dart`). Reaproveite as fontes em
  `assets/fonts/pdf` e a identidade visual do documento fiscal. Se precisar da
  lista completa sem paginação para o PDF, prefira um endpoint JSON
  equivalente ao do CSV, com os mesmos filtros, a baixar páginas em laço.
- O PDF traz cabeçalho (nome, papel, período e filtros aplicados), os mesmos
  números da tela, a tabela de lançamentos e, no informe anual, a marca
  "DOCUMENTO SIMULADO — SEM VALOR FISCAL".
- O conteúdo segue a Fase 2: o PDF do entregador não tem colunas de lojista, e
  vice-versa.
- Testes: um por PDF, verificando que é gerado e contém os totais esperados.

## Fase 4 — O que parece fixo: avaliações, score e perfis

Achados:

- **A média de avaliação da massa é um número inventado.**
  `MassaDemonstracao.conta()` grava `mediaAvaliacao` direto (Ricardo 4,8,
  Cláudia 4,8, Lucas 4,6), e as avaliações são salvas pelo repositório sem
  passar pelo `AvaliacaoService.atualizarMedia`. Resultado: o perfil mostra
  4,8, mas a tela de avaliações calcula 5,0 com as notas reais.
- **O score da massa também é inventado.** Os valores 4,7, 4,9, 3,1 e 5,0 não
  saem da regra (−0,5 por cancelamento tardio, `TurnoService`/`ScoreService`).
  O Thiago tem um cancelamento tardio e deveria estar em 4,5, não em 3,1.
- **O lojista tem score fixo em 5,0**, que nunca muda. Mesmo assim, o
  `PerfilPublicoResponse` o devolve e `perfil_publico_screen.dart` o exibe
  quando não é nulo.
- **Conta nova mostra "5.00 — Excelente"** sem histórico nenhum:
  `score ?? 5.0` em `dashboard_motoboy_screen.dart`, `models/usuario.dart`,
  `DashboardService` e `RelatorioService`.
- **Tags de avaliação iguais para os dois papéis** (`avaliacao_screen.dart`,
  `_tags`): "Carga bem embalada" e "Pagamento correto" não servem para avaliar
  um entregador, e "Pontual" serve mal para avaliar uma loja. Faça uma lista
  por papel de quem é avaliado. Sugestões:
  - para avaliar o entregador: Pontual, Cuidado com a carga, Educado, Conhece
    a região, Boa comunicação;
  - para avaliar a loja: Pedidos prontos no horário, Carga bem embalada,
    Endereços corretos, Boa comunicação, Pagamento correto.

O que fazer:

- Média e score sempre derivados dos dados, nunca gravados à mão (inclusive na
  massa: a Fase 5 cria as avaliações pelo serviço, ou recalcula no fim).
- Score só para o entregador; tire-o do perfil e das respostas do lojista.
- Sem histórico, mostre "Novo na plataforma" ou "Sem avaliações", nunca 5,0.
- Faça uma varredura geral atrás de outros valores fixos disfarçados de dado:
  literais numéricos em telas, `?? <número>` usado como padrão de exibição, e
  textos que citam fluxos que não existem mais. Liste o que encontrou; corrija
  o que for claro e me pergunte sobre o que não for.

## Fase 5 — Massa de demonstração nova e limpeza do banco

A massa (`config/MassaDemonstracao.java`) ainda carrega a época anterior ao
financeiro e ao fiscal:

- notificações que citam a dupla confirmação removida na V13 ("Confirme o
  pagamento e avalie", "Confirme o recebimento", "Aguardando o lojista",
  `pagamento_pendente`), além do comentário "Pendentes de pagamento";
- notas emitidas pelo entregador;
- só 30 dias de história, o que deixa o informe anual e o gráfico mensal
  pobres;
- média e score fixos (Fase 4).

Reescreva a massa para contar a história atual. Mantenha as contas de login
que o README documenta (`lojista@teste.com` e `motoboy@teste.com`, senha
`senha123`, e as outras `@teste.com`), porque estão no vídeo e na defesa.
Deve incluir:

- de 4 a 6 meses de história, com recargas, turnos pagos todo mês e saques,
  para os gráficos mensais e o informe anual terem forma;
- um turno multivaga com 2 ou 3 entregadores (uma nota por entregador);
- notas **emitidas pelo lojista**; uma nota cancelada pelo lojista; alguns
  pagamentos ainda sem nota, para aparecer "a emitir" do lado do lojista e
  "aguardando emissão" do lado do entregador;
- avaliações criadas pelo `AvaliacaoService` (ou média recalculada no fim),
  com notas variadas, algumas abaixo de 5, e comentários coerentes com as tags
  da Fase 4;
- score resultante da regra: pelo menos um entregador com cancelamento tardio;
- notificações apenas de tipos que o código atual gera, com textos atuais;
- a garantia que já existe: a massa termina passando em
  `ConsistenciaService.verificarConsistencia()`, e o `MassaDemonstracaoTest`
  continua cobrindo isso;
- tabela de contas do README atualizada.

**Limpeza dos dados antigos em produção (Railway):** o reset atual
(`MOTOSHIFT_SEED_RESET=confirmo`, em `ResetDaMassaNoBoot`) apaga só as contas
`@teste.com` e o que é delas. Quero também apagar as contas antigas que não
são da massa. Faça assim:

1. Crie um segundo modo explícito, `MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo`,
   que apaga **todos** os dados de negócio (todas as tabelas de domínio, na
   ordem das FKs, com DELETE e nunca DROP/TRUNCATE de schema), preserva o
   `flyway_schema_history` e recria a massa, tudo numa transação só. O log
   deve registrar as contagens antes e depois, e o aviso de remover a variável.
2. Não mude o modo `confirmo`, que continua apagando só a massa.
3. Teste de integração cobrindo os dois modos, incluindo "valor errado não faz
   nada".
4. Documente no README o passo a passo que **eu** vou executar no Railway:
   fazer o deploy desta branch, definir a variável, esperar o boot, conferir o
   log, remover a variável e fazer o redeploy. Você não executa nada contra
   produção.

## Fora do escopo

Não mexa no schema além do que alguma fase exigir (se precisar de migração,
crie a V15 e justifique no commit). Não troque bibliotecas, não mude a
navegação e não suba a versão do Flutter.
