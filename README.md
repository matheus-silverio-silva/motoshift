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
| Banco de dados | H2 (desenvolvimento) / MySQL (produção) |
| IA | Claude Sonnet (Anthropic API) |
| Documentação | Springdoc OpenAPI / Swagger UI |
| Versionamento | Git + GitHub |

---

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
```

---

## 🔑 Credenciais de Teste

| Perfil | Email | Senha |
|--------|-------|-------|
| Lojista | lojista@teste.com | senha123 |
| Motoboy | motoboy@teste.com | senha123 |

Os usuários e turnos de teste são criados automaticamente na inicialização.

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
