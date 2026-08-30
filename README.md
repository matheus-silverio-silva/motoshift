# 🏍️ MotoShift

> Plataforma de agendamento de turnos para motoboys autônomos
> e pequenos lojistas urbanos.

MVP desenvolvido como trabalho acadêmico no Centro Universitário
UNIFACEAR — Curso de Sistemas de Informação.

---

## 📋 Sobre o Projeto

O MotoShift resolve um problema real da logística urbana:
a falta de previsibilidade tanto para motoboys quanto para
lojistas. Em vez do despacho imediato algorítmico, o sistema
adota agendamento por turnos, garantindo organização e
estabilidade financeira para ambos os lados.

---

## 🛠️ Stack Tecnológica

| Camada | Tecnologia |
|--------|-----------|
| Front-end | Flutter (Android/iOS/Web) |
| Back-end | Java 17 + Spring Boot 3.3.6 |
| Segurança | Spring Security + JWT (HS256) + BCrypt |
| Banco de dados | H2 (desenvolvimento) / PostgreSQL + Flyway (produção) |
| IA | Claude Sonnet 4 (Anthropic API) |
| Documentação | Springdoc OpenAPI / Swagger UI |
| Deploy | Railway (back-end + front-end web via Docker/nginx) |
| Versionamento | Git + GitHub |

---

## 🗂️ Organização do Repositório

```
.
├── backend/                  # API Spring Boot (Java 17)
│   └── src/main/java/com/motoshift/
│       ├── config/           # Boot: seed de dev, OpenAPI, handler de erro da API
│       ├── controller/       # HTTP e só: recebe, autoriza, delega, devolve
│       ├── dto/              # Contratos de entrada e saída (inclui ErroResponse)
│       ├── entity/           # Entidades JPA
│       ├── repository/       # Spring Data
│       ├── security/         # Spring Security, filtro JWT e o usuário do token
│       ├── service/          # Regra de negócio
│       └── util/             # Geo (Haversine, bounding box)
│
├── Motoshift/                # App Flutter (Android, iOS e Web)
│   ├── lib/
│   │   ├── models/           # Modelos que as telas consomem
│   │   ├── presentation/     # Providers (estado compartilhado)
│   │   ├── routes/           # Nomes de rota
│   │   ├── services/
│   │   │   ├── api/          # ApiClient (transporte) + uma API por domínio
│   │   │   ├── api_service   # Monta as APIs de domínio sobre um cliente só
│   │   │   └── auth_service  # Sessão: login, logout, restauração
│   │   ├── theme/  utils/  widgets/
│   │   └── views/            # Uma pasta por tela
│   └── test/                 # Unidade, widget, acessibilidade e goldens
│
├── design/
│   ├── prototipos/           # Protótipos navegáveis (identidade atual)
│   └── stitch/               # Exports do Stitch da 1ª iteração — referência
│
├── docs/                     # Auditoria, guia de defesa, planos e requisitos
├── scripts/                  # Utilitários de linha de comando
└── .github/workflows/        # CI: mvn test, flutter analyze, flutter test
```

Duas notas sobre o que **não** está mais aqui, porque a pergunta costuma
aparecer na revisão:

- **Não há `lib/domain` nem `lib/data`.** Existiam entidades e repositórios de
  uma tentativa anterior de Clean Architecture, com dois providers registrados
  no boot e nenhuma tela os consumindo. Conviver com duas arquiteturas é pior
  do que ter uma: o app segue o padrão `views` + `providers` + `services`.
- **A identidade do usuário nunca vem do corpo da requisição.** Ela sai do JWT,
  no `security/`. Os `lojistId`/`motoboyId` que o app ainda envia são ignorados
  pelo backend.


## ⚙️ Como Rodar Localmente

### Pré-requisitos
- Java 17+
- Flutter SDK 3.x+
- Maven 3.9+
- Chave de API da Anthropic (para funcionalidades de IA)

### Back-end (Spring Boot)

```bash
# 1. Clone o repositório
git clone https://github.com/matheus-silverio-silva/motoshift.git
cd motoshift/backend

# 2. Configure as variáveis de ambiente
cp src/main/resources/application.properties.example \
   src/main/resources/application.properties
# Edite o application.properties com suas chaves

# 3. Configure a chave Anthropic (Linux/Mac)
export ANTHROPIC_API_KEY=sk-ant-api03-...

# Windows (PowerShell)
$env:ANTHROPIC_API_KEY="sk-ant-api03-..."

# 4. Rode o back-end
mvn spring-boot:run
```

Acesse o console H2 em: `http://localhost:8080/h2-console`
- JDBC URL: `jdbc:h2:mem:motoshiftdb`
- User: `sa` | Password: *(vazio)*

Swagger UI: `http://localhost:8080/swagger-ui.html`

### Front-end (Flutter)

```bash
cd motoshift/Motoshift

# Instale as dependências
flutter pub get

# Rode o app (emulador Android usa 10.0.2.2 automaticamente)
flutter run

# Para web, apontando para um back-end específico:
flutter run -d chrome --dart-define=API_URL=http://localhost:8080
```

---

## 🚀 Deploy (Railway)

Ambos os serviços são publicados no **Railway**.

### Front-end (Flutter Web)

A pasta [`Motoshift/`](Motoshift/) contém um **Dockerfile** multi-stage que o
Railway detecta automaticamente:

1. **Build** — `flutter build web --release`, com a URL da API injetada em
   tempo de build via `--dart-define=API_URL`.
2. **Serve** — os arquivos estáticos são servidos por **nginx** com fallback de
   SPA (todas as rotas caem em `index.html`).

Variável de ambiente necessária no serviço front-end:

| Variável | Exemplo | Observação |
|----------|---------|------------|
| `API_URL` | `https://motoshift-backend.up.railway.app` | URL base do back-end, **sem** `/api` no final (o app já anexa) |

### Back-end (Spring Boot)

Roda com o perfil `prod` (PostgreSQL). Variáveis principais:

| Variável | Obrigatória | Descrição |
|----------|-------------|-----------|
| `SPRING_PROFILES_ACTIVE` | sim | Defina como `prod` |
| `JWT_SECRET` | **sim** | Segredo de assinatura dos tokens, mínimo 32 caracteres. Sem ele o boot falha de propósito — melhor não subir do que assinar token com a chave de exemplo do repositório. Trocar o valor invalida os tokens emitidos, ou seja, desloga todo mundo |
| `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` | sim | Conexão com o PostgreSQL (o plugin do Railway já as injeta) |
| `ANTHROPIC_API_KEY` | sim | Chave da API Anthropic para as funcionalidades de IA |
| `MOTOSHIFT_CORS_ORIGINS` | não | Origens liberadas no CORS, separadas por vírgula (ex.: `https://motoshift.up.railway.app`). O padrão `*` libera qualquer origem |
| `JWT_EXPIRACAO_HORAS` | não | Validade do token; padrão 168 (7 dias) |
| `PORT` | não | Porta do servidor (injetada automaticamente pelo Railway) |

---

## 🔑 Credenciais de Teste

Todos os usuários abaixo usam a senha **`senha123`**. São criados automaticamente
na primeira inicialização (junto com turnos, carteiras, avaliações e histórico),
desde que o banco esteja vazio.

### 🏪 Lojistas

| Email | Nome | Estabelecimento | Cidade |
|-------|------|-----------------|--------|
| `claudia@teste.com` | Cláudia Oliveira | Hamburgueria da Cláudia | Curitiba/PR |
| `fernando@teste.com` | Fernando Costa | Pizzaria do Fernando | Curitiba/PR |
| `ana@teste.com` | Ana Souza | Farmácia Ana | Curitiba/PR |
| `lojista@teste.com` | Maria Andrade | Mercado Andrade | São Paulo/SP |

### 🏍️ Motoboys

| Email | Nome | Veículo | Score |
|-------|------|---------|-------|
| `ricardo@teste.com` | Ricardo Souza | Honda CG 160 Titan | 4.7 |
| `lucas@teste.com` | Lucas Mendes | Yamaha Factor 150 | 4.9 |
| `thiago@teste.com` | Thiago Alves | Honda Biz 125 | 3.1 |
| `motoboy@teste.com` | Carlos Mendes | Honda PCX 150 | 5.0 |

> 💡 Para explorar o fluxo completo, recomendamos **`claudia@teste.com`** (lojista
> com vários turnos) e **`ricardo@teste.com`** (motoboy com histórico, carteira e
> avaliações). Os turnos de teste cobrem cenários abertos, em andamento,
> concluídos, pendentes de pagamento e cancelados.

---

## 📡 Principais Endpoints da API

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| POST | /api/auth/registro | Cadastro de usuário |
| POST | /api/auth/login | Autenticação |
| GET | /api/turnos/disponiveis | Listar turnos disponíveis |
| POST | /api/turnos | Criar novo turno (Lojista) |
| PUT | /api/turnos/{id}/aceitar | Aceitar turno (Motoboy) |
| PUT | /api/turnos/{id}/finalizar | Finalizar turno |
| PUT | /api/turnos/{id}/cancelar | Cancelar turno |
| GET | /api/dashboard/motoboy/{id} | Métricas do Motoboy |
| GET | /api/dashboard/lojista/{id} | Métricas do Lojista |
| GET | /api/carteira/{id} | Saldo e ganhos |
| GET | /api/sugestoes/turnos/{id} | Sugestões por IA |
| GET | /api/relatorio/motoboy/{id} | Relatório financeiro por IA |
| GET | /api/relatorio/lojista/{id} | Relatório operacional por IA |
| GET | /api/score/{id}/analise | Análise de score por IA |

Documentação completa: `http://localhost:8080/swagger-ui.html`

---

## 🤖 Funcionalidades com IA (Claude)

- **Sugestão de turnos** — recomenda os melhores turnos
  com base no perfil e histórico do motoboy (últimos 30 dias)
- **Relatório financeiro** — análise mensal personalizada
  em linguagem natural para motoboy e lojista
- **Análise de score** — explica variações no score de reputação
  e sugere plano de melhoria concreto

---

## 📐 Regras de Negócio Implementadas

| RF | Regra |
|----|-------|
| RF01 | Conta bloqueada por 15 min após 5 tentativas de login falhas |
| RF02 | Dashboard com métricas em tempo real |
| RF03 | Lojista exige CNPJ; Motoboy exige CNH no cadastro |
| RF04 | Turno deve ser agendado com mínimo 2h de antecedência |
| RF05 | Motoboy não pode aceitar turno com conflito de horário |
| RF06 | Finalização do turno credita automaticamente na carteira |
| RF07 | Cancelamento com menos de 1h de antecedência penaliza o score |
| RF08 | Sugestão inteligente de turnos via IA |
| RF09 | Relatório financeiro/operacional mensal via IA |

---

## 👥 Autores

- Matheus de Souza Silvério da Silva
- Orientadora: Fernanda Manica

**Instituição:** Centro Universitário UNIFACEAR
**Curso:** Sistemas de Informação
**Ano:** 2026

---

## 📄 Licença

Projeto acadêmico — todos os direitos reservados aos autores.
