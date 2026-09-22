# Documentos fiscais do MotoShift

> **O que este documento responde:** que papel cada lançamento do extrato gera,
> por que uma reserva não vira nota fiscal, o que exatamente é simulado aqui e
> o que faltaria para emitir uma NFS-e de verdade.

> ⚠️ **Tudo o que este documento descreve é SIMULAÇÃO.** Nenhum documento é
> transmitido a prefeitura ou à Receita Federal, não há certificado digital,
> RPS nem protocolo de autorização. Todo documento — em tela e no PDF — carrega
> a marca **DOCUMENTO SIMULADO — SEM VALOR FISCAL**, e a marca não é opcional:
> ela nasce no backend, em `DocumentoResponse.MARCA`, e o app a desenha em
> `MarcaSimulacao`, também no PDF, como marca d'água.

---

## 1. O problema que isto resolve

O extrato mostrava linhas — "Pagamento do turno: Turno Noite, R$ 200,00" — e
nada mais. Quem precisasse comprovar aquele dinheiro (para o contador, para o
imposto de renda, para si mesmo) tinha uma tela de aplicativo e uma captura.
Ao mesmo tempo, a NFS-e simulada que já existia era emitida a partir do
**turno**, não do pagamento: nota e extrato eram dois caminhos separados
contando a mesma história, e nada obrigava os dois a concordarem.

Agora **cada lançamento concluído do extrato tem um documento**, e o documento
do pagamento é a nota fiscal — a mesma nota, ligada ao lançamento por
`transacao_id`. Não há como a nota dizer um valor e o extrato dizer outro: a
nota lê o pagamento.

---

## 2. Que documento cada lançamento gera

A tabela está codificada em `service/fiscal/TipoDocumento.java`, num lugar só.

| Lançamento | Documento | Quem pode ver |
|---|---|---|
| `pagamento_recebido` (entregador) | **NFS-e** | as duas partes |
| `pagamento_enviado` (lojista) | **a MESMA NFS-e** | as duas partes |
| `recarga` | Recibo de recarga | o dono |
| `saque`, Pix concluído | Comprovante de Pix | o dono |
| `saque`, Pix recusado | Comprovante de movimentação | o dono |
| `reserva`, `liberacao_reserva` | Comprovante de movimentação | o dono |
| `estorno`, `retencao_iss`, `retencao_irrf`, `bonus` | Comprovante de movimentação | o dono |
| qualquer lançamento **não concluído** | nenhum | — |
| `saque` com Pix ainda **pendente** | nenhum ainda | — |

### Reserva e liberação não são serviço prestado

É a regra que mais importa aqui, e a que seria mais fácil errar. Reservar é o
lojista separar o **próprio** dinheiro — do disponível para o bloqueado —, e
liberar é esse dinheiro voltar. Ninguém prestou nada a ninguém, o dinheiro não
mudou de dono e não há base de cálculo. Emitir NFS-e nesses casos documentaria
um serviço inexistente e tributaria movimento interno de caixa.

Por isso reserva e liberação geram **comprovante**, nunca nota. NFS-e existe
para uma coisa só neste sistema: o pagamento de um **turno concluído**, que é
serviço de entrega prestado pelo entregador ao lojista.

### O saque pendente não tem comprovante

Um comprovante de Pix emitido antes de o banco responder afirmaria uma
transferência que ainda pode ser recusada. Enquanto a cobrança está `PENDENTE`,
o lançamento não oferece documento; quando ela falha e o estorno entra, o que
existe é um comprovante de movimentação, que é o que de fato aconteceu.

---

## 3. Nota fiscal e comprovante são coisas diferentes

|  | NFS-e | Comprovante |
|---|---|---|
| Tabela | `notas_fiscais` | **nenhuma** — é derivado |
| Numeração | sequencial por prestador + série | derivada do id do lançamento |
| Autenticidade | código de verificação da "autoridade" | HMAC-SHA256 dos campos |
| Emissão | idempotente, grava | pura: mesmo lançamento, mesmo papel |
| Cancelamento | existe, e não estorna dinheiro | não existe (não há o que cancelar) |

O comprovante **não tem tabela** de propósito: ele não acrescenta fato nenhum
ao que a transação já registra. Guardá-lo seria manter duas cópias do mesmo
dado, com a segunda podendo divergir da primeira. O número (`RC-00000091`,
`PIX-00000104`, `MOV-00000055`) sai do id do lançamento, e o código de
autenticação é um HMAC-SHA256 dos campos com a chave
`motoshift.fiscal.chave-autenticacao`:

- o mesmo lançamento gera sempre o mesmo código — dá para conferir;
- lançamentos diferentes geram códigos diferentes;
- sem a chave, ninguém fabrica um código que a plataforma reconheça.

Trocar a chave muda o código de todos os comprovantes. É o comportamento
desejado: um comprovante antigo continua conferindo contra a chave com que
nasceu, e não contra a nova. Em produção a chave é obrigatória
(`MOTOSHIFT_FISCAL_CHAVE`); sem ela o boot falha, em vez de assinar com um
valor de exemplo que está no repositório.

---

## 4. Nota e extrato têm que concordar

A nota é emitida **a partir do lançamento** `pagamento_recebido`, e não do
turno. `NotaFiscalService.emitirParaPagamento` recebe a transação; o valor do
serviço é o valor do lançamento; a competência é a data do turno.

A emissão é **idempotente**: um índice único parcial (`uk_nota_transacao`, sobre
`transacao_id` onde ele não é nulo) impede uma segunda nota para o mesmo
pagamento, e pedir de novo devolve a que existe — inclusive quando ela está
cancelada. Cancelar não libera o pagamento para ser documentado de novo; o
banco não deixaria, e a intenção é essa.

### A pergunta difícil: o líquido da nota bate com o crédito do extrato?

Depende de uma decisão de negócio, e o sistema deixa as duas explícitas em
`motoshift.fiscal.reter-na-fonte`:

| `reter-na-fonte` | O que o extrato registra | O que a nota diz | Coerência |
|---|---|---|---|
| `false` (padrão) | crédito de R$ 200,00 | serviço R$ 200,00, líquido R$ 200,00, tributos **aproximados** (Lei 12.741/2012) | líquido = crédito |
| `true` | crédito de R$ 200,00 **e** `retencao_iss` −R$ 10,00, `retencao_irrf` −R$ 3,00 | serviço R$ 200,00, retenções R$ 13,00, líquido R$ 187,00 | líquido = crédito − retenções |

Com retenção ligada, as duas retenções entram **na mesma operação** do
pagamento (`operacao_id`), como lançamentos próprios do entregador. Não é
"crédito menor": é crédito cheio e duas saídas identificadas, que é o que um
informe de rendimentos precisa mostrar. O padrão é `false` porque o MotoShift
não é fonte pagadora com retenção obrigatória para autônomo — ligar a retenção
é uma decisão fiscal de quem opera a plataforma, não um default de código.

> A invariante (c) do ledger foi ajustada para isso: retenção é dinheiro que
> sai da plataforma, como o saque. Ver
> [`FLUXO-FINANCEIRO.md`](FLUXO-FINANCEIRO.md), seção 6.

---

## 5. Regras que valem para todo documento

**Autorização — só as partes veem.** `DocumentoFiscalService` compara o
usuário do token com o dono do lançamento (e, no pagamento, com a contraparte).
Qualquer terceiro recebe **403**, inclusive para lançamentos que existem: um
404 nesse caso ainda contaria que o lançamento existe.

**Cancelar a nota não estorna dinheiro.** O cancelamento é do prestador, marca
a nota como cancelada para as duas partes e **não devolve nada**: o serviço foi
prestado e o pagamento aconteceu, e está no extrato. Anular o pagamento seria
inventar um estorno que ninguém pediu. A numeração também não é reaproveitada —
a sequência tem buracos, como em qualquer talão.

**Numeração sequencial por prestador.** Cada prestador tem a própria sequência,
e a série vem de `motoshift.fiscal.nfse-serie` (padrão `A1`). Duas notas de
prestadores diferentes podem ter o mesmo número — o que identifica a nota é o
par prestador + número + série.

**Documento das partes sempre mascarado.** `DocumentoDaParte` devolve
`***.456.789-**` para CPF e `**.345.678/0001-**` para CNPJ. O entregador, no
cadastro atual, **não tem CPF** — o campo `documentoFederal` guarda a CNH —, e
o documento diz "CPF não informado no cadastro" em vez de exibir a CNH num
campo de CPF, que é o erro que qualquer preenchimento automático cometeria.

---

## 6. A API

| Método | Rota | O que faz |
|---|---|---|
| POST | `/api/carteira/transacoes/{id}/documento` | Emite — ou devolve, se já existir — o documento do lançamento |
| GET | `/api/carteira/transacoes/{id}/documento` | O documento já existente, sem emitir |
| GET | `/api/notas-fiscais` | Notas com filtros (`papel`, `status`, `competenciaDe/Ate`, `contraparteId`, `turnoId`) e paginação opcional |
| GET | `/api/notas-fiscais/resumo?ano=` | Informe anual simulado |
| GET | `/api/notas-fiscais/resumo/exportar?ano=` | O mesmo informe em CSV |

"Gerar" e "ver" são o mesmo pedido do ponto de vista de quem usa: como a
emissão é idempotente, o POST devolve 201 na primeira vez e 200 depois.

A listagem segue a convenção de paginação do projeto: o corpo continua sendo um
array, e o total vai no header `X-Total-Count`. Sem `pagina`, a resposta é a
lista inteira — o contrato antigo não quebrou.

### O informe anual sai do extrato, não das notas

`InformeRendimentosService` soma os **pagamentos** do ano (regime de caixa),
por contraparte e por mês, e informa ao lado quantos deles já viraram nota.
Somar as notas daria um número menor e errado: dinheiro recebido continua sendo
rendimento mesmo que a nota não tenha sido emitida. O informe mostra os dois
números justamente para que a diferença apareça.

---

## 7. O que existe aqui e o que faltaria numa emissão real

### Existe

- Modelo de dados com o que uma NFS-e precisa: partes, competência,
  discriminação do serviço, base de cálculo, alíquotas, tributos, valor
  líquido, número, série e código de verificação.
- Numeração sequencial por prestador e série configurável.
- Emissão idempotente, cancelamento com motivo, autorização por parte.
- PDF e impressão no app (pacotes `pdf` e `printing`), com a marca de
  simulação como marca d'água.

### Não existe (e é o que uma integração real exigiria)

| O que falta | Por quê |
|---|---|
| **Certificado digital A1/A3** do prestador | a NFS-e é assinada em XML (XMLDSig); sem certificado não há assinatura |
| **RPS** (Recibo Provisório de Serviços) e seu lote | é o que se envia ao município; o número do RPS é diferente do número da nota |
| **Webservice municipal** (padrão ABRASF) ou o **Ambiente Nacional da NFS-e** | cada município tem endpoint, layout e regras próprias; o número e o código de verificação passam a vir de lá |
| **Cadastro real do prestador** (CPF/CNPJ, inscrição municipal, CNAE, item da lista de serviços da LC 116/2003) | hoje o entregador não tem sequer CPF no cadastro |
| **Alíquota do município** e regime tributário (Simples, MEI) | as alíquotas aqui são de exemplo, fixas em configuração |
| **Retenções conforme a lei** | a retenção implementada é uma simulação da mecânica, não a regra fiscal aplicável |
| Consulta de situação, carta de correção, substituição | o ciclo de vida real de uma nota é maior que emitir e cancelar |

### Por onde a troca entraria

O ponto de extensão já está isolado, na mesma ideia do `GatewayPagamento` do
ledger:

```
NotaFiscalService  →  EmissorDeNotas (interface)  →  EmissorSimulado (hoje)
                                                  →  EmissorAbrasf (real, amanhã)
```

`EmissorDeNotas.autorizar(rascunho)` recebe a nota com partes, valores e
competência preenchidos e devolve `(numero, serie, codigoVerificacao)`. Uma
implementação real montaria o RPS a partir do rascunho, assinaria com o
certificado, enviaria ao município e devolveria o que a prefeitura atribuiu.
**Nenhuma coluna de `notas_fiscais` muda** — o modelo já é o que o provedor
precisaria —, e o resto do backend não sabe de que lado está a simulação.

O que **também** mudaria numa emissão real, e não é detalhe: a emissão
deixaria de ser síncrona. A prefeitura responde em lote, às vezes em minutos, e
a nota passaria a ter um estado "enviada, aguardando autorização" entre o
pedido e o número. O modelo de hoje não tem esse estado porque a simulação
autoriza na hora.

---

## 8. Onde olhar no código

| Assunto | Arquivo |
|---|---|
| Tabela lançamento → documento | `service/fiscal/TipoDocumento.java` |
| Emissão, autorização e 403 | `service/fiscal/DocumentoFiscalService.java` |
| Comprovantes e HMAC | `service/fiscal/ComprovanteService.java` |
| Fronteira com a "prefeitura" | `service/fiscal/EmissorDeNotas.java`, `EmissorSimulado.java` |
| Nota a partir do pagamento | `service/NotaFiscalService.java` |
| Alíquotas e retenção | `service/fiscal/CalculoTributario.java` |
| Retenção no ledger | `service/PagamentoTurnoService.java`, `service/ledger/Movimento.java` |
| Informe anual | `service/fiscal/InformeRendimentosService.java` |
| Máscara de CPF/CNPJ | `service/fiscal/DocumentoDaParte.java` |
| Migração | `db/migration/V14__fiscal_por_lancamento.sql` |
| App: tela do documento | `Motoshift/lib/views/documento_fiscal/`, `lib/widgets/documento/` |
| App: PDF e impressão | `Motoshift/lib/services/documento_pdf.dart` |

### Testes que sustentam este documento

| Arquivo | O que prende |
|---|---|
| `service/fiscal/TipoDocumentoTest.java` | a tabela da seção 2, incluindo reserva sem nota |
| `service/fiscal/DocumentoFiscalServiceTest.java` | idempotência, 403 para terceiro, saque pendente sem documento |
| `service/fiscal/RetencaoNaFonteTest.java` | com retenção: o bruto no extrato, as duas saídas na mesma operação, a nota batendo com o saldo |
| `service/NotaFiscalServiceTest.java` | sem retenção: tributo informativo, líquido = crédito do extrato; cancelar não estorna |
| `service/fiscal/NotasEInformeTest.java` | filtros, paginação e o informe pelo extrato |
| `service/fiscal/DocumentoDaParteTest.java` | máscara de CPF/CNPJ e o entregador sem CPF |
| `Motoshift/test/documento/documento_fiscal_test.dart` | marca sempre visível, PDF gerado, caminhos até o documento |
| `Motoshift/test/fiscal/notas_fiscais_filtros_test.dart` | filtro indo para a API, paginação, informe e exportação |
