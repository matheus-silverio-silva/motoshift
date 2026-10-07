# 🎓 Guia de Defesa — MotoShift

Resumo técnico do código para apoiar respostas a perguntas da banca.
Cada item aponta **onde no código** a funcionalidade vive.

---

## 1. Resumo em uma frase

MotoShift é um MVP de logística urbana baseado em **agendamento de turnos**
(em vez do despacho imediato dos apps tradicionais), conectando **lojistas**
que publicam turnos e **motoboys** que os reservam — com app em **Flutter**,
API em **Java/Spring Boot** e banco **PostgreSQL** (H2 em desenvolvimento).

> Frase-chave para a banca: *"O diferencial não é tecnológico, é de modelo de
> negócio: previsibilidade por turnos agendados, reduzindo ociosidade do motoboy
> e garantindo cobertura para o lojista."*

---

## 2. Arquitetura geral

```
┌─────────────────┐      HTTP/JSON (REST)      ┌──────────────────────┐
│  App Flutter    │ ─────────────────────────► │  API Spring Boot     │
│  (Android/iOS/  │ ◄───────────────────────── │  (camadas)           │
│   Web)          │                            │                      │
└─────────────────┘                            │  Controller → Service│
        │                                      │     → Repository     │
   Provider (estado)                           └──────────┬───────────┘
                                                          │ JPA/Hibernate
                                                  ┌─────────────────────┐
                                                  │ PostgreSQL (prod),  │
                                                  │ schema por Flyway   │
                                                  │ H2 (dev)            │
                                                  └─────────────────────┘
                                          IA: Service → Claude (Anthropic API)
```

---

## 3. Back-end (Java 17 + Spring Boot 3.3.6)

Pacote raiz: `com.motoshift`. Arquitetura em camadas clássica:

| Camada | Pasta | Responsabilidade |
|--------|-------|------------------|
| **Controller** | `controller/` | Expõe endpoints REST, recebe/retorna DTOs |
| **Service** | `service/` | Regras de negócio (validações, transações) |
| **Repository** | `repository/` | Acesso a dados (Spring Data JPA) |
| **Entity** | `entity/` | Tabelas do banco (`Usuario`, `Turno`, `TurnoInscricao`, `Carteira`, `Transacao`, `Avaliacao`, `NotaFiscal`, `LancamentoGerencial`, entre outras) |
| **DTO** | `dto/` | Objetos de transferência (separa API do modelo interno) |
| **Config** | `config/` | `MassaDemonstracao` (massa de teste: `popular()`, `resetar()` e `apagarTudoERecriar()`), `DataInitializer` (gatilho em dev) e `ResetDaMassaNoBoot` (os dois resets, com trava, em qualquer ambiente) |

**Fluxo de uma requisição** (ex: aceitar turno):
`PUT /api/turnos/{id}/aceitar` → `TurnoController` → `TurnoService.aceitar()`
(valida conflito de horário) → `TurnoRepository.save()` → retorna `TurnoResponse`.

Serviços principais: `AuthService`, `TurnoService`, `PagamentoTurnoService`,
`LedgerService` (o único que altera saldo), `DreService` (lucro e prejuízo) e
`AnthropicService` (IA).

---

## 4. Front-end (Flutter)

- **Gerência de estado:** `Provider` (`ChangeNotifier`) — providers em
  `presentation/providers/` (ex: `TurnoProvider`, `PedidoProvider`).
- **Telas:** `views/` (uma pasta por tela: login, dashboards, agenda, carteira…).
- **Acesso à API:** `services/api_service.dart` centraliza as chamadas HTTP;
  `services/auth_service.dart` cuida da sessão.
- **Tema:** `theme/app_theme.dart` (Material Design 3). As fontes (Bricolage
  Grotesque e Plus Jakarta Sans, SIL OFL) vão **embarcadas** em `assets/fonts`:
  o `google_fonts` as usa dos assets e a busca em rede está desligada
  (`GoogleFonts.config.allowRuntimeFetching = false` no `main.dart`). Antes o
  app baixava cada peso na primeira vez em que ele aparecia — sem internet, a
  tela abria na fonte do sistema.
- **Mapa:** `flutter_map` (OpenStreetMap) para região de entrega.

> **Se perguntarem por Clean Architecture:** existiam `domain/` e `data/` de uma
> tentativa anterior, com dois providers registrados no boot e nenhuma tela
> consumindo. Foram removidas. Resposta honesta: *"Conviver com duas
> arquiteturas é pior do que ter uma; o app segue `views` + `providers` +
> `services`, que é o que as telas realmente usam."*

**Configuração da URL da API:** injetada em build via
`--dart-define=API_URL=...` e lida em `services/api/api_client.dart`
(`String.fromEnvironment('API_URL')`). Em dev usa `10.0.2.2:8080` (emulador
Android) ou `localhost:8080`.

**Servidor acordando:** ao abrir, o app pergunta `GET /api/status`
(`ServidorService`). Se a resposta não vem em 3 s, a tela avisa "Acordando o
servidor…", desliga o botão Entrar e pergunta de novo a cada 5 s, por até 4
min — o plano gratuito da hospedagem desliga o servidor depois de 15 min
parado. Quem tem sessão salva espera na abertura, sem perder a sessão.

---

## 5. Requisitos Funcionais — onde estão no código

| RF | Regra | Local | Testado? |
|----|-------|-------|----------|
| RF01 | Login + bloqueio após 5 falhas por 15 min | `AuthService.login()` | ✅ |
| RF02 | Dashboard lojista/motoboy | `DashboardController` + `views/dashboard_*` | — |
| RF03 | Cadastro: CNPJ (14 díg.) / CNH (11 díg.) | `AuthService.registrar()` | parcial |
| RF04 | Publicar turno, antecedência mínima de 2h | `TurnoService.criar()` | ✅ |
| RF05 | Reservar turno, sem conflito de horário e sem dois na mesma vaga | `TurnoService.aceitar()` + `TurnoRepository.buscarTravandoAsVagas()` | ✅ |
| RF06 | Finalizar transfere o valor reservado para o entregador **que fez check-in**, na mesma transação; só depois do início do turno | `TurnoService.finalizar()` + `PagamentoTurnoService.fecharInscricoes()` / `liquidar()` | ✅ |
| RF07 | Cancelar é do lojista e não penaliza ninguém; desistir da vaga é do entregador e, a < 1h do início, tira 0.5 do score dele | `TurnoService.cancelar()` / `desistir()` + `Reputacao` | ✅ |
| RF09 | Notificações dentro do app, com o sino que se atualiza | `NotificacaoService` + `NotificacaoProvider` (app) | ✅ |
| RF12 | Carteira e ledger: recarga, reserva, liquidação, saque e as três invariantes | `LedgerService` + `ConsistenciaService` | ✅ |
| RF13 | Resultado do período (lucro ou prejuízo) numa DRE em regime de caixa | `DreService` + `LancamentoGerencialService` | ✅ |
| RF15 | Check-in e check-out, com janela de horário e proximidade | `CheckinService` | ✅ |
| RF16 | Turno que se resolve sozinho: vencimento, lembrete e finalização automática | `TurnoExpiracaoService` + `TurnoLembreteService` | ✅ |
| RF19 | Trocar a senha e recuperá-la por código | `SenhaService` | ✅ |

A lista completa — RF01 a RF21 e RNF01 a RNF08, com os cards do Jira, as
classes e os testes de cada um — está em `docs/REQUIREMENTS.md`. A numeração
segue o que o código cita: o **RF09 são as notificações**; o relatório por IA é
o **RF14** e a sugestão de turnos por IA, o **RF08**.

**Regras de negócio mais "perguntáveis":**
- *Antecedência de 2h:* `LocalDateTime.now().plusHours(2)` — turno antes disso é rejeitado (HTTP 400).
- *Conflito de horário:* `TurnoRepository.existeConflitoDeAgenda()` — olha as
  inscrições ativas do entregador (inclusive em turno multi-vaga que segue
  "aberto"); se houver sobreposição, retorna HTTP 409.
- *A última vaga não é de dois:* o aceite conta as inscrições e grava em seguida — e contar e gravar não é
  atômico. Dois entregadores tocando "Aceitar" na última vaga liam os dois "0 de 1" e entravam os dois (a
  unicidade da inscrição é por turno + entregador, não barrava). Agora `aceitar` e `desistir` carregam o
  turno com `@Lock(PESSIMISTIC_WRITE)`: o segundo espera o primeiro commitar e já lê o turno lotado → 409.
  Trava pessimista, e não `@Version`, porque disputar a última vaga é o caso esperado e a resposta certa é
  "vagas preenchidas", não um erro para repetir. `AceiteConcorrentePostgresTest`: 8 threads, 1 vaga,
  exatamente 1 inscrição e 7 respostas 409 — em PostgreSQL, e o teste falha (2 entram) sem a trava.
- *Crédito na carteira:* acontece na **finalização do turno**, na mesma transação que o encerra —
  o valor sai do saldo **bloqueado** do lojista (reservado quando ele publicou) e entra no
  **disponível** do entregador. Não há confirmação a dar: o compromisso foi assumido na publicação.
  A dupla confirmação manual que existia aqui foi removida (V13) — ver `docs/financeiro/FLUXO-FINANCEIRO.md`.
- *Finalizar só paga quem trabalhou:* finalizar exige turno começado e pelo menos um check-in (409 fora
  disso). Só a inscrição com check-in recebe; a aceita sem check-in vira `faltou` (V21), sem pagamento e
  sem penalidade de score, e a parte dela volta ao lojista como sobra. Antes, aceitar um turno de amanhã
  e tocar "Finalizar" pagava na hora.
- *Cancelar × desistir:* eram um botão só. A loja cancelava em cima da hora e o entregador perdia score; um
  entregador saía de um turno de três vagas e o turno caía para os outros dois. Agora `cancelar` é só do
  lojista dono (turno inteiro, reserva de volta, ninguém penalizado) e `desistir` é só do entregador inscrito
  (a vaga dele reabre, o turno segue, a loja é avisada). Quem desistiu não aceita o mesmo turno de novo.
- *Penalidade de score:* desistir da vaga com menos de 1h subtrai 0.5 de quem desistiu (mínimo 0.0).
  A regra (valor inicial e penalidade) mora em `Reputacao`, num lugar só.

---

## 6. Inteligência Artificial (Claude / Anthropic)

- **RF08** (sugestão de turnos) e **RF14** (relatórios com análise).
- `AnthropicService` chama a API da Anthropic (modelo `claude-sonnet-4`, trocável
  pela variável `ANTHROPIC_MODEL`, sem recompilar).
- Usado em: **sugestão de turnos**, **relatórios** (financeiro/operacional) e
  **análise de score** — endpoints `/api/sugestoes`, `/api/relatorio`, `/api/score`.
- A chave (`ANTHROPIC_API_KEY`) vem de variável de ambiente — **nunca** fica no código.
- Como cada sugestão é uma chamada paga, `/api/sugestoes` aceita **10 por hora por
  usuário**; acima disso, 429 com `Retry-After` (`LimiteDeRequisicoesFilter`).

> Se perguntarem "a IA é essencial?": *"Não para o fluxo central de turnos;
> é uma camada de valor agregado (recomendação e relatórios em linguagem natural)."*

---

## 7. Banco de dados

- **Dev:** H2 em memória (console em `/h2-console`), recriado a cada boot —
  zero configuração. Flyway desligado: as migrações são SQL PostgreSQL.
- **Prod:** PostgreSQL no Neon (perfil `prod`, `application-prod.properties`).
- **O schema é das migrações, não do Hibernate.** `ddl-auto=validate` em
  produção: o Hibernate só confere se as entidades batem com o que o Flyway
  criou. São 25 migrações versionadas em `db/migration` (V1 a V25), cada uma
  com o motivo escrito no cabeçalho.
- **Integridade no banco.** São 25 `FOREIGN KEY` — 18 delas desde a V11 —,
  todas `ON DELETE RESTRICT`, menos a do código de recuperação de senha (V24),
  que apaga em cascata. As entidades continuam referenciando por `Long`, sem
  `@ManyToOne` — decisões separadas, explicadas no DER.
- **Massa de demonstração:** `MassaDemonstracao` — cerca de cinco meses de
  história (recargas, turnos pagos toda semana, saques, avaliações, notas
  emitidas pelo lojista) gravados pelos mesmos serviços do app, e não por
  INSERT. Em dev nasce com o banco vazio; em produção é recriada por um de dois
  resets com trava: `MOTOSHIFT_SEED_RESET=confirmo` (só a massa) ou
  `MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo` (todos os dados de negócio, com
  DELETE na ordem das FKs; o `flyway_schema_history` fica). Datas sempre
  calculadas a partir do momento em que roda. O passo a passo está no README.

---

## 8. Deploy

- **Três peças:** banco no **Neon** (PostgreSQL), back-end no **Render**
  (`backend/Dockerfile`, plano gratuito) e front-end web no **Firebase
  Hosting** (`flutter build web` + `firebase deploy`, com fallback de SPA no
  `firebase.json`).
- **Mesmo commit, mesmo app:** Flutter **3.41.5** no build, no CI e nos
  goldens, com as dependências saindo do `pubspec.lock` versionado. O
  `Motoshift/Dockerfile` (nginx) continua no repositório como alternativa por
  container.
- **Cache do front:** o `firebase.json` manda `Cache-Control: no-cache` para o
  `index.html` e os arquivos que apontam a versão atual (`flutter_bootstrap.js`,
  `flutter_service_worker.js`, `version.json`, `manifest.json`). Sem isso o
  navegador podia servir o app antigo por até 1 h depois de um deploy.
- **Fuso:** o container roda em UTC; o `main` põe a JVM em
  `America/Sao_Paulo` antes de o Spring subir (variável `MOTOSHIFT_FUSO`), e o
  Dockerfile define `TZ` e `-Duser.timezone`. Ver a pergunta do fuso, abaixo.
- **Servidor que dorme:** o plano gratuito desliga o serviço depois de 15 min
  sem requisição. `GET /api/status` (público, sem banco, fora do limite) é o
  que um monitor chama a cada 10 min para ele não dormir, e o que o app chama
  ao abrir para avisar "Acordando o servidor…" em vez de falhar.
- **CI** (GitHub Actions): `mvn test`, `flutter analyze` e `flutter test` em todo
  pull request e em todo push na `main`; um commit novo cancela a execução
  anterior da mesma branch.
- Back-end: perfil `prod` + PostgreSQL; porta via `$PORT`; healthcheck em
  `/actuator/health`.
- **Variáveis obrigatórias:** `JWT_SECRET` e `MOTOSHIFT_CORS_ORIGINS`. Sem
  elas o boot falha de propósito — melhor o deploy não subir do que subir
  assinando token com chave de exemplo ou liberando qualquer origem.
- **O que produção desliga:** o Swagger (`springdoc.*.enabled=false`, e as
  rotas dele saem das públicas: sem token, 401), a conferência do ledger
  (`@Profile("!prod")`) e a massa de demonstração no boot.
- **Limite de requisições:** cadastro e "esqueci minha senha" aceitam 20 a
  cada 10 minutos por IP. Atrás do proxy da hospedagem o endereço da conexão é
  o do proxy, igual para todos; o IP de quem chamou vem do `X-Forwarded-For`.
  No Render o proxy acrescenta também o próprio IP no fim da lista, então vale
  a **penúltima** entrada (`MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS=1`): lendo a
  última, o limite contava todos os usuários juntos. Em memória, por instância.

---

## 9. Testes

- **Back-end:** 554 testes (JUnit 5, Mockito, `@SpringBootTest`, `@DataJpaTest`),
  cobrindo as regras dos turnos (RF04–RF07), o ledger e as invariantes, a DRE,
  a senha, os limites de requisição, autorização de ponta a ponta (sem token → 401,
  token de outra pessoa → 403, dono → 200), liquidação do pagamento e
  idempotência.
- **Migrações e schema em PostgreSQL de verdade:** um servidor embarcado sobe
  no próprio teste (sem Docker) e roda Flyway + `ddl-auto=validate` — inclusive
  os casos difíceis, como migrar um banco que já tem linha órfã. Antes disso, a
  primeira execução real das migrações era o deploy.
- **Front-end:** 501 testes — unidade, widget, acessibilidade (alvo de toque,
  rótulo de tudo o que é clicável e contraste de texto pelo WCAG AA) e
  *golden tests* (comparação visual das telas).
- *Observação:* os goldens são desenhados com as **fontes do próprio app**
  (os arquivos de `assets/fonts`), e não mais com a fonte do sistema de quem
  roda o teste — eram gravados em Segoe UI, e por isso não mostravam a cara do
  app. A troca revelou um estouro de layout de verdade na linha do extrato
  (16 px além da tela no celular), que a fonte do sistema escondia; desde
  então "RenderFlex overflowed" deixou de ser silenciado na suíte. O CI segue
  em `windows-latest` com o Flutter fixo em 3.41.5, que é onde os goldens são
  gravados: a rasterização muda entre sistemas e entre versões.

---

## 10. Perguntas prováveis da banca + respostas curtas

**P: Por que Flutter?**
R: Um único código-base para Android, iOS e Web — reduz custo/tempo de um MVP.

**P: Por que turnos em vez de despacho imediato?**
R: É a tese do trabalho — o despacho imediato gera ociosidade não-remunerada ao
motoboy e indisponibilidade ao lojista em picos. O turno agendado dá previsibilidade aos dois lados.

**P: Como garante que dois motoboys não peguem o mesmo turno?**
R: O turno tem um número de vagas. Ao aceitar, o serviço confere se o turno
está "aberto", se ainda há vaga, se aquele entregador já não está inscrito e se
o horário não conflita com outro turno dele; qualquer uma delas retorna HTTP
409. O turno fecha (ACEITO) quando a última vaga é preenchida. E dois toques
simultâneos na última vaga não entram os dois: o aceite trava a linha do turno
(`SELECT ... FOR UPDATE`), o segundo espera o primeiro e já lê o turno lotado.

**P: A senha é segura?**
R: BCrypt, sempre — no cadastro, na massa de demonstração e no login, que não
aceita outro formato. As contas antigas de produção, gravadas em texto puro
antes disso, foram convertidas pela migração V9. O token é JWT assinado
(HS256), com o segredo vindo de variável de ambiente.

**P: E o fuso horário?**
R: O sistema tem um fuso só, o de Curitiba. O app manda a data do turno como
hora local, o banco guarda `timestamp` sem fuso e o código usa
`LocalDateTime` — nada é convertido no caminho, então o que precisa estar certo
é o "agora" do servidor. O container da hospedagem roda em UTC, 3 horas à
frente: a regra das 2 h de antecedência virava 5 h, o turno expirava 3 h antes
e, na DRE, o que acontecia depois das 21h caía no dia seguinte. A correção é o
servidor nascer no fuso de quem usa (`MotoshiftApplication.main`, variável
`MOTOSHIFT_FUSO`, padrão `America/Sao_Paulo`), e a suíte de testes roda nesse
mesmo fuso, inclusive no CI. Um fuso só porque loja e entregador estão na
mesma cidade — o check-in exige 500 m do ponto — e o Brasil não tem horário de
verão desde 2019. Para atender outro estado **no lugar** de Curitiba, basta
trocar a variável; para atender **dois fusos ao mesmo tempo**, as datas
passariam a ser instantes (`timestamptz`), o app mandaria o deslocamento, cada
loja teria o seu fuso e os cortes de dia e de mês da DRE seriam calculados no
fuso de quem consulta.

**P: O servidor demora no primeiro acesso. Por quê?**
R: É o plano gratuito da hospedagem: sem requisição por 15 minutos, o serviço
é desligado, e a primeira chamada espera o boot — cerca de 3 minutos. Tratamos
dos dois lados. Um monitor chama `GET /api/status` a cada 10 minutos, o que
mantém o servidor de pé. E o app, ao abrir, pergunta o mesmo status: se a
resposta demora, ele avisa "Acordando o servidor…", desliga o botão Entrar e
insiste a cada 5 segundos por até 4 minutos, em vez de deixar o primeiro login
falhar por tempo esgotado. A rota não consulta o banco e não tem limite de
requisições.

**P: E o bloqueio de login do RF01?**
R: Cinco erros bloqueiam a conta por 15 minutos, e o contador fica em duas
colunas de `usuarios` — não em memória. Assim o bloqueio sobrevive a um
redeploy, vale igual em todas as instâncias e só existe para conta que existe.
O custo conhecido é que quem sabe seu e-mail pode te deixar 15 minutos fora;
mitigar isso pede captcha ou segundo fator, que estão fora do escopo.

**P: "Claudia@Teste.com" e "claudia@teste.com" são a mesma conta?**
R: São. E-mail não diferencia maiúsculas, mas a comparação do banco é exata:
dava para criar as duas contas, e quem se cadastrou em minúsculas não entrava
quando o teclado do celular punha a primeira letra em maiúscula. O e-mail agora
é normalizado (sem espaço nas pontas, em minúsculas) em três lugares, do mais
externo ao mais interno: na entrada da requisição (`LoginRequest` /
`RegistroRequest`, antes da validação — um espaço na ponta derrubava o `@Email`
com 400), na entidade (`Usuario.setEmail`, que vale para qualquer caminho que
grave um usuário) e no banco (índice único em `lower(email)`, V23). A migração
confere antes se já existem contas que só diferem pela caixa e, se existirem,
**falha dizendo quais** — escolher qual conta fica não é decisão de migração.

**P: Por que as tabelas não tinham chave estrangeira?**
R: Não têm mais essa lacuna: a V11 criou as 16 FKs com `ON DELETE RESTRICT`.
As entidades continuam com `Long` em vez de `@ManyToOne` porque o app nunca
navega por objeto — integridade é do banco, navegação seria custo sem uso.

**P: O que é o score?**
R: Reputação do **entregador** (0 a 5) — o lojista não tem score. Começa em
5.0 e cada **desistência em cima da hora** (o entregador sai da vaga a menos de
1h do início) tira 0.5; nenhum outro evento o muda — nem o turno que a loja
cancela, nem a falta sem check-in —, e ninguém o grava à mão (nem a massa de
demonstração, que desiste pelo próprio `TurnoService`). Enquanto o entregador
não tem histórico — nenhum turno concluído, cancelado ou de que tenha desistido
—, a API devolve o score **nulo** e o app diz "Novo na
plataforma": 5.0 ali seria o ponto de partida da conta apresentado como
reputação conquistada. A **avaliação** é outra coisa: a média das notas que a
pessoa recebeu, recalculada por `AvaliacaoService` a cada avaliação e nula
antes da primeira. No app, estrela é sempre avaliação, nunca score. O "score
de 30 dias atrás" da tela de análise é **estimativa** (reverte as penalizações
da janela) e vai rotulado como tal na resposta da API — medir de verdade
exigiria uma tabela de eventos de score.

**P: Os números da demonstração foram escritos à mão?**
R: Não. A massa passa pelos serviços de verdade: a recarga pelo
`CobrancaService`, o aceite, a finalização, a desistência e o cancelamento pelo
`TurnoService`, a avaliação pelo `AvaliacaoService` e a nota pelo
`NotaFiscalService`, a pedido do lojista. Por isso o score do Thiago é 4,5 —
ele desistiu de uma vaga a menos de 1h do início, e a regra tirou 0,5 —, as
médias são as das notas que cada um recebeu, as notificações são as que o
código gera hoje, e a massa passa na mesma conferência de consistência do
ledger que o banco de produção. A única coisa que vai direto ao repositório é
o turno do passado: a RF04 não deixa publicar com menos de 2h de antecedência,
e um turno de três meses atrás não tem como respeitá-la hoje — ele nasce pelo
repositório e reserva o dinheiro pelo mesmo serviço da publicação.

**P: Quem emite a nota fiscal? A NFS-e não é do prestador?**
R: No mundo real, sim: a NFS-e sai do CNPJ de quem presta — aqui, o entregador
MEI. No MotoShift o documento continua com o entregador como **prestador** e o
lojista como **tomador**, mas quem **pede** a emissão (e o cancelamento) é só o
lojista: a plataforma emite por conta do entregador, a pedido de quem pagou. É
o lojista quem precisa do documento para lançar a despesa e quem tem o
cadastro fiscal completo; o entregador vê, baixa e imprime, e é avisado quando
a nota sai. O modelo separa as duas coisas — `prestador_id` é quem prestou,
`emitida_por_id` é quem pediu —, e o entregador que tenta emitir leva 403.
Numa emissão real, a plataforma precisaria de autorização do MEI no emissor;
isso e o resto do que faltaria estão em `docs/financeiro/FISCAL.md`.

**P: A nota fiscal segue algum modelo oficial, ou é um layout inventado?**
R: Segue o **DANFSe v2.0**, o documento auxiliar da NFS-e do padrão nacional,
definido pela Nota Técnica SE/CGNFS-e nº 008/2026: os mesmos blocos na mesma
ordem (identificação, prestador, tomador, destinatário, intermediário,
serviço, ISSQN, federal, IBS/CBS, totais, informações complementares), a
chave de acesso de 50 dígitos com a composição oficial e o DV em módulo 11, e
o QR Code. O serviço é o item 26.01 da LC 116/2003, e em 2026 a nota destaca
IBS e CBS com as alíquotas do ano de teste da LC 214/2025. O recibo segue a
quitação do art. 320 do Código Civil, com o valor por extenso, e o
comprovante de Pix os campos mínimos do Regulamento Pix. O que **não** se
copiou foi de propósito: nada de brasão ou nome de prefeitura, o QR Code não
leva ao portal do governo, e a marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL"
está em todos — o documento tem a estrutura de um real sem poder passar por
um. As fontes estão na seção 7 do `FISCAL.md`.

**P: E se a API da IA cair?**
R: Nada que tem número para mostrar deixa de mostrar. A análise de score
continua respondendo os números, só sem o texto (`analiseDisponivel: false`), e
o relatório também: os números vêm apurados do extrato e da DRE, e `analise`
vem nulo. Só a sugestão de turnos responde 503, porque ali a resposta É o texto. Toda chamada tem timeout de 20s e cache de 15 minutos por
pergunta — sem isso, cada F5 na tela era uma chamada paga.

**P: Como a API sabe qual banco usar?**
R: Perfis do Spring — sem perfil usa H2 (dev); com `SPRING_PROFILES_ACTIVE=prod`
usa PostgreSQL com Flyway.

**P: E com 10 mil turnos?**
R: As listagens aceitam `?pagina=&tamanho=` e devolvem o total no header
`X-Total-Count`; a contagem de vagas de uma lista inteira sai em uma consulta,
não uma por turno. O app ainda pede a lista completa — a API é que já não
depende disso.

**P: O que está fora do escopo (trabalhos futuros)?**
R: Rastreamento em tempo real, envio de e-mail por um provedor de verdade
(a recuperação de senha existe, mas o e-mail é simulado: o código sai no log
do servidor), revogação de sessão ao trocar a senha, rascunho de turno,
tabela de eventos de score e lock distribuído para os jobs agendados (hoje a
saída é ligar os jobs em uma instância só). O check-in, que estava aqui,
entrou nesta revisão (seção 11).

---

**P: Por que a DRE é em regime de caixa, e não de competência?**
R: Por três motivos. Coerência: o informe anual já conta o rendimento pelo dia
em que foi creditado, e duas telas não podem dizer que o mesmo mês rendeu
valores diferentes. Público: MEI e pessoa física pensam em "quando paguei", não
em "a que mês pertence". E simplicidade: competência exige provisão — contas a
pagar e a receber, estorno de provisão —, que é um sistema contábil, não uma
demonstração simplificada. Vale o `criadoEm` do lançamento concluído e a `data`
do custo informado, e nada entra antes de acontecer.

**P: Por que o custo que o usuário informa não passa pelo ledger?**
R: Porque o ledger registra só dinheiro que a plataforma movimentou, e as três
invariantes dependem disso: "carteira = extrato" vale porque cada linha do
extrato tem um movimento de saldo do outro lado. A gasolina que o entregador
pagou no posto, a plataforma não viu passar — ouviu falar. Se esse número
digitado entrasse no extrato, as invariantes dependeriam da memória de alguém.
Por isso é outra tabela (`lancamentos_gerenciais`), outro serviço, sem o
`LedgerService`, e a DRE junta os dois só na leitura. Há um teste que confere:
criar, editar e excluir um lançamento desses não muda saldo nenhum.

**P: Como o app sabe o custo do entregador?**
R: Não sabe — ele informa. Combustível, manutenção, DAS e contas fixas são
lançados na tela de resultado; conta fixa é lançada uma vez, como recorrente, e
vale todo mês. Para o combustível há uma calculadora (km ÷ consumo × preço do
litro). E a tela é honesta sobre o limite: sem nada informado, ela avisa que o
resultado só conhece o que passou pela plataforma — e a IA do relatório recebe
a mesma instrução.

**P: O que é ponto de equilíbrio aqui?**
R: Quantos turnos o entregador precisa fazer no período para pagar as despesas
fixas: despesas fixas ÷ margem de contribuição média por turno, arredondado
para cima. A margem de contribuição é o que sobra de cada turno depois das
deduções e dos custos variáveis (combustível e manutenção). Se essa margem for
zero ou negativa, não há ponto de equilíbrio — cada turno a mais aumenta o
prejuízo —, e o número vem nulo, com o motivo, em vez de um número absurdo.

### Glossário rápido
- **Turno:** bloco de tempo que o lojista publica e o motoboy reserva.
- **Wallet/Carteira:** saldo de cada conta. O lojista recarrega e reserva o
  valor de cada turno publicado; o entregador recebe na finalização e saca.
- **Score:** reputação do entregador; só aparece depois do primeiro turno.
- **Avaliação:** média das notas recebidas, dos dois lados.
- **DTO:** objeto que trafega entre app e API (não expõe a entidade do banco).
- **Provider:** mecanismo de gerência de estado do Flutter usado no app.

---

## 11. Recursos desta revisão — a regra e onde ela está

Uma seção curta por recurso: o que a regra diz e o arquivo em que ela mora.

### Localização: o pino é a loja

- **Regra.** O turno parte do ponto da loja, marcado uma vez em *Dados
  pessoais* (`usuarios.latitude/longitude`, V15). Sem ele, do GPS; sem GPS, do
  centro da cidade — e aí **publicar pede confirmação**: nenhum turno nasce num
  ponto que ninguém olhou. O toque no mapa sempre vence, inclusive o GPS que
  responde atrasado.
- **Distância.** Quem mede é o backend (`GeoUtils`, Haversine); o app mostra
  a `distanciaKm` que veio, a mesma no card, no pino e no detalhe. A caixa do
  banco (`findAbertosNaArea`) e o círculo usam a mesma Terra: antes a caixa era
  0,1% menor e um turno na borda do raio sumia (`FiltroPorDistanciaTest`).
- **Onde.** `AgendarTurnoScreen._definirPontoInicial` e `_confirmarPonto`;
  `LocalizacaoService` (tempo limite de 15 s, página fora de HTTPS, última
  posição conhecida no celular); `GeoUtils`; `AuthService.definirPontoDaLoja`.

**P: E se o GPS do navegador nunca responder?**
R: Todo pedido de posição tem 15 s de limite — inclusive o aviso de permissão
que ninguém clicou, que era onde a tela ficava "buscando" para sempre. Passou
disso, a tela diz que o aparelho não respondeu e oferece tentar de novo.

### Check-in e check-out: a hora real

- **Regra.** Só o entregador inscrito e aceito; de 30 min antes do início até
  o fim do turno; a até 500 m do ponto (`motoshift.checkin.raio-metros`). A
  trava de distância desliga com `MOTOSHIFT_CHECKIN_EXIGIR_PROXIMIDADE=false`,
  para a apresentação feita de casa. Check-out só depois do check-in. Repetir
  qualquer um não muda nada nem avisa de novo.
- **Status.** O primeiro check-in leva o turno de ACEITO a EM_ANDAMENTO — o
  estado que o enum esperava. Em andamento, o turno **não vence** (o job só
  olha turno aberto) e **não se cancela** — nem o entregador que fez check-in
  desiste da vaga: cancelar devolveria a reserva inteira com alguém
  trabalhando; a saída é finalizar. O job de vencimento,
  ao fechar um turno multi-vaga no início, o leva direto a EM_ANDAMENTO se
  alguém já chegou.
- **Pontualidade.** % de check-ins até 10 min após o início, nos últimos 90
  dias. Sem check-in, "Sem histórico" — nunca 100%.
- **Onde.** `CheckinService`; colunas em `turno_inscricoes` (V16) porque cada
  entregador de um turno multi-vaga chega na sua hora; `Reputacao.pontualidade`;
  no app, `CheckinDoTurno` (detalhe do entregador) e `Presenca`.

**P: Por que a presença mora na inscrição e não no turno?**
R: Porque num turno de três vagas são três chegadas. No turno ficaria uma hora
só — a do primeiro —, e a pontualidade dos outros dois não existiria.

### Publicar de novo: o turno que acabou vira rascunho

- **Regra.** Turno finalizado, cancelado ou expirado do lojista tem
  "Publicar de novo" (lista e detalhe). O formulário abre com título,
  descrição, região, ponto, raio, valor, vagas e duração do turno de origem;
  a data vai para o mesmo dia da semana da semana seguinte, mesmo horário —
  e, se essa data já passou ou fura as 2 h de antecedência, para a próxima
  semana que dá.
- **Nada muda nas regras.** É o mesmo formulário e o mesmo
  `POST /api/turnos`: confirmação do custo, antecedência e saldo valem igual,
  e o backend confere de novo. Por isso não há endpoint novo.
- **Onde.** `RepeticaoDeTurno` (a data e o que se copia),
  `AgendarTurnoScreen(origem:)`, botão em `AcoesDoTurno` e no card de
  `TurnosLojistaListaScreen`.

**P: Por que não um endpoint "repetir turno"?**
R: Porque repetir sem olhar é publicar sem confirmar o custo. O app só
preenche; quem publica é o lojista, pelo caminho de sempre.

### Abrir rota e calendário: o turno fora do app

- **Rota.** Google Maps pela URL universal (`maps/dir/?api=1&destination=`),
  que funciona no navegador e no celular; o Waze só aparece quando o
  `waze://` responde — AndroidManifest e Info.plist declaram a consulta. No
  navegador não dá para saber que apps a pessoa tem, então é o Google Maps.
- **Calendário.** `.ics` pela RFC 5545: `DTSTART;TZID=America/Sao_Paulo`,
  com o VTIMEZONE junto (o backend devolve horário de parede, sem fuso — sem
  o TZID, "18:00" viraria 18:00 de quem abre o arquivo), VALARM de 1 h, texto
  escapado e linhas dobradas em 75 octetos sem partir "ç". Baixa pelo
  `baixarArquivo`, o mesmo da planilha.
- **Onde.** `AbrirRota`, `CalendarioIcs`, `AtalhosDoTurno`.

### Turno esquecido se finaliza sozinho

- **O buraco.** Finalizar transfere dinheiro, e por isso é decisão de quem
  estava lá — o job só **cobrava** a finalização por notificação. Mas cobrar
  não fecha nada: se as duas partes esquecessem o turno, a reserva ficava
  bloqueada na carteira do lojista para sempre e o entregador que trabalhou
  não recebia.
- **Regra.** Passadas `motoshift.finalizacao.automatica-horas` (padrão 12) do
  **fim** do turno, o job o fecha. Com check-in: finaliza pelo mesmo caminho do
  botão (`TurnoService.pagarQuemTrabalhou`) — paga quem chegou, marca `faltou`
  quem não chegou, devolve a sobra. Sem nenhum check-in: as inscrições viram
  `faltou`, a reserva volta inteira (motivo `sem_checkin`) e o turno vai para
  `expirado`. As duas partes são avisadas com `criarUnica`.
- **Por que um método próprio (`finalizarPeloSistema`) e não um "usuário
  sistema".** O que o job precisa pular é só o `exigirParticipante`, que
  responde "esta pessoa pode mexer neste turno?" — e não há pessoa. Inventar
  uma conta de sistema para passar pela trava deixaria um id mágico no banco e
  um caminho para alguém se passar por ele; o método interno não é alcançável
  por rota nenhuma.
- **Uma transação por turno.** Numa só, um turno que não fechasse desfaria o
  fechamento de todos os outros a cada 5 minutos.
- **Onde.** `TurnoExpiracaoService.finalizarTurnosEsquecidos` (a regra) e
  `TurnoExpiracaoJobs` (o agendamento); `FinalizacaoAutomaticaTest` cobre com
  check-in, sem nenhum check-in e dentro do prazo.

**P: E se a instância com os jobs cair?**
R: Nada se perde: o job procura "turnos com fim + prazo no passado", não
"turnos que venceram desde a última volta". Quando a instância volta, fecha o
que ficou. Com réplicas, só uma roda os jobs (`MOTOSHIFT_JOBS_HABILITADOS=false`
nas outras) — e essa configuração **derrubava o boot**: o serviço de expiração
inteiro era condicional aos jobs, e a massa de demonstração depende dele. O
agendamento saiu para uma classe própria (`TurnoExpiracaoJobs`), e
`JobsDesligadosTest` sobe o contexto com os jobs desligados.

### Lembrete de 1 hora

- **Regra.** Job de 5 em 5 min (padrão do vencimento): turno aberto, aceito
  ou em andamento que começa em até 1 h; lembra cada entregador com inscrição
  aceita que ainda não chegou, e a loja uma vez ("com Ricardo e mais 1").
- **Sem duplicar.** `criarUnica` — a notificação que já existe para aquela
  pessoa, tipo e turno é o controle; não precisou de coluna.
- **Onde.** `TurnoLembreteService`; no app, o estilo de `turno_lembrete`.

### Meta do mês

- **Regra.** `usuarios.meta_mensal` (V19), só do entregador, de R$ 1 a
  R$ 100.000, editável no perfil e no painel. A barra compara com
  `ganhosMensais` — pagamentos recebidos + gorjetas do mês, a mesma soma do
  "Ganhos mês". Sem meta, o painel convida a definir: uma barra zerada diria
  "você não ganhou nada", quando o que falta é a meta.
- **Onde.** `AuthService.definirMeta`, `DashboardService.doMotoboy`; no app,
  `MetaDoMes` e `editarMetaDoMes`.

### Selos de reputação

- **Regra.** Calculados na hora a partir do histórico — sem tabela, porque um
  selo guardado envelhece. Entregador: 20 turnos concluídos (o pedido era 25;
  ajustado à massa, em que o entregador mais antigo tem 23); 30 dias sem
  cancelar (histórico mais velho que 30 dias e nenhuma desistência DELE no
  período); nota acima de 4,8 com 10 avaliações ou mais; pontual (90% ou mais
  com 10 check-ins ou mais). Loja: paga gorjeta (3 ou mais em turnos dos
  últimos 90 dias); nota acima de 4,8; contrata toda semana (turno concluído
  em cada uma das últimas 4 semanas).
- **Quem cancelou.** O turno só é cancelado pela loja (`cancelado_por_id` e
  `cancelado_em` no turno, V19), e isso não tira selo de ninguém. O entregador
  **desiste da vaga**, e a desistência mora na inscrição dele — a V22 pôs
  `cancelado_por_id` e `cancelado_em` em `turno_inscricoes`, porque desistir não
  cancela o turno: a vaga reabre e ele segue. É dali que o selo e a análise de
  score leem. O cancelamento que um entregador fez pela regra antiga foi levado
  para a inscrição pelo backfill da V22, e continua contando — só contra ele.
- **Onde.** `Selos` (os limites são constantes no topo), no perfil público
  (`AuthService.buscarPerfilPublico`) e nos painéis; no app,
  `SelosDeReputacao`, com o critério num diálogo ao tocar.

**P: Por que o selo não é guardado?**
R: Porque ele é uma pergunta sobre o histórico ("desistiu de alguma vaga nos
últimos 30 dias?"). Guardado, ficaria verdadeiro depois de deixar de ser.

### Favoritos: a loja guarda quem trabalhou bem

- **Regra.** Só o lojista favorita, e só entregador é favorito. Um favorito
  por par (loja, entregador): a chave primária da tabela `favoritos` (V18) é
  o próprio par, então nem dois cliques simultâneos duplicam — o segundo bate
  na chave e o controller refaz a chamada, que encontra o que existe.
  Desfavoritar o que não é favorito não é erro.
- **O efeito.** Publicar um turno avisa os favoritos da loja ("A
  Hamburgueria da Cláudia publicou um turno para amanhã, 18h"), na mesma
  transação da publicação — turno recusado por saldo não avisa ninguém. Na
  lista de disponíveis do entregador, os turnos dessas lojas levam o selo
  "Loja que já te chamou", calculado numa consulta só.
- **Papéis.** A lista é da loja. O entregador não vê quem o favoritou; vê
  só o selo nos turnos daquela loja.
- **Onde.** `FavoritoService`, `FavoritoController`, `Favorito` (chave
  composta), V18; `TurnoService.criar` chama `avisarFavoritos`;
  `TurnoController.disponiveis` marca o selo. No app, `FavoritosProvider`,
  `BotaoFavorito`, `FavoritosDoLojista` (perfil) e `SeloLojaQueTeChamou`.

**P: "da Mercado"? Como o texto acerta o artigo?**
R: `Artigo` olha a primeira palavra do nome da loja: "Hamburgueria" é
feminina, "Mercado" é masculina — "O Mercado do Fernando publicou um turno".
A mesma regra vale para a notificação da gorjeta.

### Gorjeta: dinheiro a mais, pelo mesmo livro

- **Regra.** Só o lojista do turno, só com o turno finalizado e só a quem
  trabalhou nele (inscrição finalizada); uma por entregador por turno; de
  R$ 1 a `motoshift.gorjeta.maximo` (R$ 50); só do saldo **disponível** — o
  bloqueado é das reservas. Sem saldo, 422 com quanto há.
- **Idempotente.** Chave `gorjeta:turno:{t}:entregador:{e}:debito|credito`.
  A mesma gorjeta pedida de novo devolve a que existe; outro valor para o
  mesmo entregador no mesmo turno é recusado (409).
- **Dois tipos, um de cada lado.** Débito do lojista `bonus_enviado`,
  crédito do entregador `bonus`, mesma `operacao_id`, os dois com o
  `turno_id`. O tipo decide a aritmética do saldo (a invariante (c) do
  `ConsistenciaService`); um tipo só com o sinal na `natureza` quebraria essa
  regra. Por isso a V17 só alarga o CHECK.
- **Fiscal.** Gorjeta não é serviço: gera comprovante, não NFS-e
  (FISCAL.md).
- **Onde.** `GorjetaService`, `Movimento.gorjeta`, V17; no app,
  `SeletorDeGorjeta` dentro de `AvaliacaoScreen` e
  `AvaliarEntregadoresScreen`. Aparece no extrato ("Gorjeta recebida" /
  "Gorjeta enviada"), no resumo, nos relatórios e no CSV.

**P: E se a avaliação for enviada e a gorjeta falhar?**
R: São duas chamadas: a nota fica, e a tela diz "Avaliação enviada, mas a
gorjeta não" com o motivo do backend. Nada de dinheiro se move pela metade —
a gorjeta é uma transação só no `LedgerService`.

### Resultado financeiro: lucro e prejuízo

- **O problema.** O app dizia quanto entrou, não quanto sobrou. "Ganhos", para o
  entregador, era faturamento bruto — sem combustível, manutenção, DAS e contas
  fixas. O lojista via o gasto com entregas, não o que elas renderam. Foi o
  pedido da correção: uma parte contábil mais forte, com lucro e prejuízo.
- **A regra.** Uma DRE simplificada para cada papel, em regime de caixa
  (RF13). Entregador: receita bruta (pagamentos + gorjetas) − deduções
  (retenções + DAS) = receita líquida − custos variáveis (combustível,
  manutenção) = margem de contribuição − despesas fixas = resultado. Lojista:
  taxas de entrega cobradas − custo dos entregadores − entregas fora do app =
  margem da operação − outras despesas = resultado. Reserva e liberação não
  entram: são o dinheiro do lojista mudando de bolso.
- **O que o usuário informa não é transação.** Fica em `lancamentos_gerenciais`
  (V25), não move saldo, não entra no extrato e não gera documento fiscal. A
  categoria diz o papel e o grupo da DRE — não há coluna "tipo". Conta fixa é
  recorrente: uma regra mensal (dia 31 vira 28 em fevereiro), e não uma linha
  gravada por mês.
- **Onde.** `DreService` (as duas demonstrações e os indicadores),
  `LancamentoGerencialService`, `Recorrencia` (função pura), `DreController` e
  `LancamentoGerencialController` em `/api/financeiro`. No app,
  `views/resultado/`: a faixa diz a situação por extenso ("Prejuízo de R$
  220,55 no período"), a tabela mostra a origem de cada linha (extrato ou
  informado por você) e o PDF do relatório ganhou a seção "Demonstração do
  resultado".
- **Como é testado.** `DreServiceTest` (lucro, prejuízo, equilíbrio, período
  vazio, reserva fora, gorjeta nos dois lados, ponto de equilíbrio nulo),
  `RecorrenciaTest`, `LancamentoGerencialHttpTest` (404 para o de outro
  usuário, categoria do papel errado, 401 sem token) e
  `LancamentosGerenciaisForaDoLedgerTest` — criar, editar e excluir não mexem
  em saldo nem nas invariantes.
- **Na demonstração.** `motoboy@teste.com` (Carlos) e `claudia@teste.com`: o
  mês passado fecha com lucro e o retrasado com prejuízo — o Carlos por uma
  manutenção de R$ 420, a Cláudia por uma promoção de frete grátis. O detalhe
  está em `docs/financeiro/RESULTADO.md`.

### A massa conta tudo isso

- **Pelos serviços de verdade.** Chegada e saída pelo `CheckinService`
  (numa sobrecarga que recebe a hora: a regra é a mesma, conferida contra a
  hora do turno do passado), gorjeta pelo `GorjetaService`, favoritos pelo
  `FavoritoService`, meta pelo `AuthService.atualizar`, o aviso aos favoritos
  pelo `avisarFavoritos` e o lembrete pelo próprio job. A massa só reescreve a
  data do que cada passo gravou.
- **O que mostra.** Pontualidades diferentes (Ricardo 100%, Carlos ~92%,
  Lucas ~73%, Thiago ~30%); um turno em andamento com check-in; gorjetas da
  Cláudia e duas do Fernando; favoritos de três lojas; meta do Ricardo e do
  Carlos (Lucas e Thiago veem o convite); selos em uns perfis e em outros não;
  lembrete de 1 hora e avisos de chegada e de favorito ainda não lidos. E o
  resultado: o Carlos e a Cláudia com um mês de lucro e um de prejuízo, pelos
  custos e receitas que informaram (`LancamentoGerencialService`).
- **Continua fechando.** `MassaDemonstracaoTest.massaFechaNasInvariantes`
  passa a massa pela `verificarConsistencia()`, agora com gorjetas no meio;
  `novidadesNaMassa` confere cada item acima; `ResetDaMassaPostgresTest`
  confere, no Postgres, que um favorito ou um cancelamento de conta real
  cruzado com a massa não trava o reset nas FKs.

**P: A massa grava direto no banco?**
R: Só o que a regra do presente não deixaria fazer no passado (publicar um
turno de três meses atrás, que a RF04 barraria) e as datas. Dinheiro, presença,
gorjeta e favoritos passam pelos serviços — por isso a massa também testa as
regras.
