# Documentos fiscais do MotoShift

> **O que este documento responde:** que papel cada lançamento do extrato gera,
> por que uma reserva não vira nota fiscal, que modelo oficial da legislação
> brasileira cada documento segue, o que exatamente é simulado aqui e o que
> faltaria para emitir uma NFS-e de verdade.

> ⚠️ **Tudo o que este documento descreve é SIMULAÇÃO.** Nenhum documento é
> transmitido ao Sistema Nacional NFS-e, a prefeitura ou à Receita Federal,
> não há certificado digital, DPS assinada nem protocolo de autorização. Todo documento — em tela e no PDF — carrega
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
| `pagamento_recebido` (entregador) | **NFS-e** — só consulta, depois que o lojista emitir | as duas partes |
| `pagamento_enviado` (lojista) | **a MESMA NFS-e** — é daqui que ela é emitida | as duas partes |
| `recarga` | Recibo de recarga | o dono |
| `saque`, Pix concluído | Comprovante de Pix | o dono |
| `saque`, Pix recusado | Comprovante de movimentação | o dono |
| `reserva`, `liberacao_reserva` | Comprovante de movimentação | o dono |
| `estorno`, `retencao_iss`, `retencao_irrf` | Comprovante de movimentação | o dono |
| `bonus_enviado` / `bonus` — a **gorjeta** (V17) | Comprovante de movimentação ("Gorjeta enviada" / "Gorjeta recebida", com o turno) | o dono de cada lado |
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

### A gorjeta não é serviço

A gorjeta é um valor além do turno, dado depois de o serviço ter sido prestado
e documentado — pela NFS-e do pagamento do turno. Não há prestação nova, não há
base de cálculo, e uma nota para ela duplicaria o serviço. Por isso gera
**comprovante**, dos dois lados, com o turno de referência e a natureza dita
por extenso ("não é serviço e não gera NFS-e"). No mundo real, gorjeta a
autônomo tem tratamento próprio de rendimento; aqui, como tudo, é simulado.

### O saque pendente não tem comprovante

Um comprovante de Pix emitido antes de o banco responder afirmaria uma
transferência que ainda pode ser recusada. Enquanto a cobrança está `PENDENTE`,
o lançamento não oferece documento; quando ela falha e o estorno entra, o que
existe é um comprovante de movimentação, que é o que de fato aconteceu.

---

### Quem emite: o lojista, por conta do entregador

O documento é sempre o mesmo — **o entregador é o prestador, o lojista é o
tomador** —, mas quem dispara a emissão, e o cancelamento, é **só o lojista**.
O entregador vê a nota, baixa o PDF e imprime; se pedir a emissão ou o
cancelamento, leva **403** com uma mensagem que diz o que acontece
("A nota fiscal é emitida pelo lojista que contratou o turno…"), tanto em
`/api/notas-fiscais` quanto em `/api/carteira/transacoes/{id}/documento`.

> **A pergunta da banca: a NFS-e não é do prestador?** No mundo real, sim: a
> nota de serviço sai do CNPJ de quem presta — aqui, o entregador MEI, pelo
> emissor nacional ou da prefeitura dele. O MotoShift inverte quem **clica**,
> não quem **presta**: a plataforma emite por conta do entregador, a pedido do
> tomador. As razões são práticas. É o lojista quem precisa do documento para
> lançar a despesa e fechar o mês; é ele quem tem cadastro fiscal completo (o
> entregador, hoje, nem tem CPF no cadastro — ver a seção 5); e deixar a
> emissão com quem paga tira do entregador uma tarefa burocrática que não
> muda nada no dinheiro dele. O modelo registra as duas coisas separadas:
> `prestador_id` é quem prestou, `emitida_por_id` é quem pediu. Numa emissão
> real, a plataforma precisaria de uma procuração/autorização do MEI no
> emissor municipal ou nacional para emitir em nome dele — está na lista da
> seção 8.

Para o entregador, o que falta emitir não é pendência: é informação. A tela
de notas mostra esses pagamentos como **"Aguardando emissão"**, sem botão, o
detalhe do lançamento mostra **"Aguardando emissão pelo lojista"** no lugar do
botão, e o app do entregador **nunca** faz o POST da NFS-e — abre a nota pelo
GET. O extrato diz isso no próprio lançamento: o `pagamento_recebido` sem nota
vem com `tipoDocumento = NFSE`, `documentoId = null` e
`documentoDisponivel = false`. Quando a loja emite, o entregador recebe a
notificação `nota_fiscal_emitida`; quando cancela, `nota_fiscal_cancelada`.
Comprovantes (recarga, saque, movimentação) não mudaram: o dono de cada um
continua gerando o seu.

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

**Cancelar a nota não estorna dinheiro.** O cancelamento é do lojista — o
mesmo lado que emite —, marca a nota como cancelada para as duas partes,
avisa o entregador e **não devolve nada**: o serviço foi
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
| POST | `/api/carteira/transacoes/{id}/documento` | Emite — ou devolve, se já existir — o documento do lançamento. NFS-e só pelo lojista (o entregador leva 403) |
| GET | `/api/carteira/transacoes/{id}/documento` | O documento já existente, sem emitir. É por aqui que o entregador abre a nota dele; antes da emissão, 404 "Aguardando emissão pelo lojista" |
| POST | `/api/notas-fiscais` | Emite a nota do turno — só o lojista |
| PUT | `/api/notas-fiscais/{id}/cancelar` | Cancela a nota — só o lojista; não estorna dinheiro |
| GET | `/api/notas-fiscais` | Notas com filtros (`papel`, `status`, `competenciaDe/Ate`, `contraparteId`, `turnoId`) e paginação opcional |
| GET | `/api/notas-fiscais/resumo?ano=` | Informe anual simulado |
| GET | `/api/notas-fiscais/resumo/exportar?ano=` | O mesmo informe em CSV |

O informe também sai em **PDF**, montado no app a partir do mesmo
`/resumo` que a tela já carregou (`RelatorioPdf.informe`). Como imita um
documento fiscal, leva a marca **DOCUMENTO SIMULADO — SEM VALOR FISCAL** na
faixa do topo e em marca d'água, igual à NFS-e — e o rodapé diz que ele não
substitui o informe de rendimentos oficial. O PDF do entregador fala de
"fonte pagadora", o do lojista de "prestador", como a tela.

Para o lojista, "gerar" e "ver" são o mesmo pedido: como a emissão é
idempotente, o POST devolve 201 na primeira vez e 200 depois. Para o
entregador, a NFS-e é só GET: o POST dele é sempre um pedido de emissão, e
continua 403 mesmo depois que a nota existe.

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

## 7. Os modelos oficiais que os documentos seguem

Os documentos imitam **modelos que existem**, definidos em norma. O que se
copia é a estrutura — os blocos, os campos, os rótulos e as regras que
decidem cada valor; o que **não** se copia é o que faria o papel passar por
documento de verdade: não há brasão nem nome de prefeitura no cabeçalho, o QR
Code não aponta para o portal do governo, e a marca de simulação está em
todos.

### NFS-e → DANFSe v2.0 (Nota Técnica SE/CGNFS-e nº 008/2026)

Desde 2026 a NFS-e é padronizada nacionalmente (LC 214/2025), e o documento
que se imprime ou envia em PDF é o **DANFSe** — o Documento Auxiliar da NFS-e.
A NT 008/2026 do Comitê Gestor da NFS-e fixou um modelo único, a versão 2.0,
com os campos de IBS e CBS da reforma tributária. É esse o leiaute da tela e
do PDF, montado no backend (`LeiauteDanfse`) e só desenhado no app:

| Bloco, na ordem da NT | O que a simulação preenche |
|---|---|
| **Identificação** | chave de acesso de 50 dígitos, número da NFS-e, competência, data e hora da emissão, número e série da DPS e o **QR Code** (2,3 cm; a NT pede no mínimo 1,52 cm) |
| **Emitente / prestador** | CNPJ/CPF/NIF, inscrição municipal, telefone, nome, e-mail, endereço, município, CEP, situação no Simples Nacional — o que o cadastro não tem sai com "-", como no documento oficial |
| **Tomador** | os mesmos campos, com o CNPJ mascarado e o endereço comercial da loja |
| **Destinatário** e **intermediário** | "o próprio tomador" e "INTERMEDIÁRIO DO SERVIÇO NÃO IDENTIFICADO NA NFS-e" |
| **Serviço prestado** | código de tributação nacional **26.01.01** (item 26.01 da LC 116/2003: coleta, remessa ou entrega de objetos, bens ou valores — onde a entrega por motoboy se enquadra), NBS **1.0702.00.00**, local e país da prestação e a descrição do turno |
| **Tributação municipal (ISSQN)** | operação tributável, município de incidência, base de cálculo, alíquota, **retido pelo tomador** ou **não retido**, ISSQN apurado |
| **Tributação federal** | IRRF retido — ou "-" quando não houve retenção |
| **Tributação IBS/CBS** | em **2026, o ano de teste**: CBS 0,9% (LC 214/2025, art. 346) e IBS estadual 0,1% (art. 343), sobre a base sem o ISSQN (art. 12, §2º), com CST 000 e classificação 000001. Antes de 2026, "não se aplica"; depois, a simulação diz que ainda não tem as alíquotas da transição, em vez de inventá-las |
| **Valor total** | serviço, descontos, ISSQN retido, retenções federais, **valor líquido** e, com IBS/CBS, o total deles e o "Valor Líquido da NFS-e + IBS/CBS" — sombreado em cinza, como a NT manda |
| **Informações complementares** | os tributos aproximados da Lei 12.741/2012 (federais, estaduais, municipais), o código de verificação e a operação do extrato |

O **valor líquido continua sendo o do extrato** em todos os casos. Em 2026
IBS e CBS são destacados mas dispensados de recolhimento para quem cumpre as
obrigações acessórias (LC 214/2025, art. 348, §1º), e o quadro de totais diz
isso: o prestador recebe o líquido, não o líquido + IBS/CBS.

**A chave de acesso** (`ChaveDeAcessoNfse`) segue a composição oficial,
posição por posição: código IBGE do município (7) + ambiente gerador (1) +
tipo de inscrição (1) + CPF/CNPJ do emitente (14) + número da NFS-e (13) +
ano e mês da emissão (4) + código numérico (9) + DV em módulo 11 (1). O DV é o
mesmo cálculo da chave da NF-e, e o teste confere contra o exemplo do manual
dela. O que é simulado: a plataforma faz o papel do Sistema Nacional
(ambiente gerador 2), o código numérico sai de um hash da nota (e não do
sorteio do Sistema Nacional) e o CPF do entregador — que o cadastro não tem —
vai com zeros. O município vem de uma tabela curta (`MunicipioIbge`: as
capitais e a região de Curitiba); cidade fora dela sai com `0000000` e o
documento diz por quê. A chave é **gravada na emissão** (V20), porque leva o
município do prestador; notas anteriores à V20 recebem, na leitura, a chave
derivada pela mesma regra.

**O QR Code não leva ao portal oficial.** No DANFSe real ele abre a consulta
pública da nota no Portal Nacional da NFS-e. Com uma chave simulada o portal
responderia "não encontrada" — e um link para o governo num documento que não
é do governo é exatamente o que a marca de simulação existe para impedir.
Aqui o QR Code carrega a chave e a frase "DOCUMENTO SIMULADO", e o texto ao
lado explica o que ele faria na nota real.

**Regime tributário.** O prestador aparece como **não optante** do Simples
Nacional. É a única escolha coerente com as alíquotas de exemplo da simulação
(ISS 5%, IRRF 1,5%): um entregador MEI pagaria o ISS dentro do DAS, em valor
fixo, não teria IRRF retido e, em 2026, ficaria fora do IBS/CBS (LC 214/2025,
art. 348). Simular o MEI de verdade é trocar essa regra — está na tabela do
que falta, abaixo.

### Recibo de recarga → quitação do Código Civil, art. 320

O art. 320 diz o que uma quitação designa: o valor e a espécie da dívida
quitada, o nome de quem pagou, o tempo e o lugar do pagamento, com a
assinatura do credor. O recibo traz isso num texto corrido ("Recebemos de …
a importância de R$ 300,00 (trezentos reais), referente à recarga de saldo …,
paga via Pix em … Curitiba - PR, 15 de agosto de 2026."), com o **valor por
extenso** (`util/Reais.java`) — o que impede alguém de transformar "10,00" em
"100,00" com uma caneta. A assinatura do credor, que um recibo em papel teria,
aqui é o código de autenticação, e o recibo diz isso.

### Comprovante de Pix → Regulamento Pix (Resolução BCB nº 1/2020)

O regulamento do Pix, nos *Requisitos Mínimos para a Experiência do
Usuário*, define o que o comprovante mostra — e proíbe o que não é da
transação (propaganda, links). O comprovante traz pagador, instituição do
pagador, recebedor, CPF/CNPJ do recebedor, chave Pix mascarada, instituição do
recebedor, data e hora e o **identificador fim a fim** (EndToEndId) no formato
do Banco Central: "E" + ISPB (8) + AAAAMMDDHHMM (12) + 11 alfanuméricos = 32
posições. No lugar do ISPB, que identificaria uma instituição real, vai a
palavra **SIMULADO**, que também tem 8 letras.

### Comprovante de movimentação

Reserva, liberação, estorno, retenções e gorjeta não têm modelo legal: são
movimentos internos da carteira. Continuam no formato próprio da plataforma.

### Fontes

- NFS-e nacional e Nota Técnica SE/CGNFS-e nº 008/2026 (DANFSe v2.0):
  [Portal da NFS-e](https://www.gov.br/nfse)
- LC 116/2003 (lista de serviços, item 26.01):
  [planalto.gov.br](https://www.planalto.gov.br/ccivil_03/leis/lcp/lcp116.htm)
- LC 214/2025 (IBS e CBS; arts. 12, 343, 346 e 348):
  [planalto.gov.br](https://www.planalto.gov.br/ccivil_03/leis/lcp/lcp214.htm)
- Lei 12.741/2012 (tributos aproximados):
  [planalto.gov.br](https://www.planalto.gov.br/ccivil_03/_ato2011-2014/2012/lei/l12741.htm)
- Código Civil, art. 320 (quitação):
  [planalto.gov.br](https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm)
- Regulamento Pix — Requisitos Mínimos para a Experiência do Usuário:
  [bcb.gov.br](https://www.bcb.gov.br/content/estabilidadefinanceira/pix/Regulamento_Pix/IV_RequisitosMinimosparaExperienciadoUsuario.pdf)
- NBS — Nomenclatura Brasileira de Serviços, 1.0702.00.00:
  [nbs.economia.gov.br](http://nbs.economia.gov.br/pt/concepts/servicos-postais-servicos-de-coleta-remessa-ou-entrega-de-documentos-ou-encomendas-servicos-de-remessas-expressas.html)

Um modelo oficial que **ainda não** está aqui: o informe anual poderia seguir
o *Comprovante de Rendimentos Pagos e de Imposto sobre a Renda Retido na
Fonte* da IN RFB nº 2.060/2021 (um por fonte pagadora, com os quadros da
Receita). Hoje ele é o relatório próprio da seção 6.

---

## 8. O que existe aqui e o que faltaria numa emissão real

### Existe

- Modelo de dados com o que uma NFS-e precisa: partes, competência,
  discriminação do serviço, base de cálculo, alíquotas, tributos, valor
  líquido, número, série, código de verificação e chave de acesso no formato
  nacional.
- O leiaute oficial do DANFSe v2.0, na tela e no PDF (uma página A4, com QR
  Code) — seção 7.
- Numeração sequencial por prestador e série configurável.
- Emissão idempotente, cancelamento com motivo, autorização por parte.
- PDF e impressão no app (pacotes `pdf` e `printing`), com a marca de
  simulação como marca d'água.

### Não existe (e é o que uma integração real exigiria)

| O que falta | Por quê |
|---|---|
| **Certificado digital A1/A3** do prestador | a DPS é assinada em XML (XMLDSig); sem certificado não há assinatura |
| **DPS** (Declaração de Prestação de Serviço) em XML, enviada ao **Sistema Nacional NFS-e** | é o que o emitente envia; o número, a chave de acesso e a nota autorizada voltam de lá. Aqui a DPS é só o número e a série que o DANFSe mostra |
| **Cadastro real do prestador** (CPF/CNPJ, inscrição municipal, CNAE, endereço com CEP) | hoje o entregador não tem sequer CPF no cadastro — a chave de acesso leva zeros no lugar |
| **Tabela completa de municípios do IBGE** | a simulação conhece as capitais e a região de Curitiba |
| **Autorização do prestador para a plataforma emitir** em nome dele | aqui o lojista pede e a plataforma emite pelo entregador; no emissor real isso exige procuração ou credenciamento do MEI |
| **Alíquota do município** e regime tributário (Simples, MEI) | as alíquotas aqui são de exemplo, fixas em configuração, e o prestador é sempre "não optante" |
| **Alíquotas de IBS/CBS da transição** (2027 em diante) | a simulação só tem as do ano de teste, fixadas na LC 214/2025 |
| **Retenções conforme a lei** | a retenção implementada é uma simulação da mecânica, não a regra fiscal aplicável |
| Consulta de situação, carta de correção, substituição | o ciclo de vida real de uma nota é maior que emitir e cancelar |

### Por onde a troca entraria

O ponto de extensão já está isolado, na mesma ideia do `GatewayPagamento` do
ledger:

```
NotaFiscalService  →  EmissorDeNotas (interface)  →  EmissorSimulado (hoje)
                                                  →  EmissorNacional (real, amanhã)
```

`EmissorDeNotas.autorizar(rascunho, prestador)` recebe a nota com partes,
valores e competência preenchidos e devolve `(numero, serie,
codigoVerificacao, chaveAcesso)`. Uma implementação real montaria a DPS a
partir do rascunho, assinaria com o certificado, enviaria ao Sistema Nacional
NFS-e e devolveria o número e a chave que ele atribuiu. O modelo já tem as
colunas que o provedor preencheria, e o resto do backend não sabe de que lado
está a simulação.

O que **também** mudaria numa emissão real, e não é detalhe: a emissão
deixaria de ser síncrona. O Sistema Nacional (ou a prefeitura) pode responder
depois, e a nota passaria a ter um estado "enviada, aguardando autorização"
entre o pedido e o número. O modelo de hoje não tem esse estado porque a
simulação autoriza na hora.

---

## 9. Onde olhar no código

| Assunto | Arquivo |
|---|---|
| Tabela lançamento → documento | `service/fiscal/TipoDocumento.java` |
| Emissão, autorização e 403 | `service/fiscal/DocumentoFiscalService.java` |
| Comprovantes e HMAC | `service/fiscal/ComprovanteService.java` |
| Fronteira com o Sistema Nacional NFS-e | `service/fiscal/EmissorDeNotas.java`, `EmissorSimulado.java` |
| Leiaute do DANFSe v2.0 (quadros oficiais) | `service/fiscal/LeiauteDanfse.java`, `dto/DanfseResponse.java` |
| Chave de acesso e municípios IBGE | `service/fiscal/ChaveDeAcessoNfse.java`, `MunicipioIbge.java` |
| Valor em reais e por extenso | `util/Reais.java` |
| Nota a partir do pagamento | `service/NotaFiscalService.java` |
| Alíquotas e retenção | `service/fiscal/CalculoTributario.java` |
| Retenção no ledger | `service/PagamentoTurnoService.java`, `service/ledger/Movimento.java` |
| Informe anual | `service/fiscal/InformeRendimentosService.java` |
| Máscara de CPF/CNPJ | `service/fiscal/DocumentoDaParte.java` |
| Migrações | `db/migration/V14__fiscal_por_lancamento.sql`, `V20__chave_de_acesso_da_nfse.sql` |
| App: tela do documento | `Motoshift/lib/views/documento_fiscal/`, `lib/widgets/documento/` (o DANFSe em `nfse_view.dart`, o QR Code em `qr_code.dart`) |
| App: modelo do DANFSe | `Motoshift/lib/models/danfse.dart` |
| App: PDF e impressão | `Motoshift/lib/services/documento_pdf.dart` |
| App: identidade visual comum aos PDFs | `Motoshift/lib/services/identidade_pdf.dart` |
| App: PDF do informe anual (e do extrato e do relatório) | `Motoshift/lib/services/relatorio_pdf.dart` |

### Testes que sustentam este documento

| Arquivo | O que prende |
|---|---|
| `service/fiscal/TipoDocumentoTest.java` | a tabela da seção 2, incluindo reserva sem nota |
| `service/fiscal/DocumentoFiscalServiceTest.java` | idempotência, 403 para terceiro e para o entregador que pede a NFS-e, "aguardando emissão" no extrato, saque pendente sem documento; recibo no modelo do art. 320 e comprovante Pix com os campos do Regulamento Pix |
| `service/fiscal/LeiauteDanfseTest.java` | os blocos do DANFSe na ordem da NT 008, os rótulos oficiais, ISSQN retido ou não, IBS/CBS só em 2026, líquido = extrato |
| `service/fiscal/ChaveDeAcessoNfseTest.java` | a chave de 50 dígitos posição por posição, o DV contra o exemplo do manual da NF-e, o entregador sem CPF |
| `util/ReaisTest.java` | reais formatados e por extenso, com as concordâncias ("mil e cem", "um milhão de reais") |
| `service/fiscal/RetencaoNaFonteTest.java` | com retenção: o bruto no extrato, as duas saídas na mesma operação, a nota batendo com o saldo |
| `service/NotaFiscalServiceTest.java` | sem retenção: tributo informativo, líquido = crédito do extrato; cancelar não estorna; só o lojista emite e cancela (403 para o entregador) e o entregador é avisado |
| `controller/NotaFiscalControllerTest.java` | pelo HTTP: 403 para o entregador em emitir, cancelar e no POST do documento; o GET abre a nota dele |
| `service/fiscal/NotasEInformeTest.java` | filtros, paginação e o informe pelo extrato |
| `service/fiscal/DocumentoDaParteTest.java` | máscara de CPF/CNPJ e o entregador sem CPF |
| `Motoshift/test/documento/documento_fiscal_test.dart` | marca sempre visível; o DANFSe na tela e no PDF (chave, QR Code, quadros na ordem, IBS/CBS de 2026, uma página A4); o recibo do art. 320; caminhos até o documento. As fixtures em `test/fixtures/danfse_*.json` foram geradas pelo próprio `LeiauteDanfse` |
| `Motoshift/test/fiscal/notas_fiscais_filtros_test.dart` | filtro indo para a API, paginação, informe e exportação |
| `Motoshift/test/exportacao/exportar_pdf_test.dart` | os três PDFs gerados, com os totais da tela lidos de volta do arquivo, as colunas por papel e a marca no informe |
| `Motoshift/test/fiscal/quem_emite_test.dart` | entregador sem "Emitir" nem "Cancelar", "aguardando emissão" sem botão, nota aberta por GET |
