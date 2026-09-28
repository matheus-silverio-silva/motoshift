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
turno, tabela de eventos de score e lock distribuído para os jobs agendados
(hoje a saída é ligar os jobs em uma instância só). O check-in, que estava
aqui, entrou nesta revisão (seção 11).

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

### Check-in e check-out: a hora real

- **Regra.** Só o entregador inscrito e aceito; de 30 min antes do início até
  o fim do turno; a até 500 m do ponto (`motoshift.checkin.raio-metros`). A
  trava de distância desliga com `MOTOSHIFT_CHECKIN_EXIGIR_PROXIMIDADE=false`,
  para a apresentação feita de casa. Check-out só depois do check-in. Repetir
  qualquer um não muda nada nem avisa de novo.
- **Status.** O primeiro check-in leva o turno de ACEITO a EM_ANDAMENTO — o
  estado que o enum esperava. Em andamento, o turno **não vence** (o job só
  olha turno aberto) e **não se cancela**: cancelar devolveria a reserva
  inteira com alguém trabalhando; a saída é finalizar. O job de vencimento,
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
  cancelar (histórico mais velho que 30 dias e nenhum cancelamento DELE no
  período); nota acima de 4,8 com 10 avaliações ou mais; pontual (90% ou mais
  com 10 check-ins ou mais). Loja: paga gorjeta (3 ou mais em turnos dos
  últimos 90 dias); nota acima de 4,8; contrata toda semana (turno concluído
  em cada uma das últimas 4 semanas).
- **Quem cancelou.** Cancelar é dos dois lados, e sem saber quem cancelou um
  cancelamento da loja tiraria o selo do entregador. Por isso a V19 grava
  `cancelado_por_id` e `cancelado_em` no turno.
- **Onde.** `Selos` (os limites são constantes no topo), no perfil público
  (`AuthService.buscarPerfilPublico`) e nos painéis; no app,
  `SelosDeReputacao`, com o critério num diálogo ao tocar.

**P: Por que o selo não é guardado?**
R: Porque ele é uma pergunta sobre o histórico ("cancelou nos últimos 30
dias?"). Guardado, ficaria verdadeiro depois de deixar de ser.

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
  lembrete de 1 hora e avisos de chegada e de favorito ainda não lidos.
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
