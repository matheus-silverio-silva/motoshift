# MotoShift — Revisão do financeiro + prompts para o Claude Code

Revisão feita sobre `main` (`cefbb5f`) do repositório `matheus-silverio-silva/motoshift`, 19/09/2026.

> **Atualização:** depois desta revisão entrou em `main` o PR #7 (V8–V11). Ele já resolveu os achados 1 e 2 da tabela
> (enums `TipoTransacao`/`StatusTransacao` e `idempotencyKey` preenchida) e criou FKs. **O problema central continua:**
> `PagamentoTurnoService` credita o entregador sem debitar o lojista, e nada reserva, recarrega ou estorna. Os prompts
> abaixo já foram ajustados: as migrações novas começam na **V12**.

> **Antes de rodar qualquer prompt:** a pasta local (`C:\Projetos\stitch_log_stica_urbana_agendada`) ainda está na branch
> `feat/carteira-liquidacao-automatica`, **atrás de `main`** — não tem a V7, o `NotaFiscalService` nem a tela
> `notas_fiscais`. Faça `git checkout main && git pull` e crie a branch a partir dali, senão o Claude Code vai
> reimplementar a nota fiscal que já existe e o merge vai conflitar.

---

## 1. O que a revisão encontrou

### O dinheiro do entregador surge do nada (o problema central)

`PagamentoTurnoService.liquidarInscricao` → `creditarCarteira` **soma** o valor no saldo do motoboy e não **debita
ninguém**. Não existe no backend um único ponto que:

- faça a **reserva** ao publicar o turno (`saldoBloqueado` existe na entidade, na V4 e na tela, mas nunca é movimentado);
- **debite** o lojista na liquidação (o tipo `pagamento_enviado` só existe em comentário e no enum do app);
- permita ao lojista **colocar dinheiro** na carteira (não há endpoint de `recarga`);
- **devolva** a reserva em cancelamento/expiração (`liberacao_reserva`, `estorno` também são só comentário).

Consequência: somando todas as carteiras, o total cresce a cada turno pago. Isso é a primeira coisa que uma banca
perguntaria sobre uma "carteira digital", e hoje não há resposta.

### O pagamento ainda é a dupla confirmação manual

O fluxo continua sendo "lojista declara que pagou" + "motoboy declara que recebeu" (`confirmarPagamentoLojista` /
`confirmarRecebimentoMotoboy`). O que você quer — **terminou o turno, a plataforma paga com o saldo do lojista** — não
existe. A decisão anterior (reservar na publicação, gateway simulado atrás de interface) nunca chegou ao código.

### Outros achados do financeiro

| # | Onde | Problema |
|---|------|----------|
| 1 | `Transacao.tipo` / `status` | Strings livres com duas gerações convivendo (`turno`/`pagamento_recebido`, `processado`/`concluido`); `CarteiraService` tem listas só para reconciliar. |
| 2 | `idempotencyKey` | Coluna única criada na V4, **nunca preenchida** por nenhum caminho. |
| 3 | `marcarTransacaoProcessada` | Varre o extrato inteiro do motoboy em memória para achar a pendente. |
| 4 | `@Version` na carteira | O conflito vira 409 no `ApiExceptionHandler`, mas nenhuma operação de dinheiro tenta de novo nem tem chave para repetir com segurança. |
| 5 | Saque | Sai do saldo e fica `concluido` na hora — sem estado intermediário, sem gateway simulado, sem comprovante. |
| 6 | Extrato | `GET /carteira/{id}` devolve **todas** as transações, sem paginação nem filtro. O filtro do app (todos/entradas/saques) é só no desktop e só no cliente. |
| 7 | `CarteiraService.grafico` | Carrega o extrato inteiro e agrupa por mês em memória. |
| 8 | `RelatorioService` | "Ganhos" são somados de `Turno.valorEstimado` dos turnos finalizados — não do extrato. Turno finalizado e não pago conta como ganho. |
| 9 | Multi-vaga | Turno de 3 vagas com 2 preenchidas: nada trata o valor da vaga vazia (que deveria voltar ao lojista). |
| 10 | Tela `saldo_lojista` | Mostra "indisponível" e calcula o comprometido no cliente, porque não há carteira de lojista no backend. |
| 11 | `finalizar` | Qualquer participante finaliza. Com pagamento automático, isso passa a mover dinheiro — a regra precisa ser explícita. |

### Fiscal (o que já existe em `main`)

A V7 criou `notas_fiscais` com uma NFS-e **por par (turno, entregador)**, ISS 5% e IRRF 1,5% configuráveis, emissão
idempotente e cancelamento. O que falta para o que você descreveu:

- a nota **não está ligada ao extrato** — não dá para abrir um lançamento e gerar a nota dele;
- só existe documento para pagamento de turno; recarga, saque e estorno não geram comprovante nenhum;
- o `valorLiquido` da nota desconta ISS e IRRF, mas o entregador é creditado pelo **valor cheio** → nota e extrato
  discordam;
- não há PDF/visualização imprimível, nem marca clara de "documento simulado".

---

## 2. Como usar

São **dois prompts, em sequência**. O fiscal depende do extrato (ledger) que o primeiro cria. Rode o Prompt 1, revise,
rode os testes, faça o merge — e só então o Prompt 2. Os dois pedem plano antes de código; aprove o plano antes de ele sair
escrevendo.

---

## 3. PROMPT 1 — Financeiro: liquidação automática com saldo, transferências reais, relatórios e filtros

````text
Contexto: MotoShift, TCC. Backend Spring Boot + PostgreSQL (Flyway, V1–V7) em backend/, app Flutter web em Motoshift/.
Trabalhe a partir de main atualizada, numa branch nova: feat/financeiro-ledger.

Leia antes de planejar: backend/.../entity/{Carteira,Transacao,Turno,TurnoInscricao}.java,
service/{CarteiraService,PagamentoTurnoService,TurnoService,TurnoExpiracaoService,RelatorioService,DashboardService,NotaFiscalService}.java,
controller/{CarteiraController,TurnoController}.java, db/migration/V4 e V7, docs/revisao/REVISAO-2026-09-16.md,
e no app: models/{carteira,transacao}.dart, services/api/carteira_api.dart, views/{carteira,saldo_lojista,dashboard_lojista}.

## Problema
Hoje a liquidação credita o entregador sem debitar o lojista: o dinheiro aparece do nada. saldoBloqueado nunca é
movimentado, não há recarga, reserva, débito nem estorno, e o pagamento ainda depende da dupla confirmação manual.
Quero que o dinheiro exista de verdade dentro do app: entra por recarga, fica reservado quando o turno é publicado,
é transferido do lojista para o entregador quando o turno termina, e sai por saque.

## Regras de negócio (decididas — não mude sem me perguntar)
1. Recarga: o lojista adiciona saldo por um gateway SIMULADO atrás de uma interface (GatewayPagamento, com
   GatewayPagamentoSimulado). Fluxo: criar cobrança Pix fictícia (status PENDENTE, código copia-e-cola falso) →
   confirmar via endpoint que simula o webhook → crédito no disponível. A confirmação é idempotente.
2. Publicar turno RESERVA valorEstimado × vagas: disponível → bloqueado. Sem saldo suficiente, a publicação falha com
   422 e mensagem que diga quanto falta. Nada de turno publicado sem lastro.
3. Finalizar turno LIQUIDA automaticamente, na mesma transação, para cada inscrição finalizada:
   bloqueado do lojista → disponível do entregador. Gera os dois lados no extrato (pagamento_enviado para o lojista,
   pagamento_recebido para o entregador), com a mesma operacaoId. O que foi reservado para vagas não preenchidas volta
   ao disponível do lojista (liberacao_reserva).
4. Cancelar turno ou expirar (job de TurnoExpiracaoService) libera a reserva inteira (liberacao_reserva).
   Mantenha a penalidade de score do cancelamento tardio; não invente multa financeira.
5. A dupla confirmação de pagamento deixa de existir como condição de pagamento. Remova os endpoints de confirmar
   pagamento/recebimento e as colunas lojista_confirmou_em/motoboy_confirmou_em de turno_inscricoes (migração de
   contract separada, no mesmo padrão expand/contract da V5/V6, com comentário explicando). Ajuste o app.
6. Quem pode finalizar: mantenha os dois participantes, mas deixe explícito no código e no doc que o dinheiro já estava
   reservado — finalizar só transfere o que o lojista comprometeu ao publicar.
7. Saque: do disponível do entregador (ou do lojista) para a chave Pix, pelo mesmo gateway simulado.
   Estados: SOLICITADO → CONCLUIDO (ou FALHOU → estorno automático ao disponível). Mínimo de R$ 20,00 mantido.
8. Transferência entre usuários fora de turno NÃO entra neste escopo.

## Modelo de dados (migração V12, aditiva — main já vai até a V11)
- TipoTransacao e StatusTransacao já existem (V10). Reaproveite-os; acrescente só o que faltar (ex.: status falhou/
  estornado) e confira se ainda sobra alguma lista de compatibilidade de tipos/status legados para apagar.
- Novas colunas em transacoes: operacao_id (UUID que agrupa os dois lados de uma transferência), saldo_disponivel_apos
  e saldo_bloqueado_apos (snapshot para o extrato mostrar saldo linha a linha), natureza (credito|debito — o sinal não
  pode depender do app adivinhar pelo tipo).
- idempotency_key já é preenchida desde a V10: siga o formato que existe para os lançamentos novos
  (reserva, liquidação, recarga, saque, estorno). Repetir a operação devolve o resultado anterior, não move dinheiro de novo.
- Tabela cobrancas (recargas e saques no gateway simulado): id, usuario_id, tipo, valor, status, codigo_pix,
  criada_em, concluida_em, idempotency_key.
- FKs reais nas tabelas novas, no padrão da V11 (cobrancas → usuarios; transacoes.operacao_id não precisa de FK).

## Arquitetura
- Crie um LedgerService como ÚNICO lugar do backend que altera saldo. Toda mutação passa por ele:
  lança a(s) transação(ões), atualiza a carteira, grava o snapshot de saldo, respeita a idempotência. CarteiraService,
  PagamentoTurnoService e TurnoService chamam o LedgerService; nenhum deles faz setSaldo* diretamente.
- Trate ObjectOptimisticLockingFailureException com retry curto (3 tentativas) dentro das operações do ledger —
  seguro porque a idempotency_key impede o duplo lançamento.
- Invariantes, validadas por teste e por um método verificarConsistencia() exposto só em perfil dev:
  (a) nenhum saldo negativo; (b) saldo da carteira = soma dos lançamentos concluídos daquele usuário;
  (c) soma de todas as carteiras = recargas concluídas − saques concluídos (a plataforma não cria nem destrói dinheiro).

## API (todas autenticadas, dono pelo token, nunca pelo corpo)
- POST /api/carteira/recargas            → cria cobrança simulada
- POST /api/carteira/recargas/{id}/confirmar → simula o webhook (idempotente)
- POST /api/carteira/saques              → substitui o /{usuarioId}/saque atual (mantenha o antigo como @Deprecated
                                             delegando para o novo até o app migrar)
- GET  /api/carteira/extrato  com paginação (Pageable) e filtros: dataInicio, dataFim, tipos (lista), status,
       natureza (credito|debito), turnoId, contraparteId, valorMin, valorMax, busca (texto na descrição).
- GET  /api/carteira/resumo?dataInicio&dataFim → entradas, saídas, líquido do período, disponível, bloqueado,
       a receber (entregador: turnos aceitos ainda não finalizados), comprometido (lojista: reservas abertas),
       quebra por tipo.
- GET  /api/carteira/extrato/exportar?formato=csv (mesmos filtros).
- GET  /api/carteira/fluxo?agrupamento=dia|semana|mes&dataInicio&dataFim → série para gráfico, feita com GROUP BY no
       banco (substitui o agrupamento em memória do grafico atual).
- GET /api/carteira/{usuarioId} continua existindo para não quebrar o app, mas devolve só a primeira página do extrato.

## Relatórios
- RelatorioService passa a apurar ganhos/gastos pelo EXTRATO (pagamento_recebido/pagamento_enviado concluídos), não por
  Turno.valorEstimado.
- Relatório do entregador: ganhos por período, por lojista, por dia da semana e faixa de horário, ticket médio por turno,
  valor por hora trabalhada, saques do período.
- Relatório do lojista: gasto por período, por entregador, custo médio por turno e por hora, reservas abertas,
  recargas do período, turnos cancelados/expirados e quanto foi devolvido.
- A leitura por IA continua, mas recebendo esses números; se a IA falhar, o endpoint devolve os números com
  analise = null em vez de 503.

## App Flutter
- Carteira do lojista de verdade: saldo_lojista_screen para de mostrar "indisponível" e usa o backend
  (disponível, bloqueado, reservas por turno). Botão "Adicionar saldo" com a cobrança Pix simulada
  (QR/código fictício + botão "Simular pagamento").
- Publicar turno mostra o custo total (valor × vagas) e o saldo disponível antes de confirmar; sem saldo, oferece recarga.
- Extrato unificado para os dois papéis, mobile e desktop: filtros por período (atalhos: 7 dias, 30 dias, mês atual,
  mês anterior, personalizado), tipo, entrada/saída, status, turno e contraparte; paginação infinita; saldo após cada
  lançamento; agrupamento por dia. O filtro sai do cliente e vai para a API.
- Detalhe do lançamento: tipo, valor, data, status, contraparte, turno (com link), operacaoId, saldos antes/depois.
- Tela de relatórios financeiros com o resumo do período, gráfico de fluxo (entradas × saídas) e exportar CSV.
- Remova do app os botões de confirmar pagamento/recebimento.
- O sinal/cor do lançamento vem de `natureza`, não de um switch sobre o tipo.

## Seed (DataInitializer)
Gere uma história coerente: lojistas com recarga, turnos publicados com reserva, turnos finalizados com liquidação,
um cancelado com estorno, um expirado, saques de entregadores. O seed também tem que passar em verificarConsistencia().

## Testes (obrigatórios, JUnit + Testcontainers/H2 conforme o projeto já usa)
- Publicar sem saldo → 422; publicar com saldo → disponível cai, bloqueado sobe.
- Finalizar turno de 3 vagas com 2 inscritos → 2 transferências + 1 liberacao_reserva; bloqueado volta a zero.
- Cancelar e expirar liberam a reserva inteira.
- Confirmar a mesma recarga duas vezes credita uma vez; finalizar/liquidar duas vezes transfere uma vez.
- Concorrência: duas liquidações simultâneas na mesma carteira terminam consistentes.
- Saque que falha no gateway simulado é estornado.
- Teste de invariante: após um cenário com dezenas de operações aleatórias, (a), (b) e (c) valem.
- Extrato: cada filtro isolado e combinados; paginação.
- No app: testes de widget do extrato filtrado e do fluxo de recarga; atualize os goldens afetados.

## Documentação (entregável, não opcional)
- docs/financeiro/FLUXO-FINANCEIRO.md: ciclo do dinheiro (recarga → reserva → liquidação → saque), diagramas Mermaid de
  sequência para publicar/finalizar/cancelar/expirar e de estados para cobrança e saque, tabela de tipos de lançamento
  com natureza e contraparte, as três invariantes e como são garantidas (transação, @Version + retry, idempotência).
- Atualize docs/DER (tabelas e migrações novas), README (endpoints novos) e o OpenAPI (@Operation em todos os endpoints novos).
- Comentários que envelheceram (ex.: "a V6 as remove num deploy posterior") devem ser corrigidos.

## Forma de trabalho
1. Primeiro me mostre o PLANO: lista de arquivos a criar/alterar, a V12 (e a migração de contract), e os pontos em que
   você precisou decidir algo não coberto acima. Espere minha aprovação.
2. Implemente em commits pequenos e temáticos (ledger e migração; publicar/finalizar/cancelar; recarga/saque;
   extrato e filtros; relatórios; app; docs), mensagens em português.
3. Ao final: mvnw test e flutter test verdes, e um resumo do que mudou e do que ficou de fora.
````

---

## 4. PROMPT 2 — Fiscal: documento (simulado) para cada lançamento do extrato

````text
Contexto: MotoShift. O Prompt anterior criou o ledger (LedgerService, TipoTransacao, natureza, operacaoId, cobrancas).
Já existe em main uma NFS-e simulada por (turno, entregador): V7, NotaFiscal, NotaFiscalService, NotaFiscalController,
views/notas_fiscais. Trabalhe numa branch nova a partir de main: feat/fiscal-extrato.
Leia esses arquivos e docs/financeiro/FLUXO-FINANCEIRO.md antes de planejar.

## Objetivo
Cada lançamento do extrato, do entregador e do lojista, tem um botão "Gerar documento" que produz o documento fiscal
ou comprovante correspondente. É tudo SIMULAÇÃO: nenhuma transmissão a prefeitura/Receita, nenhum certificado.
Todo documento leva, visível, a marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL" (no PDF, como marca d'água, e na tela).

## Qual documento para qual lançamento
| Lançamento                         | Documento                                   | Quem vê                     |
|------------------------------------|---------------------------------------------|-----------------------------|
| pagamento_recebido (entregador)    | NFS-e: prestador = entregador, tomador = lojista | os dois                  |
| pagamento_enviado (lojista)        | a MESMA NFS-e acima (não emitir uma segunda) | os dois                    |
| recarga                            | Recibo de recarga                            | o dono                      |
| saque                              | Comprovante de transferência Pix             | o dono                      |
| reserva / liberacao_reserva / estorno | Comprovante de movimentação               | o dono                      |
Reserva e liberação NÃO são serviço prestado: não geram nota fiscal, só comprovante. Deixe isso explícito no código.

## Modelo
- Reaproveite NotaFiscal para as NFS-e. Adicione transacao_id (o pagamento_recebido de origem) e operacao_id, para ligar a
  nota ao lançamento. A unicidade (turno_id, prestador_id) continua.
- Crie um "Comprovante" para o resto, sem tabela se possível: gerado sob demanda a partir da Transacao, com número
  derivado do id e código de autenticação derivado de forma estável (HMAC dos campos com uma chave de config) — o mesmo
  lançamento sempre gera o mesmo comprovante. Se precisar de tabela para numeração, justifique no plano.
- Migração aditiva (a próxima livre depois das do Prompt 1), com comentário no padrão das anteriores.

## Coerência nota × extrato (hoje discordam — corrija)
A NFS-e desconta ISS e IRRF no valorLiquido, mas o entregador é creditado pelo valor cheio. Implemente as duas opções atrás
de uma propriedade motoshift.fiscal.reter-na-fonte (default false):
- false: a nota mostra os tributos como "valor aproximado dos tributos" (informativo, estilo Lei 12.741/2012) e o
  valor líquido é igual ao valor do serviço — bate com o extrato;
- true: a liquidação credita o líquido ao entregador e gera um lançamento de retenção com o mesmo operacaoId.
Teste as duas.

## Regras
- Emissão idempotente: gerar duas vezes devolve o mesmo documento.
- NFS-e só para pagamento de turno CONCLUÍDO no extrato. Cancelar a nota é permitido (mantém o fluxo atual), mas
  não estorna dinheiro — documente isso.
- Autorização: só as partes do lançamento veem o documento. Teste 403 para terceiro.
- Numeração da NFS-e sequencial por prestador (já existe); a série fica em configuração.
- Dados do documento: prestador e tomador com nome, CPF/CNPJ mascarado (ex.: ***.456.789-**), cidade; discriminação do
  serviço (turno, data, horário, endereço/região); competência; código de verificação; operacaoId do extrato.

## API
- POST /api/carteira/transacoes/{id}/documento → emite (ou devolve o existente) e retorna o documento com um campo
  `tipoDocumento` (NFSE | RECIBO_RECARGA | COMPROVANTE_PIX | COMPROVANTE_MOVIMENTACAO).
- GET  /api/carteira/transacoes/{id}/documento
- GET  /api/notas-fiscais ganha filtros e paginação: papel (prestador|tomador), período de competência, status
  (emitida|cancelada), contraparte, turnoId.
- GET  /api/notas-fiscais/resumo?ano → para o entregador, "informe de rendimentos" anual simulado (total por tomador e
  por mês); para o lojista, total de serviços tomados por prestador. Exportável em CSV.
- TransacaoResponse ganha: documentoDisponivel (bool), tipoDocumento, documentoId (quando já emitido).

## App Flutter
- No extrato e no detalhe do lançamento: ícone/indicador de documento emitido e botão "Gerar nota fiscal" ou
  "Gerar comprovante" conforme o tipo.
- Visualização do documento no layout de uma NFS-e (cabeçalho, prestador, tomador, discriminação, valores, tributos,
  código de verificação) e "Baixar PDF"/"Imprimir" usando os pacotes pdf e printing (funcionam no Flutter web).
- A tela notas_fiscais existente ganha os filtros acima e a aba de informe anual.
- Marca de simulação sempre visível.

## Testes
- Cada tipo de lançamento gera o documento certo; reserva/liberação nunca geram NFS-e.
- Os dois lados de um pagamento recebem a mesma nota.
- Idempotência, autorização (403) e as duas configurações de retenção.
- Soma do informe anual = soma dos pagamento_recebido concluídos do ano.
- Widget test da visualização e golden do documento.

## Documentação
docs/financeiro/FISCAL.md: o que é simulado e o que uma integração real exigiria (padrão ABRASF/NFS-e Nacional,
certificado A1, RPS, prefeitura), tabela lançamento → documento, a decisão sobre retenção, e como trocar
NotaFiscalService por um cliente real sem mudar o modelo. Atualize DER, README e OpenAPI.

## Forma de trabalho
Plano primeiro (arquivos, migração, decisões em aberto) e espere aprovação. Commits temáticos em português.
Ao final, mvnw test e flutter test verdes e um resumo.
````

---

## 5. Decisões que tomei por você (mude no prompt se discordar)

- **Pagamento automático ao finalizar**, sem janela de contestação. Se quiser uma janela (ex.: 24 h para o lojista
  contestar antes de liberar), é uma linha nas regras do Prompt 1 — mas aumenta bastante o escopo.
- **Sem taxa da plataforma.** Se quiser que o MotoShift cobre uma comissão, dá para acrescentar ao Prompt 1 um
  lançamento `tarifa` configurável e, no Prompt 2, uma NFS-e da plataforma para o lojista.
- **Retenção de ISS/IRRF desligada por padrão**, para a nota e o extrato baterem sem complicar o saldo do entregador.
- **Sem transferência livre entre usuários** (fora de turno) — fica fora do escopo para não abrir uma superfície de
  fraude que o TCC não precisa defender.
