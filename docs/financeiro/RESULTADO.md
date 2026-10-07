# Resultado financeiro — a DRE do MotoShift

Como o MotoShift responde "tive lucro?" para o entregador e para o lojista:
uma **DRE simplificada** (Demonstração do Resultado do Exercício), em regime de
caixa, que junta o que o extrato registrou com o que a pessoa informa.

É o requisito **RF13** (card SCRUM-47). O ciclo do dinheiro que passa pela
plataforma está em [`FLUXO-FINANCEIRO.md`](FLUXO-FINANCEIRO.md); os documentos
fiscais, em [`FISCAL.md`](FISCAL.md).

---

## 1. O problema que isto resolve

O ledger registra só o dinheiro que passa pela carteira. Isso basta para dizer
quanto entrou e quanto saiu — e não basta para dizer se valeu a pena.

- **Para o entregador**, "ganhos" era faturamento bruto. O combustível, a
  manutenção, o DAS do MEI e as contas fixas não apareciam em lugar nenhum:
  ele recebia R$ 485 num mês, gastava R$ 420 numa troca de relação e o app
  continuava dizendo "R$ 485 de ganhos".
- **Para o lojista**, o app mostrava quanto ele gastou com entregadores, mas
  não quanto as entregas renderam. Sem a taxa de entrega que ele cobra do
  cliente, todo mês era só custo.

A DRE leva a conta até a última linha: receita, o que se tira dela, e o
**resultado do período** — lucro, prejuízo ou equilíbrio.

## 2. As duas demonstrações

O papel vem do token. Cada linha diz de onde veio o número: **extrato** (a
plataforma registrou), **manual** (o usuário informou) ou **calculado**.

### 2.1 Entregador

```
  Pagamentos de turnos           pagamento_recebido                 [extrato]
  Gorjetas                       bonus                              [extrato]
= Receita bruta
  (−) Retenções na fonte         retencao_iss + retencao_irrf       [extrato]
  (−) DAS do MEI                 das_mei                            [manual]
= Receita líquida
  (−) Combustível                combustivel                        [manual]
  (−) Manutenção                 manutencao                         [manual]
= Margem de contribuição
  (−) Celular e internet         celular_internet                   [manual]
  (−) Seguro                     seguro                             [manual]
  (−) Parcela ou aluguel         parcela_ou_aluguel_veiculo         [manual]
  (−) Outra despesa              outra_despesa_entregador           [manual]
= Resultado do período           lucro (> 0), prejuízo (< 0), equilíbrio (= 0)
```

A ordem é a de uma DRE de verdade: primeiro sai o que é **tributo** (as
retenções e o DAS), depois o que **cresce com o trabalho** (combustível e
manutenção), e só então o que **existe trabalhando ou não** (as contas fixas).
A margem de contribuição, no meio, é o que cada turno deixa para pagar as
contas fixas — é dela que sai o ponto de equilíbrio.

O DAS está nas deduções, e não nas despesas fixas, embora o valor seja fixo
por mês: é tributo sobre a atividade, e a receita líquida é o que sobra depois
dele.

### 2.2 Lojista — a operação de entrega

```
  Receita de entregas            taxa_de_entrega_cobrada            [manual]
  (−) Custo dos entregadores     pagamento_enviado + bonus_enviado  [extrato]
  (−) Entregas fora do app       entrega_fora_do_app                [manual]
= Margem da operação
  (−) Outras despesas            outra_despesa_entrega              [manual]
= Resultado da operação de entrega
```

É a DRE **da entrega**, não da loja: o MotoShift não sabe o que a hamburgueria
vende. Ela responde uma pergunta menor e útil — "o que eu cobro de taxa paga o
que eu gasto para entregar?".

**`reserva` e `liberacao_reserva` não entram.** São o dinheiro do lojista
mudando de bolso dentro da própria carteira — de disponível para bloqueado e
de volta. O custo é o `pagamento_enviado`: o que de fato saiu para o
entregador. Contar a reserva seria contar o mesmo turno duas vezes, e contar a
liberação como receita faria um turno cancelado dar lucro. A recarga também
fica de fora, pelo mesmo motivo: é o lojista pondo o próprio dinheiro na
carteira.

A gorjeta aparece nos dois lados: é **receita** de quem recebe (`bonus`) e
**custo** de quem dá (`bonus_enviado`).

## 3. Regime de caixa

Vale **o dia em que o dinheiro entrou ou saiu**:

- no extrato, o `criadoEm` do lançamento **concluído** — o pagamento conta no
  dia em que o turno foi finalizado, não no dia em que foi trabalhado;
- no lançamento informado, a `data` que a pessoa preencheu — o dia em que
  pagou a conta.

Por que caixa, e não competência:

1. **Coerência com o informe anual.** O `InformeRendimentosService` já conta o
   rendimento pelo dia em que foi creditado. Duas telas do mesmo app não podem
   dizer que setembro rendeu valores diferentes.
2. **É como MEI e pessoa física pensam.** O entregador sabe quando pagou a
   gasolina; "a competência da manutenção" não é uma pergunta que ele se faz.
3. **Sem provisão.** Competência exigiria reconhecer despesa antes de pagar e
   receita antes de receber — contas a pagar, contas a receber, estorno de
   provisão. É um sistema contábil; esta é uma demonstração simplificada.

**Nada entra antes de acontecer.** A DRE nunca olha além de hoje: a conta que
vence no dia 20 não está paga no dia 7, mesmo que o período pedido vá até o
fim do mês.

**A data do pagamento é até hoje.** Pelo mesmo motivo, um lançamento não nasce
com data futura: `POST` e `PUT` respondem 400 — "No regime de caixa, o
lançamento entra no dia em que foi pago. Informe uma data até hoje." —, e o
seletor de data do formulário para em hoje. Antes o formulário aceitava até o
fim do ano seguinte: o lançamento era salvo e **sumia**, porque a lista só
mostra o que já conta, e não havia mais como editá-lo nem excluí-lo. O "até
quando" de um recorrente continua podendo ficar no futuro.

## 4. Por que o custo informado fica fora do ledger

Um **lançamento gerencial** (tabela `lancamentos_gerenciais`, migração V25)
**não é transação**: não entra em `transacoes`, não move saldo, não gera
documento fiscal e não aparece no extrato.

O motivo é o que o ledger promete. Ele registra só dinheiro que a plataforma
movimentou, e as três invariantes da seção 6 do
[`FLUXO-FINANCEIRO.md`](FLUXO-FINANCEIRO.md) dependem disso: "carteira =
extrato" e "a plataforma não cria nem destrói dinheiro" só valem porque cada
linha do extrato tem um movimento de saldo do outro lado. O combustível que o
entregador pagou no posto, a plataforma não viu passar — ela **ouviu falar**
dele. Se esse número digitado entrasse no extrato, as invariantes passariam a
depender da memória de alguém.

Por isso:

- a tabela é outra, e o serviço é outro (`LancamentoGerencialService`), sem o
  `LedgerService` entre as dependências;
- quem junta os dois mundos é o `DreService`, **só na leitura**;
- há um teste que confere: criar, editar e excluir lançamentos gerenciais não
  altera `saldoDisponivel` nem `saldoBloqueado`, e a conferência do
  `ConsistenciaService` continua sem divergência
  (`LancamentosGerenciaisForaDoLedgerTest`).

**De quem é.** Só o dono vê e mexe. O lançamento de outra pessoa responde
**404**, igual a um id que não existe — um 403 confirmaria que ele existe.

## 5. Categorias

Não existe coluna "tipo" (receita ou despesa). Cada categoria sabe o **papel**
a que pertence e o **grupo da DRE** em que entra; o sinal sai do grupo, e o
valor é sempre positivo.

| Categoria | Papel | Grupo |
|---|---|---|
| `combustivel` | entregador | custo variável |
| `manutencao` | entregador | custo variável |
| `das_mei` | entregador | dedução |
| `celular_internet` | entregador | despesa fixa |
| `seguro` | entregador | despesa fixa |
| `parcela_ou_aluguel_veiculo` | entregador | despesa fixa |
| `outra_despesa_entregador` | entregador | despesa fixa |
| `taxa_de_entrega_cobrada` | lojista | receita |
| `entrega_fora_do_app` | lojista | custo de entrega |
| `outra_despesa_entrega` | lojista | despesa operacional |

Categoria de outro papel é recusada com 400 — um lojista lançando combustível
é erro de quem chamou. O app nem chega a oferecer: o formulário é montado com
`GET /api/financeiro/categorias`, que devolve só as do papel do token.

O lançamento pode apontar para um **turno** (`turnoId`), desde que o usuário
tenha participado dele: o lojista que o publicou, ou o entregador que fez
check-in. E pode levar os **km** rodados, que alimentam o custo por km.

## 6. Recorrência

Conta fixa não se digita todo mês. Um lançamento **recorrente** é uma regra:
vale uma vez por mês, no dia do mês da `data` — ou no **último dia**, se o mês
for mais curto —, de `data` até `recorrente_ate`, ou sem fim.

- Uma conta de todo dia 31 vence em 28 de fevereiro (29 no bissexto): não some
  nem pula para março.
- A DRE conta as ocorrências **cujo dia cai dentro do período**. Num período
  de 1 a 15, a conta do dia 20 está em vigor, mas ainda não aconteceu.
- Não há uma linha gravada por mês. Gravar obrigaria a criar linhas no futuro
  ou a rodar um job para inventá-las; e excluir a regra apagaria só o futuro.

O cálculo é uma função pura (`service.Recorrencia`), sem banco e sem relógio,
testada nos cantos: dia 31 em fevereiro, período de meio mês e recorrência que
termina antes do fim do período.

### 6.1 Editar sem reescrever o passado

Como o recorrente é uma regra, trocar o valor dela trocava **todos os meses**:
o seguro que subiu em outubro mudava o resultado de julho. O `PUT` aceita o
campo opcional `aplicarAPartirDe` (uma data até hoje):

- **com ele**, num recorrente que já aconteceu antes dessa data, o lançamento
  antigo é encerrado na véspera (`recorrente_ate`) e um **novo** é criado com
  os dados enviados, começando na primeira ocorrência a partir da data. Os dois
  na mesma transação; a resposta é o novo. Os meses anteriores continuam com o
  valor antigo, e a DRE de um período que atravessa a troca soma os dois;
- **sem ele**, a edição corrige o histórico inteiro, como sempre foi.

No app, salvar a edição de um recorrente que começou em mês anterior pergunta
"A mudança vale a partir de quando?": **Aplicar a partir deste mês** (o padrão,
que manda o dia 1º do mês corrente) ou **Corrigir todos os meses**.

Quando o dia do recorrente ainda não chegou neste mês, a regra nova começa no
futuro. Ela não conta em período nenhum, mas a lista a mostra à frente — "Começa
em 20/10/2026 · ainda não conta" —, para poder ser conferida, corrigida ou
excluída. O mesmo vale para o que foi gravado com data futura antes de isso
ser recusado: aparece na lista de todo período que chega até hoje, com zero
ocorrências, e a soma da lista continua igual à da DRE.

## 7. Indicadores

**Entregador**

| Indicador | Conta |
|---|---|
| Margem líquida | resultado ÷ receita bruta (nula sem receita) |
| Turnos pagos | pagamentos recebidos no período |
| Horas trabalhadas | duração dos turnos pagos — a mesma regra do relatório (`LancamentosDoExtrato`) |
| Lucro por hora | resultado ÷ horas trabalhadas |
| Lucro por turno | resultado ÷ turnos pagos |
| Custo por km | custos variáveis ÷ km informados (nulo sem km) |
| Ponto de equilíbrio | despesas fixas ÷ margem de contribuição média por turno, **arredondado para cima** |

O **ponto de equilíbrio** é quantos turnos pagam as contas fixas do período.
Se a margem por turno for zero ou negativa, não há ponto de equilíbrio — cada
turno a mais aumenta o buraco —, e o número vem **nulo**, com o motivo: "a
margem por turno não cobre os custos variáveis". Um "9999 turnos" seria um
número, e esconderia que a conta não fecha.

**Lojista**

| Indicador | Conta |
|---|---|
| Custo sobre a receita | (entregadores + entregas fora do app) ÷ receita de entregas (nulo sem receita) |
| Turnos finalizados | turnos com pagamento no período |
| Custo médio por turno | custo dos entregadores ÷ turnos |
| Resultado por turno | resultado ÷ turnos |
| Gorjetas dadas | `bonus_enviado` do período |

## 8. Período, comparação e gráfico

- **Período.** Sem datas, o mês corrente até hoje — o mesmo `Periodo` do
  relatório. Na tela, os atalhos (7 dias, 30 dias, mês atual, mês anterior) ou
  um mês escolhido no gráfico.
- **Comparação.** O período imediatamente anterior, com o **mesmo número de
  dias**. A variação do resultado vem em **reais**: percentual sobre resultado
  negativo engana (de −100 para −50 "melhora 50%"; de −100 para +100 daria
  "−200%").
- **Gráfico mensal.** `GET /api/financeiro/dre/mensal?ano` devolve doze linhas
  com receita, custos e resultado. Na tela, cada mês é um botão: tocar nele
  apura aquele mês.

A situação **nunca é só uma cor**: a faixa do topo diz por extenso ("Lucro de
R$ 106,95 no período"), com ícone e rótulo; o resultado de cada mês leva o
sinal escrito; e o gráfico tem um resumo em texto para o leitor de tela.

Na tela e no PDF:

- **Linhas sem valor ficam de fora.** A retenção na fonte de quem não tem
  retenção, o seguro de quem não tem seguro. Subtotais e resultado aparecem
  sempre. O backend continua mandando todas as linhas (as chaves são
  estáveis); na tela, "Mostrar todas as linhas" as devolve, e o PDF diz que
  omitiu.
- **Indicador negativo muda de nome.** "Lucro por hora" e "Lucro por turno"
  viram "Prejuízo por hora" e "Prejuízo por turno", com o valor sem sinal; na
  loja, "Resultado por turno" vira "Prejuízo por turno". A cor é a da faixa de
  situação e só reforça o rótulo.
- **O valor digitado é mostrado como foi lido.** "1.500" é mil e quinhentos, e
  embaixo do campo aparece "= R$ 1.500,00" antes de salvar. Com vírgula, o
  ponto é milhar; sem vírgula, ponto seguido de exatamente três dígitos (em um
  ou mais grupos) é milhar; qualquer outro ponto é decimal ("12.5", "0.75").
  No preço do litro e no consumo, três casas depois do ponto são decimais
  ("5.899").
- **No painel.** Os dois painéis têm o cartão "Resultado do mês", com a
  situação por extenso e o mesmo selo desta tela; tocar abre o resultado. Sem
  nada informado no mês, o cartão convida a informar os custos e abre o
  formulário. Se a DRE não responde, o cartão some e o painel continua.

## 9. Um exemplo, tirado da massa de demonstração

A massa é datada a partir do dia em que é criada. Os dois casos estão sempre
no **mês passado** (lucro) e no **mês retrasado** (prejuízo); os números
abaixo são os de uma massa criada em **outubro de 2026**.

**Carlos (`motoboy@teste.com`), entregador** — um turno por semana para o
Mercado Andrade:

| | Setembro/2026 | Agosto/2026 |
|---|---:|---:|
| Pagamentos de turnos | 385,00 | 485,00 |
| = Receita bruta | 385,00 | 485,00 |
| (−) DAS do MEI | 86,05 | 86,05 |
| = Receita líquida | 298,95 | 398,95 |
| (−) Combustível (R$ 7,50 por turno, 42 km) | 30,00 | 37,50 |
| (−) Manutenção | 0,00 | 420,00 |
| = Margem de contribuição | 268,95 | −58,55 |
| (−) Celular (35) + seguro (32) + parcela (95) | 162,00 | 162,00 |
| **= Resultado** | **+106,95 (lucro)** | **−220,55 (prejuízo)** |
| Margem líquida | 27,78% | −45,47% |
| Ponto de equilíbrio | 3 turnos | — |

Em agosto ele trabalhou **mais** (cinco turnos, contra quatro) e teve
prejuízo: a troca da relação e do pneu custou mais do que o mês rendeu. É o
que o faturamento sozinho não mostrava. E o ponto de equilíbrio de setembro —
3 turnos — diz que ele precisou de três dos quatro turnos do mês só para pagar
as contas fixas.

**Cláudia (`claudia@teste.com`), lojista** — a Hamburgueria da Cláudia:

| | Setembro/2026 | Agosto/2026 |
|---|---:|---:|
| Receita de entregas (taxas cobradas) | 1.456,00 | 192,00 |
| (−) Pagamentos e gorjetas a entregadores | 920,00 | 530,00 |
| (−) Entrega fora do app | 45,00 | 0,00 |
| = Margem da operação | 491,00 | −338,00 |
| (−) Outra despesa de entrega | 60,00 | 0,00 |
| **= Resultado** | **+431,00 (lucro)** | **−338,00 (prejuízo)** |
| Custo sobre a receita | 66,28% | 276,04% |

Em agosto ela fez uma promoção de frete grátis: só 6 entregas por noite
pagaram a taxa de R$ 8, e os entregadores custaram o mesmo de sempre.

## 10. API

| Método | Rota | O que faz |
|---|---|---|
| GET | `/api/financeiro/dre?dataInicio&dataFim` | A DRE do período, os indicadores e a comparação com o período anterior |
| GET | `/api/financeiro/dre/mensal?ano` | Doze meses: receita, custos e resultado |
| GET | `/api/financeiro/categorias` | As categorias do papel do token |
| GET | `/api/financeiro/lancamentos?dataInicio&dataFim` | Os lançamentos que contam no período (paginação opcional) |
| POST | `/api/financeiro/lancamentos` | Informar um custo ou uma receita |
| PUT | `/api/financeiro/lancamentos/{id}` | Editar. Com `aplicarAPartirDe` num recorrente, preserva os meses anteriores e responde o lançamento novo (seção 6.1) |
| DELETE | `/api/financeiro/lancamentos/{id}` | Excluir |

Todas exigem token. Nenhuma recebe id de usuário nem papel: os dois saem do
token.

O relatório por IA (`/api/relatorio/...`) passou a trazer `resultadoDoPeriodo`,
`situacao`, `margemLiquida` e `pontoDeEquilibrioTurnos` (entregador) ou
`custoSobreReceita` (lojista) — lidos da DRE, sem recalcular. A IA comenta o
resultado, e não só o faturamento; se nada foi informado à mão no período, ela
é instruída a dizer que o resultado ignora custos não informados.

## 11. O que fica de fora

- **Regime de competência.** Ver a seção 3.
- **Depreciação contábil.** Não há cálculo de desgaste da moto. A parcela ou o
  aluguel do veículo fazem o papel dela: é o que o veículo custa por mês em
  dinheiro.
- **Taxa da plataforma.** O MotoShift não tem receita própria nesta fase: não
  cobra comissão, e por isso não há uma DRE da plataforma nem linha de taxa
  nas DREs dos usuários.
- **A loja inteira.** A DRE do lojista é a da operação de entrega. Venda,
  insumo e folha da loja não são assunto do MotoShift.

## 12. Onde olhar no código

| O quê | Onde |
|---|---|
| A DRE dos dois papéis | `service/DreService.java` |
| Lançamentos gerenciais | `service/LancamentoGerencialService.java`, `entity/LancamentoGerencial.java` |
| Categorias e grupos | `entity/CategoriaLancamento.java`, `entity/GrupoDre.java` |
| Recorrência | `service/Recorrencia.java` |
| Período e horas trabalhadas (comuns ao relatório) | `service/Periodo.java`, `service/LancamentosDoExtrato.java` |
| Rotas | `controller/DreController.java`, `controller/LancamentoGerencialController.java` |
| Tabela | `db/migration/V25__lancamentos_gerenciais.sql` |
| Tela | `Motoshift/lib/views/resultado/` |
| PDF | `Motoshift/lib/services/relatorio_pdf.dart` (seção "Demonstração do resultado") |

### Testes que sustentam este documento

| Teste | O que prende |
|---|---|
| `DreServiceTest` | Lucro, prejuízo, equilíbrio e período vazio; reserva e liberação fora; gorjeta nos dois lados; retenções; período anterior; ponto de equilíbrio nulo; data futura recusada; recorrente editado a partir de uma data, com a DRE que atravessa a troca; o que ainda vai começar aparece na lista sem contar |
| `RecorrenciaTest` | Dia 31 em fevereiro, período de meio mês, recorrência que termina antes, primeira ocorrência a partir de uma data |
| `LancamentoGerencialHttpTest` | CRUD, 404 para o de outro usuário, categoria do papel errado, turno alheio, 401 sem token, 400 para data futura, `aplicarAPartirDe` pelo HTTP |
| `telas/resultado_test.dart`, `telas/resultado_no_painel_test.dart`, `models/dre_test.dart` (app) | Linhas zeradas e o link, rótulos com resultado negativo, a pergunta ao editar um recorrente, o valor lido embaixo do campo, a data até hoje, o cartão dos painéis |
| `LancamentosGerenciaisForaDoLedgerTest` | Criar, editar e excluir não mexem em saldo nem nas invariantes |
| `RelatorioServiceTest` | Os números do relatório são os da DRE; a IA recebe o resultado e o aviso |
| `MassaDemonstracaoTest` | O mês de lucro e o de prejuízo existem, para o Carlos e para a Cláudia |
| `MigracoesPostgresTest` (V25) | Domínio das categorias, valor e km positivos, recorrência coerente |
| `test/telas/resultado_test.dart` | A faixa de situação, a calculadora de combustível, o período, o formulário |
| `test/models/dre_test.dart` | Parse com campos ausentes, a frase da situação, a conta do combustível |
| `test/goldens/resultado_screens_test.dart` | Entregador com lucro, com prejuízo e lojista — celular e desktop |
