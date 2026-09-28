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
| **Entity** | `entity/` | Tabelas do banco (`Usuario`, `Turno`, `Carteira`, `Transacao`, `Avaliacao`) |
| **DTO** | `dto/` | Objetos de transferência (separa API do modelo interno) |
| **Config** | `config/` | `MassaDemonstracao` (massa de teste: `popular()`, `resetar()` e `apagarTudoERecriar()`), `DataInitializer` (gatilho em dev) e `ResetDaMassaNoBoot` (os dois resets, com trava, em qualquer ambiente) |

**Fluxo de uma requisição** (ex: aceitar turno):
`PUT /api/turnos/{id}/aceitar` → `TurnoController` → `TurnoService.aceitar()`
(valida conflito de horário) → `TurnoRepository.save()` → retorna `TurnoResponse`.

Serviços principais: `AuthService`, `TurnoService`, `CarteiraService`,
`AnthropicService` (IA).

---

## 4. Front-end (Flutter)

- **Gerência de estado:** `Provider` (`ChangeNotifier`) — providers em
  `presentation/providers/` (ex: `TurnoProvider`, `PedidoProvider`).
- **Telas:** `views/` (uma pasta por tela: login, dashboards, agenda, carteira…).
- **Acesso à API:** `services/api_service.dart` centraliza as chamadas HTTP;
  `services/auth_service.dart` cuida da sessão.
- **Tema:** `theme/app_theme.dart` (Material Design 3, fontes via `google_fonts`).
- **Mapa:** `flutter_map` (OpenStreetMap) para região de entrega.

> **Se perguntarem por Clean Architecture:** existiam `domain/` e `data/` de uma
> tentativa anterior, com dois providers registrados no boot e nenhuma tela
> consumindo. Foram removidas. Resposta honesta: *"Conviver com duas
> arquiteturas é pior do que ter uma; o app segue `views` + `providers` +
> `services`, que é o que as telas realmente usam."*

**Configuração da URL da API:** injetada em build via
`--dart-define=API_URL=...` e lida em `api_service.dart`
(`String.fromEnvironment('API_URL')`). Em dev usa `10.0.2.2:8080` (emulador
Android) ou `localhost:8080`.

---

## 5. Requisitos Funcionais — onde estão no código

| RF | Regra | Local | Testado? |
|----|-------|-------|----------|
| RF01 | Login + bloqueio após 5 falhas por 15 min | `AuthService.login()` | ✅ |
| RF02 | Dashboard lojista/motoboy | `DashboardController` + `views/dashboard_*` | — |
| RF03 | Cadastro: CNPJ (14 díg.) / CNH (11 díg.) | `AuthService.registrar()` | parcial |
| RF04 | Publicar turno, antecedência mínima de 2h | `TurnoService.criar()` | ✅ |
| RF05 | Reservar turno, sem conflito de horário | `TurnoService.aceitar()` | ✅ |
| RF06 | Finalizar transfere o valor reservado para o entregador, na mesma transação | `TurnoService.finalizar()` + `PagamentoTurnoService.liquidar()` | ✅ |
| RF07 | Cancelar < 1h penaliza o score do entregador (−0.5) | `TurnoService.cancelar()` + `Reputacao` | ✅ |

**Regras de negócio mais "perguntáveis":**
- *Antecedência de 2h:* `LocalDateTime.now().plusHours(2)` — turno antes disso é rejeitado (HTTP 400).
- *Conflito de horário:* `TurnoRepository.existeConflitoDeAgenda()` — olha as
  inscrições ativas do entregador (inclusive em turno multi-vaga que segue
  "aberto"); se houver sobreposição, retorna HTTP 409.
- *Crédito na carteira:* acontece na **finalização do turno**, na mesma transação que o encerra —
  o valor sai do saldo **bloqueado** do lojista (reservado quando ele publicou) e entra no
  **disponível** do entregador. Não há confirmação a dar: o compromisso foi assumido na publicação.
  A dupla confirmação manual que existia aqui foi removida (V13) — ver `docs/financeiro/FLUXO-FINANCEIRO.md`.
- *Penalidade de score:* cancelamento com menos de 1h subtrai 0.5 (mínimo 0.0).
  A regra (valor inicial e penalidade) mora em `Reputacao`, num lugar só.

---

## 6. Inteligência Artificial (Claude / Anthropic)

- `AnthropicService` chama a API da Anthropic (modelo `claude-sonnet-4`).
- Usado em: **sugestão de turnos**, **relatórios** (financeiro/operacional) e
  **análise de score** — endpoints `/api/sugestoes`, `/api/relatorio`, `/api/score`.
- A chave (`ANTHROPIC_API_KEY`) vem de variável de ambiente — **nunca** fica no código.

> Se perguntarem "a IA é essencial?": *"Não para o fluxo central de turnos;
> é uma camada de valor agregado (recomendação e relatórios em linguagem natural)."*

---

## 7. Banco de dados

- **Dev:** H2 em memória (console em `/h2-console`), recriado a cada boot —
  zero configuração. Flyway desligado: as migrações são SQL PostgreSQL.
- **Prod:** PostgreSQL no Railway (perfil `prod`, `application-prod.properties`).
- **O schema é das migrações, não do Hibernate.** `ddl-auto=validate` em
  produção: o Hibernate só confere se as entidades batem com o que o Flyway
  criou. São 11 migrações versionadas em `db/migration`, cada uma com o motivo
  escrito no cabeçalho.
- **Integridade no banco.** Desde a V11 são 16 `FOREIGN KEY` com
  `ON DELETE RESTRICT`. As entidades continuam referenciando por `Long`, sem
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

- **Railway** para os dois serviços.
- Front-end: **Dockerfile multi-stage** (`flutter build web` → servido por **nginx**, com fallback de SPA).
- Back-end: perfil `prod` + PostgreSQL; porta via `$PORT`; healthcheck em
  `/actuator/health`.
- **Variáveis obrigatórias:** `JWT_SECRET` e `MOTOSHIFT_CORS_ORIGINS`. Sem
  elas o boot falha de propósito — melhor o deploy não subir do que subir
  assinando token com chave de exemplo ou liberando qualquer origem.

---

## 9. Testes

- **Back-end:** 146 testes (JUnit 5, Mockito, `@SpringBootTest`, `@DataJpaTest`),
  cobrindo RF01 e RF04–RF07, autorização de ponta a ponta (sem token → 401,
  token de outra pessoa → 403, dono → 200), liquidação do pagamento e
  idempotência.
- **Migrações e schema em PostgreSQL de verdade:** um servidor embarcado sobe
  no próprio teste (sem Docker) e roda Flyway + `ddl-auto=validate` — inclusive
  os casos difíceis, como migrar um banco que já tem linha órfã. Antes disso, a
  primeira execução real das migrações era o deploy.
- **Front-end:** 91 testes — unidade, widget, acessibilidade (alvo de toque) e
  *golden tests* (comparação visual das telas).
- *Observação:* os goldens rodam no CI em `windows-latest` porque foram
  gravados com a fonte do sistema; em outro SO o texto sairia em outra fonte e
  todos falhariam por diferença de renderização, não por regressão.

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
409. O turno fecha (ACEITO) quando a última vaga é preenchida.

**P: A senha é segura?**
R: BCrypt, sempre — no cadastro, na massa de demonstração e no login, que não
aceita outro formato. As contas antigas do Railway, gravadas em texto puro
antes disso, foram convertidas pela migração V9. O token é JWT assinado
(HS256), com o segredo vindo de variável de ambiente.

**P: E o bloqueio de login do RF01?**
R: Cinco erros bloqueiam a conta por 15 minutos, e o contador fica em duas
colunas de `usuarios` — não em memória. Assim o bloqueio sobrevive a um
redeploy, vale igual em todas as instâncias e só existe para conta que existe.
O custo conhecido é que quem sabe seu e-mail pode te deixar 15 minutos fora;
mitigar isso pede captcha ou segundo fator, que estão fora do escopo.

**P: Por que as tabelas não tinham chave estrangeira?**
R: Não têm mais essa lacuna: a V11 criou as 16 FKs com `ON DELETE RESTRICT`.
As entidades continuam com `Long` em vez de `@ManyToOne` porque o app nunca
navega por objeto — integridade é do banco, navegação seria custo sem uso.

**P: O que é o score?**
R: Reputação do **entregador** (0 a 5) — o lojista não tem score. Começa em
5.0 e cada cancelamento tardio (<1h) tira 0.5; nenhum outro evento o muda, e
ninguém o grava à mão (nem a massa de demonstração, que cancela pelo próprio
`TurnoService`). Enquanto o entregador não tem histórico — nenhum turno
concluído nem cancelado —, a API devolve o score **nulo** e o app diz "Novo na
plataforma": 5.0 ali seria o ponto de partida da conta apresentado como
reputação conquistada. A **avaliação** é outra coisa: a média das notas que a
pessoa recebeu, recalculada por `AvaliacaoService` a cada avaliação e nula
antes da primeira. No app, estrela é sempre avaliação, nunca score. O "score
de 30 dias atrás" da tela de análise é **estimativa** (reverte as penalizações
da janela) e vai rotulado como tal na resposta da API — medir de verdade
exigiria uma tabela de eventos de score.

**P: Os números da demonstração foram escritos à mão?**
R: Não. A massa passa pelos serviços de verdade: a recarga pelo
`CobrancaService`, o aceite, a finalização e o cancelamento pelo
`TurnoService`, a avaliação pelo `AvaliacaoService` e a nota pelo
`NotaFiscalService`, a pedido do lojista. Por isso o score do Thiago é 4,5 —
ele cancelou um turno a menos de 1h do início, e a regra tirou 0,5 —, as
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

**P: E se a API da IA cair?**
R: A análise de score continua respondendo os números, só sem o texto
(`analiseDisponivel: false`). Relatório e sugestão respondem 503, porque ali a
resposta É o texto. Toda chamada tem timeout de 20s e cache de 15 minutos por
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
R: Rastreamento em tempo real, redefinição de senha por e-mail, rascunho de
turno, check-in do entregador (o estado EM_ANDAMENTO existe e é lido, mas
ninguém o escreve), tabela de eventos de score e lock distribuído para os jobs
agendados (hoje a saída é ligar os jobs em uma instância só).

---

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
