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
│   │   ├── routes/           # Nomes de rota e NavConfig (menu e regra de navegação)
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
│   ├── DER/                  # Modelo de dados e rastreabilidade das migrações
│   ├── financeiro/           # Ciclo do dinheiro (FLUXO-FINANCEIRO) e os documentos fiscais simulados (FISCAL)
│   └── ux/                   # Navegação: mapa, regra seção × sub-página, nomes, pós-turno
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
- **Nenhuma tela monta o próprio menu.** O menu, a barra inferior e o destaque
  vêm de `lib/routes/nav_config.dart`; a tela informa só em que seção está.
  Item de menu troca a pilha inteira, detalhe empilha — a regra, o mapa e a
  tabela de nomes estão em [`docs/ux/NAVEGACAO.md`](docs/ux/NAVEGACAO.md), e
  `test/navegacao/` falha quando alguma tela foge dela.


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
| `MOTOSHIFT_CORS_ORIGINS` | **sim** | Origens liberadas no CORS, separadas por vírgula (ex.: `https://motoshift.up.railway.app`). Sem default: o antigo `*` liberava qualquer origem quando a variável era esquecida. Agora o boot falha, o healthcheck do Railway recusa o deploy e a versão anterior continua no ar |
| `MOTOSHIFT_FISCAL_CHAVE` | **sim** | Chave do HMAC que autentica os comprovantes (recarga, Pix, movimentação). Sem ela o boot falha: o código de autenticação viraria um hash que qualquer um refaz. Trocar a chave muda o código de todos os comprovantes já emitidos |
| `MOTOSHIFT_FISCAL_RETER_NA_FONTE` | não | `true` faz a liquidação reter ISS e IRRF do entregador, como lançamentos próprios no extrato; padrão `false`, com os tributos apenas informativos na nota. Ver [`docs/financeiro/FISCAL.md`](docs/financeiro/FISCAL.md) |
| `JWT_EXPIRACAO_HORAS` | não | Validade do token; padrão 168 (7 dias) |
| `PORT` | não | Porta do servidor (injetada automaticamente pelo Railway) |

---

## 🔑 Credenciais de Teste

Todos os usuários abaixo usam a senha **`senha123`**. Em desenvolvimento são
criados automaticamente na primeira inicialização, desde que o banco esteja
vazio. Em produção, a massa é recriada pelo reset descrito em
[Resetar a massa de demonstração](#-resetar-a-massa-de-demonstração). A massa
inteira mora em `backend/.../config/MassaDemonstracao.java`, e toda data dela é
calculada a partir do momento em que roda.

### 🏪 Lojistas

| Email | Nome | Estabelecimento | Cidade |
|-------|------|-----------------|--------|
| `claudia@teste.com` | Cláudia Oliveira | Hamburgueria da Cláudia | Curitiba/PR |
| `fernando@teste.com` | Fernando Costa | Pizzaria do Fernando | Curitiba/PR |
| `ana@teste.com` | Ana Souza | Farmácia Ana | Curitiba/PR |
| `lojista@teste.com` | Maria Andrade | Mercado Andrade | São Paulo/SP |

Lojista não tem score (a reputação é do entregador); a média de avaliação de
cada loja é a das notas que os entregadores deram a ela.

### 🏍️ Motoboys

| Email | Nome | Veículo | Score | Por quê |
|-------|------|---------|-------|---------|
| `ricardo@teste.com` | Ricardo Souza | Honda CG 160 Titan | 5.0 | cancelou um turno com folga — sem penalidade |
| `lucas@teste.com` | Lucas Mendes | Yamaha Factor 150 | 5.0 | nenhum cancelamento |
| `thiago@teste.com` | Thiago Alves | Honda Biz 125 | 4.5 | cancelou um turno a menos de 1h do início (−0,5) |
| `motoboy@teste.com` | Carlos Mendes | Honda PCX 150 | 5.0 | nenhum cancelamento |

Nenhum desses números é gravado à mão: o score é o que a regra da RF07 produz
(5,0 inicial, −0,5 por cancelamento tardio) a partir do que aconteceu na massa,
e a média de avaliação é recalculada pelo `AvaliacaoService` a cada avaliação.

### 📖 O que a massa conta

Cerca de cinco meses de história, gravados pelos mesmos serviços que o app usa
(recarga e saque pelo `CobrancaService`, aceite/finalização/cancelamento pelo
`TurnoService`, avaliação pelo `AvaliacaoService`, nota pelo
`NotaFiscalService`):

- **Todo mês** as lojas recarregam a carteira pelo Pix simulado e os
  entregadores sacam parte do que receberam.
- **Toda semana** há turnos pagos na finalização — cada um com as duas
  avaliações (notas de 3 a 5, comentários com as tags do app) e a NFS-e
  emitida pelo lojista no dia seguinte.
- Um **turno de três vagas** da Cláudia com Ricardo, Lucas e Thiago: três
  pagamentos, três notas. E turnos de duas vagas com um entregador só, em que a
  sobra da reserva volta à loja.
- Uma **nota cancelada** pelo Fernando (o pagamento continua no extrato).
- **Pendências da última semana:** três pagamentos ainda sem nota ("a emitir"
  para Maria, Ana e Cláudia; "aguardando emissão" para Carlos, Ricardo e
  Lucas) e avaliações por fazer.
- Um turno da Ana que **expirou** sem entregador (vencido pelo próprio job).
- **O presente:** seis turnos abertos, um em andamento (Cláudia + Ricardo),
  dois confirmados para amanhã e os dois cancelamentos que explicam os scores.
- **Notificações** só dos tipos que o código gera hoje, com os textos de hoje;
  as de mais de três dias já aparecem como lidas.

> 💡 Para explorar o fluxo completo, recomendamos **`claudia@teste.com`**
> (lojista com o turno de três vagas, pendências e um turno em andamento) e
> **`ricardo@teste.com`** (entregador com histórico, saques, notas e um turno
> em andamento). Para o fluxo de nota fiscal dos dois lados, use
> **`lojista@teste.com`** e **`motoboy@teste.com`**.

### 🔄 Resetar a massa de demonstração

Com o tempo a massa envelhece: turnos "abertos" com início no passado, extrato
parado, notificações antigas. Há dois resets, os dois pela variável de
ambiente `MOTOSHIFT_SEED_RESET` no boot, e os dois numa transação só — se algo
falhar, nada é apagado e o app sobe normalmente. Nenhum mexe em schema,
migrações ou no `flyway_schema_history`.

| Valor exato | O que apaga | Contas reais |
|-------------|-------------|--------------|
| `confirmo` | só a massa: contas `@teste.com` e o que pertence a elas (o que uma conta real fez *dentro* da massa, como aceitar um turno da Cláudia, sai junto) | ficam |
| `confirmo-apagar-tudo` | **todos** os dados de negócio (notas, avaliações, extrato, cobranças, inscrições, notificações, turnos, carteiras e usuários), com `DELETE` na ordem das chaves estrangeiras — nunca `DROP`/`TRUNCATE` | **são apagadas** |

Qualquer outro valor — `CONFIRMO`, ` confirmo`, `confirmo-apagar`,
`apagar-tudo`, a variável vazia ou ausente — não faz nada.

#### Passo a passo no Railway (serviço **Back-End**) — `confirmo-apagar-tudo`

Use quando o banco de produção tem dados velhos ou de teste que não são da
massa e a demonstração precisa começar do zero.

1. **Antes de tudo, um backup.** Este modo apaga contas reais. No serviço do
   PostgreSQL, faça um backup (aba *Backups*) ou um `pg_dump` pela URL pública.
2. **Faça o deploy da versão que tem este modo.** Em *Settings → Source*,
   aponte o serviço para a branch com esta versão (ou para a `main`, depois do
   merge) e espere o deploy terminar. Uma versão anterior não conhece o valor
   `confirmo-apagar-tudo` e simplesmente o ignora.
3. **Defina a variável.** Em *Variables*, crie `MOTOSHIFT_SEED_RESET` com o
   valor exato `confirmo-apagar-tudo` e aplique (*Deploy* nas mudanças
   pendentes). O Railway sobe um deploy novo com ela.
4. **Espere o boot** — até o log mostrar `Started MotoshiftApplication`.
5. **Confira o log do deploy.** Devem aparecer, nesta ordem:
   - `[massa] MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo — apagando TODOS os dados de negocio ...`
   - `[massa] reset TOTAL concluido — todos os dados de negocio`, seguido de
     uma tabela com as colunas `antes`, `apagados` e `depois` por tabela. Na
     linha `usuarios`, `depois` tem de ser **8**.
   - `[massa] REMOVA a variavel MOTOSHIFT_SEED_RESET do servico agora.`

   Se aparecer `[massa] reset falhou e foi desfeito por inteiro; nada foi
   apagado`, o banco está exatamente como antes; a causa vem logo abaixo, no
   stack trace.
6. **Remova a variável `MOTOSHIFT_SEED_RESET`** em *Variables*. Este passo não
   é opcional: enquanto ela existir, **todo** deploy e **todo** restart apagam
   tudo de novo — inclusive o que for feito durante uma apresentação.
7. **Faça o redeploy** sem a variável e confirme que o log do boot não tem
   nenhuma linha `[massa]`. Entre no app com `lojista@teste.com` /
   `senha123` para conferir.

Para o reset que preserva contas reais, o procedimento é o mesmo com o valor
`confirmo` (sem o passo do backup, se preferir); o log mostra
`[massa] reset concluido`, com as linhas apagadas e criadas por tabela.

Em desenvolvimento não é preciso: o H2 é recriado a cada boot e a massa nasce
nova. Para testar localmente, suba com `MOTOSHIFT_SEED_RESET=confirmo` ou
`MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo`. Os dois modos têm teste de
integração sobre PostgreSQL com Flyway (`ResetDaMassaPostgresTest`), inclusive
para "valor errado não faz nada".

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
| GET | /api/carteira/{id} | Saldo, ganhos e a primeira página do extrato |
| GET | /api/carteira/extrato | Extrato filtrado e paginado (período, tipo, natureza, turno, contraparte, valor, busca) |
| GET | /api/carteira/extrato/exportar | O mesmo extrato sem paginação: `formato=csv` (planilha, padrão) ou `formato=json` (a base do PDF que o app gera) |
| GET | /api/carteira/resumo | O resumo do período para o papel de quem pergunta — entregador: recebido, retido, sacado, disponível e a receber; lojista: recarregado, pago, devolvido, disponível e comprometido. Os campos do outro papel não vêm |
| GET | /api/carteira/fluxo | Série de fluxo de caixa por dia, semana ou mês (sem reserva e liberação, que são o dinheiro trocando de bolso) |
| POST | /api/carteira/recargas | Abre uma cobrança Pix simulada (não credita) |
| POST | /api/carteira/recargas/{id}/confirmar | Simula o webhook e credita o saldo (idempotente) |
| POST | /api/carteira/saques | Saque via Pix — estorna sozinho se o gateway recusar |
| GET | /api/carteira/cobrancas | Recargas e saques do usuário |
| GET | /api/sugestoes/turnos/{id} | Sugestões por IA |
| GET | /api/relatorio/motoboy/{id} | Relatório financeiro por IA |
| GET | /api/relatorio/lojista/{id} | Relatório operacional por IA |
| GET | /api/score/{id}/analise | Análise de score por IA |
| POST | /api/carteira/transacoes/{id}/documento | Gera o documento do lançamento — NFS-e, recibo ou comprovante (idempotente) |
| GET | /api/carteira/transacoes/{id}/documento | O documento já gerado desse lançamento |
| GET | /api/notas-fiscais | Notas fiscais do usuário, com filtros (papel, situação, competência, contraparte) e paginação |
| GET | /api/notas-fiscais/resumo | Informe anual simulado — por contraparte e por mês |
| GET | /api/notas-fiscais/resumo/exportar | O mesmo informe em CSV |
| GET | /api/notas-fiscais/pendentes | Pagamentos de turno ainda sem nota — "a emitir" para o lojista, "aguardando emissão" para o entregador |
| POST | /api/notas-fiscais | Emitir NFS-e do turno (só o lojista; o entregador leva 403) |
| PUT | /api/notas-fiscais/{id}/cancelar | Cancelar a nota (só o lojista) |

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
| RF04 | Turno deve ser agendado com mínimo 2h de antecedência, e **publicar reserva** `valor × vagas` do saldo do lojista — sem lastro, 422 dizendo quanto falta |
| RF05 | Motoboy não pode aceitar turno com conflito de horário |
| RF06 | Finalização do turno **transfere** o valor reservado: sai do bloqueado do lojista, entra no disponível do entregador, na mesma transação. A sobra das vagas vazias volta |
| RF07 | Cancelamento com menos de 1h de antecedência penaliza o score. A reserva volta inteira ao lojista, sem multa financeira |
| RF12 | O dinheiro entra por recarga (Pix simulado) e sai por saque; a plataforma não cria nem destrói saldo — ver [`docs/financeiro/FLUXO-FINANCEIRO.md`](docs/financeiro/FLUXO-FINANCEIRO.md) |
| RF08 | Sugestão inteligente de turnos via IA |
| RF09 | Relatório financeiro/operacional mensal via IA |
| RF10 | Turno publicado guarda o ponto de partida (lat/lng), que alimenta o filtro por distância e o mapa das duas pontas |
| RF11 | Turno finalizado gera NFS-e — entregador é o prestador, lojista é o tomador, e **só o lojista emite e cancela**; o entregador vê, baixa e imprime. Todo lançamento do extrato gera o documento correspondente (nota, recibo ou comprovante), sempre simulado — ver [`docs/financeiro/FISCAL.md`](docs/financeiro/FISCAL.md) |

---

## 🧾 Documentos fiscais (NFS-e, recibos e comprovantes)

**Cada lançamento concluído do extrato tem um documento**, do entregador e do
lojista, com um botão na linha e no detalhe — "Gerar documento" para o que é
de quem olha gerar, "Ver nota fiscal" para a NFS-e que o lojista já emitiu:

| Lançamento | Documento |
|---|---|
| `pagamento_recebido` / `pagamento_enviado` | **NFS-e** — a mesma nota para os dois lados |
| `recarga` | Recibo de recarga |
| `saque` (Pix concluído) | Comprovante de Pix |
| `reserva`, `liberacao_reserva`, `estorno`, retenções | Comprovante de movimentação |

**Reserva e liberação não são serviço prestado**: são o lojista movendo o
próprio dinheiro entre os dois bolsos da carteira. Geram comprovante, nunca
nota — emitir NFS-e nesse caso documentaria um serviço inexistente. NFS-e
existe para uma coisa só: o pagamento de um **turno concluído**.

A nota é emitida a partir do **pagamento**, não do turno, e guarda o
`transacao_id`: é o que impede a nota e o extrato de contarem histórias
diferentes. O documento é um só e sempre na mesma direção — o entregador
presta, o lojista toma — e **quem emite e cancela é o lojista**. No mundo real
a NFS-e sai do prestador (o entregador MEI); aqui a plataforma a emite por
conta dele, a pedido do tomador, e a nota aparece na lista dos dois. O
entregador vê, baixa o PDF e imprime; enquanto a loja não emite, o pagamento
dele mostra "Aguardando emissão pelo lojista", sem botão, e ele é avisado
quando a nota sai e quando é cancelada. Pedir a emissão ou o cancelamento pelo
lado do entregador leva 403. Um turno com várias vagas gera **uma nota por
entregador**, e a emissão é idempotente: pedir de novo devolve a que já existe.

Só as partes do lançamento veem o documento (terceiro leva 403), CPF e CNPJ
saem mascarados, e **cancelar a nota não estorna dinheiro** — o serviço foi
prestado e o pagamento está no extrato.

### Exportação: planilha ou PDF

Extrato, relatórios e informe anual têm um botão **Exportar** com duas opções:
**Planilha (Excel/CSV)**, que é o CSV de sempre, e **PDF**, gerado no próprio
app com os pacotes `pdf` e `printing` e a identidade visual do documento
fiscal (`lib/services/identidade_pdf.dart`). O PDF traz cabeçalho com nome,
papel, período e filtros aplicados, os mesmos números da tela e a tabela de
lançamentos — e segue o papel: o do entregador não tem coluna de saldo
bloqueado, o do lojista não tem "a receber". O informe anual, que imita um
documento fiscal, sai com a marca **DOCUMENTO SIMULADO — SEM VALOR FISCAL** em
faixa e em marca d'água. Para montar o PDF com o filtro inteiro, o app pede o
mesmo recorte do CSV em JSON (`/api/carteira/extrato/exportar?formato=json`),
numa chamada só, em vez de baixar página por página.

### Tributos e retenção

| Tributo | Alíquota padrão | Propriedade |
|---------|-----------------|-------------|
| ISS | 5% | `motoshift.fiscal.iss-aliquota` |
| IRRF | 1,5% | `motoshift.fiscal.irrf-aliquota` |

Com `motoshift.fiscal.reter-na-fonte=false` (padrão), os tributos são
informativos (Lei 12.741/2012) e o líquido da nota é o que o extrato creditou.
Com `true`, a liquidação gera dois lançamentos `retencao_*` na mesma operação e
o líquido da nota é o crédito menos as retenções. As duas políticas são
testadas.

> ⚠️ **Escopo: tudo aqui é SIMULAÇÃO.** Não há transmissão à prefeitura ou à
> Receita, RPS, nem certificado digital, e as alíquotas são de exemplo. Todo
> documento leva, visível — em tela e como marca d'água no PDF —, a marca
> **DOCUMENTO SIMULADO — SEM VALOR FISCAL**. A fronteira com a "prefeitura"
> está isolada em `EmissorDeNotas`: uma emissão real trocaria o
> `EmissorSimulado` por um cliente ABRASF sem mexer no modelo de dados. O que
> faltaria, em detalhe, está em
> [`docs/financeiro/FISCAL.md`](docs/financeiro/FISCAL.md).

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
