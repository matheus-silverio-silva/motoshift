# 🎓 Guia de Defesa — MotoShift

Resumo técnico do código para apoiar respostas a perguntas da banca.
Cada item aponta **onde no código** a funcionalidade vive.

---

## 1. Resumo em uma frase

MotoShift é um MVP de logística urbana baseado em **agendamento de turnos**
(em vez do despacho imediato dos apps tradicionais), conectando **lojistas**
que publicam turnos e **motoboys** que os reservam — com app em **Flutter**,
API em **Java/Spring Boot** e banco **MySQL** (H2 em desenvolvimento).

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
                                                  ┌───────▼────────┐
                                                  │ MySQL (prod)   │
                                                  │ H2 (dev)       │
                                                  └────────────────┘
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
| **Config** | `config/` | `DataInitializer` (seed de dados de teste) |

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

> ⚠️ **Ponto que a banca pode notar:** existem pastas de *Clean Architecture*
> (`domain/`, `data/repositories/`) **e** uma organização mais pragmática
> (`views/`, `models/`, `services/`). Resposta honesta: *"O núcleo segue
> camadas (apresentação → serviço/repositório → modelo); as pastas `domain`/`data`
> foram introduzidas para isolar regras de negócio dos repositórios, e a migração
> é parcial — convivem por ser um MVP em evolução."*

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
- *Conflito de horário:* query `findConflitos()` — se houver sobreposição, retorna HTTP 409.
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

- **Dev:** H2 em memória (console em `/h2-console`) — zero configuração.
- **Prod:** MySQL (perfil `prod`, `application-prod.properties`).
- `ddl-auto=update` — Hibernate cria/atualiza tabelas automaticamente.
- `DataInitializer` popula usuários, turnos, carteiras e avaliações de teste na
  primeira inicialização (só se o banco estiver vazio).

---

## 8. Deploy

- **Railway** para os dois serviços.
- Front-end: **Dockerfile multi-stage** (`flutter build web` → servido por **nginx**, com fallback de SPA).
- Back-end: perfil `prod` + MySQL; porta via `$PORT`.

---

## 9. Testes

- **Back-end:** JUnit 5 + Mockito — 14 testes (`AuthServiceTest`, `TurnoServiceTest`),
  cobrindo RF01, RF04 e RF05, incluindo casos de borda (antecedência exata, conflito, 404/409).
- **Front-end:** *golden tests* (comparação visual de telas) + testes de widget.
- *Observação:* golden tests podem acusar diferença mínima de pixels entre
  máquinas (renderização de fonte) — é cosmético, não falha de lógica.

---

## 10. Perguntas prováveis da banca + respostas curtas

**P: Por que Flutter?**
R: Um único código-base para Android, iOS e Web — reduz custo/tempo de um MVP.

**P: Por que turnos em vez de despacho imediato?**
R: É a tese do trabalho — o despacho imediato gera ociosidade não-remunerada ao
motoboy e indisponibilidade ao lojista em picos. O turno agendado dá previsibilidade aos dois lados.

**P: Como garante que dois motoboys não peguem o mesmo turno?**
R: Ao aceitar, o serviço verifica se o turno ainda está "aberto" e checa conflito
de agenda; caso contrário retorna HTTP 409 (conflito).

**P: A senha é segura?**
R: No MVP, senha em texto plano e token em memória (marcado como "apenas dev").
Para produção, o próximo passo é hash (BCrypt) e JWT persistente — é uma limitação
consciente de escopo do MVP.

**P: O que é o score?**
R: Reputação do motoboy (0 a 5). Cancelamento tardio (<1h) penaliza em 0.5;
avaliações dos lojistas alimentam a média.

**P: Como a API sabe qual banco usar?**
R: Perfis do Spring — sem perfil usa H2 (dev); com `SPRING_PROFILES_ACTIVE=prod` usa MySQL.

**P: O que está fora do escopo (trabalhos futuros)?**
R: Rastreamento em tempo real, redefinição de senha por e-mail, rascunho de turno,
e segurança de produção (hash/JWT).

---

### Glossário rápido
- **Turno:** bloco de tempo que o lojista publica e o motoboy reserva.
- **Wallet/Carteira:** saldo do motoboy, creditado ao concluir turnos.
- **Score:** nota de reputação do motoboy.
- **DTO:** objeto que trafega entre app e API (não expõe a entidade do banco).
- **Provider:** mecanismo de gerência de estado do Flutter usado no app.
