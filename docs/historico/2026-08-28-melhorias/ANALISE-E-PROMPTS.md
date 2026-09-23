# MotoShift — Análise de melhorias e prompts para o Claude Code

Gerado em 2026-08-28, a partir do estado da branch `main`
(`7e7858d`). Leitura estática do repositório inteiro: 30 classes Java
(~4.900 linhas), 93 arquivos Dart (~18.900 linhas), testes e configuração.
Nada foi alterado no projeto para produzir este documento.

Complementa — não substitui — `AUDITORIA.md` e
`docs/refatoracao-p0/PLANO-REFATORACAO-P0.md`. Onde aqueles olham para
código morto e para os cards SCRUM-17/18/19/20, este olha para
**arquitetura, segurança e produto**.

---

## Sumário executivo

O projeto está muito acima da média de um TCC: Clean-ish Architecture no
Flutter, testes de golden com relógio injetável, teste de acessibilidade que
mede alvo de toque, deploy em Railway com Docker multi-stage, Swagger,
integração com IA. O que falta não é capricho — são **três buracos
estruturais** que um avaliador técnico encontra em cinco minutos:

| # | Buraco | Onde |
|---|--------|------|
| 1 | **Não existe camada de autenticação.** 45 endpoints públicos; só 2 validam o Bearer, e manualmente | `backend/.../controller/*` |
| 2 | **Senha em texto puro** no banco e comparada com `equals` | `AuthService.registrar/login` |
| 3 | **Autorização vem do corpo da requisição.** `{"motoboyId": 7}` — qualquer um age como qualquer um | `TurnoController`, `CarteiraController` |

Depois disso, a maior dívida é de **organização**: um `TurnoService` de 604
linhas, controllers com regra de negócio dentro, um `ApiService` de 459 linhas
no Flutter e três camadas de modelo convivendo (uma delas morta).

Prioridades sugeridas: **P0 = segurança**, **P1 = organização e modelagem**,
**P2 = produto**. Os prompts da parte 3 seguem essa ordem.

---

# Parte 1 — Organização e qualidade

## 1.1 Segurança (P0 — resolver antes da defesa)

### Não há Spring Security no `pom.xml`

Consequência prática, com o backend de produção no ar:

```
GET  /api/carteira/3            → saldo, ganhos e extrato de outro usuário
PUT  /api/turnos/12/finalizar   → finaliza turno alheio, credita carteira
POST /api/carteira/3/saque      → saca o dinheiro de outro motoboy
PUT  /api/usuarios/3            → edita o perfil de outro usuário
```

Nenhuma dessas rotas verifica quem está chamando. `AuthService.validarToken`
existe e funciona, mas só `RelatorioController` e `ScoreController` a chamam —
e cada um repete a mesma linha `authHeader.substring(7)` na mão.

O `AuthGuard` do Flutter protege a **navegação**, não a **API**. Um `curl`
ignora ele.

**Correção:** filtro de autenticação (`OncePerRequestFilter`) + Spring Security
com `SecurityFilterChain`, e o `usuarioId` saindo do token, nunca do body.

### Senha em texto puro

```java
u.setSenha(req.getSenha()); // plain-text apenas em dev
...
.map(u -> u.getSenha().equals(req.getSenha()))
```

O comentário reconhece o problema, o que é honesto, mas o mesmo código roda em
produção (`application-prod.properties` não muda nada disso). `BCryptPasswordEncoder`
é uma dependência e três linhas.

### Sessão em `ConcurrentHashMap`

```java
private final ConcurrentHashMap<String, Long> tokens = new ConcurrentHashMap<>();
```

Três defeitos: some a cada deploy (todo mundo deslogado), nunca expira (token
vazado vale para sempre) e não funciona com mais de uma instância no Railway.
JWT assinado com HS256 resolve os três e some com o mapa.

O mesmo vale para o mapa de tentativas de login do RF01: ele zera a cada
restart, então o bloqueio de 15 minutos é contornável com um deploy. Para o
MVP é aceitável — mas vale uma linha no texto do TCC dizendo que você sabe.

### CORS aberto em dois lugares

`WebConfig` libera `allowedOriginPatterns("*")` para `/api/**`, e além disso
**todo** controller repete `@CrossOrigin(origins = "*")`. Configuração
duplicada é configuração que diverge. Deixe só o `WebConfig`, com a origem do
front lida de variável de ambiente.

### `ddl-auto=update` em produção

O Hibernate é a sua ferramenta de migração hoje. Ele adiciona colunas, mas
nunca remove, nunca renomeia e nunca versiona — e falha silenciosamente em
mudanças de tipo. Flyway com um `V1__baseline.sql` gerado do schema atual
custa uma tarde e resolve para sempre.

### `DataInitializer` sem `@Profile`

447 linhas de seed com oito usuários de senha `senha123` que rodam em qualquer
perfil. Só não polui a produção porque o `if` de "banco vazio" segura. Marque
`@Profile("dev")` e o risco desaparece.

## 1.2 Modelagem de dados (P1)

### `Double` para dinheiro

`valorEstimado`, `saldo`, `valor` da transação — todos `Double`. Ponto
flutuante binário não representa `0,10` exatamente; somando extrato de
carteira, o centavo aparece. `BigDecimal(19,2)` é o tipo correto e é
defensável em banca.

### `String` para status

`status` (`"aberto"`, `"aceito"`, `"finalizado"`, `"cancelado"`,
`"expirado"`) e `pagamentoStatus` (`"pendente"`, `"pago"`) são strings
soltas comparadas com `.equals` em dezenas de lugares. Um typo compila e
falha em runtime. `enum` + `@Enumerated(EnumType.STRING)` custa pouco e
elimina a classe inteira de bug.

### Sem relacionamentos JPA

`lojistId`, `motoboyId`, `turnoId` são `Long` cru, sem `@ManyToOne` e sem
foreign key. Duas consequências:

- **Integridade:** nada impede um turno apontar para um usuário que não existe.
- **Performance:** `temConflitoDeAgenda` faz `findById` dentro de um `for` —
  N+1 explícito. Com `@ManyToOne` + uma query `@Query` isso vira uma ida ao banco.

### Dois caminhos para a mesma regra de pagamento

`TurnoService` mantém, lado a lado, o fluxo por `TurnoInscricao`
(`liquidarInscricao`) e um "fallback legado" no próprio `Turno`
(`tentarEfetivarPagamento`, com `lojistaConfirmouEm`/`motoboyConfirmouEm`
duplicados nas duas entidades). Toda regra nova precisa ser escrita duas vezes,
e o dia em que só uma for atualizada é o dia do bug de dinheiro.

Migre os turnos legados para inscrições (um `UPDATE` de backfill) e apague o
caminho antigo.

## 1.3 Organização do backend (P1)

| Sintoma | Arquivo | Tamanho |
|---|---|---|
| Service que faz tudo: criar, aceitar, finalizar, pagar, creditar carteira, notificar, filtrar por raio | `TurnoService.java` | 604 linhas |
| Regra de negócio dentro do controller | `RelatorioController.java` | 312 linhas |
| Idem | `AvaliacaoController.java` | 250 linhas |
| Idem | `ScoreController.java` | 177 linhas |
| Monta prompt de IA dentro do controller | `SugestaoController.java` | 133 linhas |

Controller deveria ter uma responsabilidade: receber HTTP, delegar, devolver
HTTP. Hoje quatro deles têm regra, montagem de prompt e agregação de dados.

**Sem `@RestControllerAdvice`.** Cada método lança `ResponseStatusException`
com texto solto; o corpo do erro depende de `server.error.include-message=always`
para o Flutter conseguir ler a mensagem. Um handler central devolvendo um DTO
`{codigo, mensagem, campo}` padroniza tudo e tira o acoplamento com essa
propriedade.

**Testes:** dois arquivos (`AuthServiceTest`, `TurnoServiceTest`, ~340 linhas)
para 30 classes. Nenhum `@WebMvcTest` de controller, nenhum `@DataJpaTest` de
repository. O front tem golden e a11y test; o back tem quase nada — é uma
assimetria que chama atenção na defesa.

**Sem CI.** Não existe `.github/`. Nada roda `mvn test`, `flutter analyze` ou
`flutter test` no push. E o backend **não tem `mvnw` nem `.mvn/wrapper`** —
só `mvnw.cmd`. Qualquer CI Linux quebra no primeiro comando.

## 1.4 Organização do Flutter (P1)

### Três camadas de modelo, uma morta

```
lib/models/           → Usuario, Turno, Carteira…  (usado por todas as telas)
lib/domain/entities/  → PedidoEntity, HistoricoItemEntity, UsuarioEntity
lib/data/models/      → PedidoModel, HistoricoItemModel
```

A segunda e a terceira existem para `PedidoProvider` e `HistoricoProvider` —
que estão registrados no `MultiProvider` do `app.dart` e **não são consumidos
por nenhuma tela**. É a Clean Architecture de uma iteração anterior, ainda
instanciada a cada boot.

Decida: ou migra o app inteiro para o padrão `domain/data/presentation`, ou
remove as três pastas e os dois providers. Manter as duas é o pior dos mundos —
e um avaliador vai perguntar qual é a arquitetura do projeto.

### `ApiService` é um God object

459 linhas com auth, usuários, turnos, carteira, transações, dashboard, IA,
agenda, avaliações e notificações. Além disso expõe `rawGet`/`rawPost`/`rawPut`
públicos, que os repositórios usam com path em string — o encapsulamento existe
e tem uma porta ao lado com "entre por aqui" escrito.

Quebre em `AuthApi`, `TurnoApi`, `CarteiraApi`, `AvaliacaoApi`,
`NotificacaoApi`, `IaApi`, sobre um `HttpClient` único que centraliza headers,
timeout e erro.

### Mina terrestre ainda ativa

```dart
Future<List<Transacao>> listarTransacoes(int motoboyId, {int limit = 20}) async {
  final list = await _get('/transacoes?motoboyId=$motoboyId&limit=$limit') …
```

Não existe `TransacaoController` no backend. A chamada é 404 garantido. Hoje
ninguém a usa — a primeira tela que usar quebra. A `AUDITORIA.md` já apontou
isso; continua lá. Ou cria o endpoint, ou apaga o método.

### Telas grandes demais

`agendar_turno` 838 linhas, `meus_turnos` 803, `agenda` 625,
`turno_lojista_conteudo` 561, `detalhe_turno_conteudo` 555. Cada uma mistura
layout, estado local, formatação e chamada de API. Você já provou que sabe
separar — `historico_turnos/` está dividido em `filtros`, `resumo`,
`conteudo_mobile` e `conteudo_desktop`. Aplique o mesmo padrão às cinco maiores.

### Navegação

30+ rotas em `Map<String, WidgetBuilder>` dentro de `app.dart`, com argumentos
passados via `ModalRoute.settings.arguments` sem tipagem. O app roda em **web**
no Railway: hoje um F5 em qualquer tela volta para a splash, e não existe URL
compartilhável. `go_router` resolve deep link, tipagem de argumento e guard de
rota no mesmo movimento — e o `AuthGuard` vira um `redirect`.

### Detalhes menores

- `dio: ^5.7.0` no `pubspec.yaml` e **nunca importado**. Remova.
- `agenda_screen.dart` ainda lê `DateTime.now()` direto, enquanto o resto do
  app já usa `clock.now()` — quebra a garantia dos goldens naquele arquivo.
- `ApiException(0, 'Sem conexao com o servidor')` engole a exceção original;
  sem retry e sem timeout explícito no `http`.
- Sem estado offline: em conexão ruim, cada tela mostra erro genérico.

## 1.5 Higiene do repositório (P2)

- `Motoshift/login/`, `cadastro/`, `agendar_turno/`, `carteira_ganhos/`,
  `dashboard_lojista/`, `dashboard_motoboy/`, `meus_turnos/` — cada uma com
  `code.html` + `screen.png` do Stitch, **dentro do projeto Flutter**. Isso é
  design, não código: mover para `design/stitch/`.
- `Motoshift/MatheusSilverio.docx`, `REQUIREMENTS.md.txt`,
  `metro_velocity/DESIGN.md` soltos no app.
- Raiz com `AUDITORIA.md`, `GUIA_DEFESA.md`, `commitar_melhorias.sh`: mover
  para `docs/` e `scripts/`.
- Branches: 4 locais (`feat/carteira-liquidacao-automatica`,
  `feat/scrum-19-20-…`, `feat/ui-desktop-responsivo`) e 3
  `railway/fix-deploy-*` no origin. Merge ou delete — a `AUDITORIA.md` já
  reclama de "três linhas de código divergentes".
- Não existe `CONTRIBUTING.md` nem `CHANGELOG.md`; o `README` é bom, mas não
  descreve a arquitetura de pastas.

---

# Parte 2 — Funcionalidades novas

Ordenadas por **retorno na banca dividido por esforço**. As três primeiras
usam infraestrutura que já existe no projeto.

## 2.1 Check-in e check-out com geolocalização ★ recomendado

O modelo já tem `latitude`/`longitude` no turno, o app já tem `geolocator` e
`GeoUtils.distanciaKm` já está escrito e testado. Falta usar isso para o que
importa: o motoboy faz check-in ao chegar (validando que está a menos de N
metros do endereço) e check-out ao sair. Ganhos:

- **Comprovação de presença** — hoje "finalizar turno" é um botão que qualquer
  um aperta.
- Horas efetivamente trabalhadas vs. contratadas, que alimenta score e relatório.
- Um RF novo, forte, com regra de negócio de verdade — exatamente o que uma
  banca gosta de ver.

Esforço: dois campos na inscrição, um endpoint, uma tela. Talvez um dia.

## 2.2 Escrow: pagamento com saldo em carteira ★ recomendado

Hoje o dinheiro é fictício: as duas partes clicam "confirmei" e a carteira é
creditada. Ninguém pagou nada. O modelo de escrow resolve a fragilidade
conceitual e some com o fluxo de dupla confirmação manual:

1. Lojista carrega saldo (mock de Pix/cartão basta para o MVP).
2. Ao publicar o turno, o valor é **bloqueado** na carteira dele.
3. Ao finalizar (ou ao check-out), o valor é **liberado** automaticamente.
4. Cancelamento devolve o bloqueio, com regra de multa.

Já existe um esboço em `docs/refatoracao-p0/PROMPTS-CLAUDE-CODE.md` (Prompt 2).
Vale a pena retomar — é o que transforma o MotoShift de "agenda" em "marketplace".

## 2.3 Turnos recorrentes ★ recomendado

O argumento central do produto é *previsibilidade*. Recorrência é a expressão
literal disso: "toda terça e quinta, 18h–22h, 12 semanas". O lojista publica
uma vez; o motoboy aceita a série inteira ou ocorrências individuais.

Modelagem: uma entidade `TurnoRecorrencia` (regra + data-fim) e turnos gerados
por um job — você já tem `@Scheduled` funcionando no `TurnoExpiracaoService`.

## 2.4 Fila de espera e substituição automática

Turno lotado hoje é um beco sem saída. Com fila: o motoboy entra na lista de
espera; se alguém cancela, o primeiro da fila é notificado e tem 15 minutos
para aceitar. Resolve o problema real do cancelamento tardio — hoje só existe
a punição no score, nunca a reposição.

## 2.5 CNH vencida bloqueia aceite

`cnhValidade` já está na entidade `Usuario` e nunca é lida. Três linhas em
`TurnoService.aceitar` e um aviso no app 30 dias antes do vencimento. Regra de
compliance real, custo quase zero.

## 2.6 Chat do turno (ou contato mascarado)

Lojista e motoboy não têm nenhum canal dentro do app. O mínimo viável é expor o
telefone só depois do aceite e só até 2h após o fim; o ideal é um chat simples
por turno. Sem isso, todo mundo migra para o WhatsApp e o app perde o registro
da combinação.

## 2.7 Notificação push de verdade

`NotificacaoService` já grava e o sino já mostra badge — mas o app só descobre
quando o usuário abre a tela. Firebase Cloud Messaging fecha o ciclo: "turno
em 1h", "vaga aberta perto de você", "pagamento liberado".

## 2.8 Score auditável

`score` é um `Double` que muda sem deixar rastro. Uma tabela
`ScoreEvento (usuarioId, tipo, delta, motivo, turnoId, criadoEm)` dá histórico,
permite recalcular, alimenta melhor a análise por IA e deixa o usuário entender
por que caiu — hoje ele só vê o número mudar.

## 2.9 Exportar relatório em PDF/CSV

Motoboy autônomo/MEI precisa declarar renda. Os relatórios de IA já existem;
falta o botão que baixa. Alto valor percebido, baixíssimo esforço.

## 2.10 Painel administrativo

Um perfil `admin` com moderação de usuários, resolução de disputa de pagamento
e visão agregada da plataforma. Além de útil, mostra que você pensou em
operação — e não só nos dois papéis felizes.

## 2.11 Observabilidade e tema escuro

Actuator já está no `pom.xml` mas só expõe `health`. Métricas de negócio
(turnos publicados/aceitos/cancelados por hora) via Micrometer, e um Sentry no
Flutter, custam pouco. O tema escuro conversa com o teste de acessibilidade que
você já escreveu — é a continuação natural daquele trabalho.
