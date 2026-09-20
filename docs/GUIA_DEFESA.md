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
| **Config** | `config/` | `MassaDemonstracao` (massa de teste: `popular()` e `resetar()`), `DataInitializer` (gatilho em dev) e `ResetDaMassaNoBoot` (reset com trava em qualquer ambiente) |

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
| RF06 | Confirmação dupla credita a carteira (Wallet) | `TurnoService.finalizar()` + `confirmar*()` | — |
| RF07 | Cancelar < 1h penaliza o score (−0.5) | `TurnoService.cancelar()` | — |

**Regras de negócio mais "perguntáveis":**
- *Antecedência de 2h:* `LocalDateTime.now().plusHours(2)` — turno antes disso é rejeitado (HTTP 400).
- *Conflito de horário:* `TurnoRepository.existeConflitoDeAgenda()` — olha as
  inscrições ativas do entregador (inclusive em turno multi-vaga que segue
  "aberto"); se houver sobreposição, retorna HTTP 409.
- *Crédito na carteira:* só ocorre quando **lojista E motoboy** confirmam (dupla confirmação).
- *Penalidade de score:* cancelamento com menos de 1h subtrai 0.5 (mínimo 0.0).

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
- **Massa de demonstração:** `MassaDemonstracao` (`popular()` / `resetar()`).
  Em dev nasce com o banco vazio; em produção é recriada pelo reset com trava
  (`MOTOSHIFT_SEED_RESET=confirmo`), com datas sempre calculadas a partir do
  momento em que roda. O passo a passo está no README.

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
R: Reputação do motoboy (0 a 5). Cancelamento tardio (<1h) penaliza em 0.5;
avaliações dos lojistas alimentam a média. O "score de 30 dias atrás" da tela
de análise é **estimativa** (reverte as penalizações da janela) e vai rotulado
como tal na resposta da API — medir de verdade exigiria uma tabela de eventos
de score.

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
- **Wallet/Carteira:** saldo do motoboy, creditado ao concluir turnos.
- **Score:** nota de reputação do motoboy.
- **DTO:** objeto que trafega entre app e API (não expõe a entidade do banco).
- **Provider:** mecanismo de gerência de estado do Flutter usado no app.
