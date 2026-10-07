# 🏍️ MotoShift

[![CI](https://github.com/matheus-silverio-silva/motoshift/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/matheus-silverio-silva/motoshift/actions/workflows/ci.yml)

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
| Deploy | Render (back-end, Docker) + Firebase Hosting (front-end web) + Neon (PostgreSQL) |
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
├── docs/                     # Requisitos (REQUIREMENTS.md, com a rastreabilidade), guia de defesa e os documentos abaixo
│   ├── DER/                  # Modelo de dados e rastreabilidade das migrações
│   ├── financeiro/           # Ciclo do dinheiro (FLUXO-FINANCEIRO), documentos fiscais simulados (FISCAL) e lucro/prejuízo (RESULTADO)
│   ├── ux/                   # Navegação: mapa, regra seção × sub-página, nomes, pós-turno
│   └── historico/            # Auditorias, revisões e prompts usados, por data
├── RODAR.bat                 # Windows: atualiza da main e sobe backend + app web
├── .githooks/                # commit-msg: carimba a chave do Jira da branch no commit
└── .github/                  # CI (mvn test, flutter analyze, flutter test), modelos de PR e de issue, dependabot
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

### Jeito rápido (Windows)

Dê dois cliques em **`RODAR.bat`**, na raiz. Ele:

1. atualiza o projeto com a `main` do GitHub (se você estiver na `main`, sem
   alterações locais e com internet — senão roda o que já está na máquina);
2. sobe o backend em `http://localhost:8080` (H2 em memória + massa de demonstração);
3. abre o app Flutter no Chrome em `http://localhost:5000`.

Contas de demonstração (senha `senha123`): `lojista@teste.com` e
`motoboy@teste.com`. O `.bat` desliga a trava de distância do check-in
(`MOTOSHIFT_CHECKIN_EXIGIR_PROXIMIDADE=false`) para a demo feita de casa.

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

Swagger UI: `http://localhost:8080/swagger-ui.html` — **só em desenvolvimento**.
No perfil `prod` a documentação fica desligada (`springdoc.api-docs.enabled` e
`springdoc.swagger-ui.enabled` em `false`) e as rotas dela deixam de ser
públicas: sem token, respondem 401.

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

**App de celular em release.** O `AndroidManifest.xml` principal declara
`INTERNET` e as duas permissões de localização que o `geolocator` usa
(`ACCESS_FINE_LOCATION` e `ACCESS_COARSE_LOCATION`); o `Info.plist` do iOS traz
o texto de `NSLocationWhenInUseUsageDescription`. HTTP sem TLS
(`usesCleartextTraffic`) vale **só no build de debug**, que é o que fala com o
backend local em `http://10.0.2.2:8080` — o release precisa de
`--dart-define=API_URL=https://...`:

```bash
flutter build apk --release --dart-define=API_URL=https://motoshift.onrender.com
```

**Servidor acordando.** Ao abrir, o app pergunta `GET /api/status`. Se a
resposta não vem em 3 segundos, a tela de login mostra a faixa "Acordando o
servidor… no plano gratuito isso leva até 3 minutos", o botão vira "Aguardando
o servidor" (desligado) e o app pergunta de novo a cada 5 segundos, por até 4
minutos; quando o servidor responde, a faixa some e o botão volta. Passado o
limite, aparece o erro com "Tentar novamente". Quem tem sessão salva espera na
tela de abertura, em vez de ser mandado de volta ao login. As demais chamadas
continuam desistindo em 20 segundos. Ver
[Manter o servidor acordado](#-manter-o-servidor-acordado).

**Nome, ícone e fontes.** O app se chama **MotoShift** em todas as plataformas
(`android:label`, `CFBundleDisplayName`/`CFBundleName`, `<title>` e
`web/manifest.json`).

- **Ícone.** A fonte é `Motoshift/assets/icon/icon.png` — o monograma "MS" na
  fonte da marca, sobre o gradiente verde-água do tema —, desenhada pelo
  próprio projeto em `tool/gerar_icone_test.dart`. Os ícones de Android
  (inclusive o adaptativo), iOS e web/favicon saem dela pelo
  `flutter_launcher_icons` e estão versionados. Para redesenhar:

  ```bash
  flutter test tool/gerar_icone_test.dart
  ```

  ```bash
  dart run flutter_launcher_icons
  ```

  (o gerador troca uma linha que não deve no `ios/Runner.xcodeproj/project.pbxproj`
  — `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` —; desfaça com
  `git checkout -- ios/Runner.xcodeproj/project.pbxproj` antes de commitar.)
- **Fontes.** Bricolage Grotesque e Plus Jakarta Sans vão **embarcadas** em
  `Motoshift/assets/fonts/` (licença SIL OFL 1.1, nos arquivos `OFL-*.txt` ao
  lado). O `google_fonts` as usa dos assets, e o `main.dart` desliga a busca em
  rede (`GoogleFonts.config.allowRuntimeFetching = false`): o app tem a mesma
  cara sem internet. Estão lá os pesos que o app usa (400 a 800); usar um peso
  novo exige pôr o arquivo dele na pasta e no `pubspec.yaml`.

**Acessibilidade.** Três coisas são verificadas por teste, em `test/a11y/`:

- **Tamanho do alvo de toque** (`alvo_de_toque_test.dart`): 44 px no mínimo em
  tudo o que é clicável.
- **Rótulo e contraste** (`diretrizes_test.dart`): as diretrizes do próprio
  Flutter — `labeledTapTargetGuideline` e `textContrastGuideline` (WCAG 2.1 AA:
  4,5:1 no texto comum, 3:1 no texto grande) — no login, nos dois painéis e no
  detalhe do turno, do lado do entregador e do lojista.
- **O que o leitor de tela diz** (`resumos_test.dart`): gráfico, mapa e
  estrelas são desenho, então cada um leva um `Semantics` com a frase que o
  substitui — "Ganhos dos últimos 7 dias: seg R$ 120, ter R$ 0, ...", "Mapa do
  turno: ponto de partida em ... Raio de entrega de 8 km.", "Nota 4 de 5". As
  frases saem de `lib/utils/resumo_acessivel.dart`.

Para o texto branco dos botões caber na regra, o rótulo passou de 13,5 para
14 px em negrito — o tamanho a partir do qual a diretriz o trata como texto
grande. O verde-água da marca (`AppColors.teal`) dá 4,1:1 contra o branco; onde
ele era cor de texto pequeno entrou `AppColors.tealTexto`, um tom mais fechado
(5,3:1). A diretriz mede só o que está na primeira dobra de cada tela.

### 📍 Testar a localização à mão (Chrome)

O navegador só libera a localização em **HTTPS ou `localhost`**: rode o app
com `flutter run -d chrome` (que abre em `localhost`). Para simular onde a
pessoa está, abra o DevTools (F12) → menu ⋮ → *More tools* → **Sensors** →
*Location* → *Other…* e digite a latitude e a longitude. Os pontos da massa:

| Ponto | Latitude | Longitude | Distância do Água Verde |
|---|---|---|---|
| Hamburgueria da Cláudia — Água Verde | -25.4560 | -49.2820 | — |
| Pizzaria do Fernando — Batel | -25.4420 | -49.2900 | 1,8 km |
| Mercado Andrade — Rebouças | -25.4445 | -49.2610 | 2,5 km |
| Farmácia Ana — Centro Cívico | -25.4160 | -49.2690 | 4,6 km |
| Marco zero (Praça Tiradentes) | -25.4284 | -49.2733 | 3,2 km |

**Entregador** (`ricardo@teste.com`), com a posição no Água Verde:

1. *Turnos* → ligue **Filtrar por distância**. O mapa aparece com um pino por
   turno, e cada pino traz o valor e a distância ("R$ 120 · 1,8 km").
2. Arraste o raio até **2 km**: ficam os turnos do Água Verde e do Batel. Em
   **3 km** entra o Rebouças; em **5 km**, todos. A distância do card ("a 1,8
   km"), a do pino e a do detalhe ("Distância de você") são o mesmo número — o
   que o backend mediu.
3. Sem "perto de mim", o card diz **"entrega até 8 km"**: é a área que o turno
   cobre, não a distância até você. A folha de filtros chama esse número de
   *Área de entrega do turno*.
4. Em *Sensors*, escolha **Location unavailable** e ligue o filtro de novo: a
   faixa amarela diz que não foi possível obter a localização e oferece
   "Tentar novamente". Bloqueie a permissão do site (cadeado na barra de
   endereço → *Localização* → *Bloquear*): a faixa diz que a permissão está
   bloqueada.
5. Com o filtro ligado, pare o backend e mova o raio: aparece **"Não foi
   possível buscar os turnos perto de você."** com "Tentar de novo" — e a lista
   some, em vez de mostrar os turnos sem filtro.
6. Abra o app pelo IP da rede (`http://192.168.x.x:porta`) e ligue o filtro: a
   mensagem diz que a localização só funciona em HTTPS ou `localhost`.

**Lojista** (`claudia@teste.com`):

1. *Publicar turno*: o mapa já abre na loja, com "Ponto da sua loja, marcado em
   Dados pessoais" — o GPS nem é consultado. Toque o mapa: vira "Ponto escolhido
   por você no mapa", e o GPS não o move mais.
2. *Perfil → Dados pessoais → Ponto da loja no mapa*: toque o mapa ou use
   **"Estou na loja: usar minha localização"** (pega o ponto do *Sensors*).
   **Desmarcar** e salvar deixa a loja sem ponto.
3. Sem ponto de loja, *Publicar turno* parte do GPS ("Posição atual do
   aparelho"). Com a localização bloqueada, parte do centro da cidade — e
   **Publicar** pede **"Confirme o ponto de partida"** antes de gastar o saldo:
   "Marcar no mapa" volta ao formulário, "Usar este ponto" aceita.

---

## 🔀 Fluxo de trabalho

Cada mudança nasce de um card do Jira (`SCRUM-NN`) e chega à `main` por pull
request.

1. **Branch** no formato `tipo/SCRUM-NN-descricao`, a partir da `main`
   atualizada — por exemplo `feat/SCRUM-32-recuperar-senha` ou
   `fix/SCRUM-27-aceite-concorrente`. O tipo é o mesmo do commit (`feat`,
   `fix`, `docs`, `test`, `chore`, `ci`, `perf`, `refactor`).
2. **Hook de commit**, uma vez por clone:

   ```bash
   git config core.hooksPath .githooks
   ```

   O `commit-msg` lê a chave do nome da branch e a carimba na mensagem —
   `fix(turno): ... (SCRUM-27)` —, que é o que faz o Jira ligar o commit ao
   card. Ele só carimba a chave **da branch**: um commit que fecha outro card
   leva a chave dele escrita à mão.
3. **Commit** em português, sem acento, no padrão do histórico:
   `tipo(escopo): o que muda`.
4. **Pull request** com a chave no título — `feat(auth): trocar a senha e
   recuperar por codigo (SCRUM-32)` — e o modelo de
   [`.github/pull_request_template.md`](.github/pull_request_template.md)
   preenchido: card, o que mudou, como testar e o checklist de testes, goldens
   e documentação.
5. **CI** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)): roda em
   todo pull request e em todo push na `main` — `mvn test` no Ubuntu,
   `flutter analyze` e `flutter test` no Windows. Um commit novo cancela a
   execução do anterior na mesma branch. Branch sem PR não roda: abrir o PR,
   mesmo como rascunho, é o que liga o CI.

**Builds reprodutíveis.** O Flutter é **3.41.5** em todo lugar: no CI, no
`Motoshift/Dockerfile` (`ghcr.io/cirruslabs/flutter:3.41.5`) e na gravação dos
goldens. O `Motoshift/pubspec.lock` é versionado, e tanto o CI quanto o Docker
instalam com `flutter pub get --enforce-lockfile` — as versões do lock, ou o
build falha. Mudou uma dependência no `pubspec.yaml`? Rode `flutter pub get`
com o Flutter 3.41.5 e commite o lock junto. Subir o Flutter é mudar os três
lugares de uma vez e regravar os goldens.

**Dependências.** O [`dependabot`](.github/dependabot.yml) abre PRs uma vez por
mês para `maven` (`/backend`), `pub` (`/Motoshift`) e `github-actions`. São os
únicos PRs sem chave do Jira no título.

**Issues.** Há dois modelos em `.github/ISSUE_TEMPLATE/`: **bug** (o que
acontece, como reproduzir, onde) e **melhoria** (o problema, a proposta, os
critérios de aceite e o que fica de fora).

---

## 🚀 Deploy (Render + Firebase + Neon)

| Peça | Onde | Como |
|------|------|------|
| Banco | **Neon** (PostgreSQL) | As migrações Flyway rodam no boot do back-end |
| Back-end | **Render** (plano gratuito) | [`backend/Dockerfile`](backend/Dockerfile), perfil `prod` |
| Front-end web | **Firebase Hosting** | `flutter build web` + `firebase deploy`, com [`Motoshift/firebase.json`](Motoshift/firebase.json) |

O passo a passo de um deploy, com o que conferir depois, está em
[`docs/historico/2026-10-05-revisao/DEPLOY.md`](docs/historico/2026-10-05-revisao/DEPLOY.md).

### Front-end (Flutter Web)

Os arquivos estáticos saem de `flutter build web` e vão para o Firebase
Hosting, que devolve o `index.html` em qualquer rota (fallback de SPA):

```bash
cd Motoshift
flutter build web --release --dart-define=API_URL=https://motoshift.onrender.com
firebase deploy --only hosting
```

| Variável de build | Exemplo | Observação |
|-------------------|---------|------------|
| `API_URL` | `https://motoshift.onrender.com` | URL base do back-end. O app anexa o `/api`; se a URL já vier com `/api` (ou com barra) no fim, ele não duplica |

**Cache.** Sem cabeçalho, o navegador podia servir a versão antiga do app por
até 1 hora depois de um deploy. O `firebase.json` manda
`Cache-Control: no-cache` para os arquivos que dizem ao navegador qual é a
versão atual — `/` e `index.html`, `flutter_bootstrap.js`,
`flutter_service_worker.js`, `version.json` e `manifest.json`. Eles são
revalidados a cada visita; o resto continua com o cache padrão.

O [`Motoshift/Dockerfile`](Motoshift/Dockerfile) (build com a imagem do Flutter
**3.41.5** + **nginx**) continua no repositório para quem preferir servir o
front por container, como era no Railway.

### Back-end (Spring Boot)

O Render constrói a imagem de [`backend/Dockerfile`](backend/Dockerfile) e a
sobe com o perfil `prod` (PostgreSQL). Variáveis principais:

| Variável | Obrigatória | Descrição |
|----------|-------------|-----------|
| `SPRING_PROFILES_ACTIVE` | sim | Defina como `prod` |
| `JWT_SECRET` | **sim** | Segredo de assinatura dos tokens, mínimo 32 caracteres. Sem ele o boot falha de propósito — melhor não subir do que assinar token com a chave de exemplo do repositório. Trocar o valor invalida os tokens emitidos, ou seja, desloga todo mundo |
| `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` | sim | Conexão com o PostgreSQL (Neon). URL em formato JDBC, com usuário e senha fora dela: `jdbc:postgresql://<host>/<db>?sslmode=require`. Para rodar o perfil `prod` na máquina, copie [`backend/.env.example`](backend/.env.example) para `backend/.env` (fora do git) |
| `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` | não | Alternativa antiga, usada só quando as `SPRING_DATASOURCE_*` não estão definidas (o plugin Postgres do Railway as injeta) |
| `ANTHROPIC_API_KEY` | sim | Chave da API Anthropic para as funcionalidades de IA |
| `MOTOSHIFT_CORS_ORIGINS` | **sim** | Origens liberadas no CORS, separadas por vírgula — as do front no Firebase (ex.: `https://<projeto>.web.app,https://<projeto>.firebaseapp.com`). Sem default: o antigo `*` liberava qualquer origem quando a variável era esquecida. Agora o boot falha, a hospedagem recusa o deploy e a versão anterior continua no ar |
| `MOTOSHIFT_FUSO` | não | O fuso do sistema; padrão `America/Sao_Paulo`. O `main` o aplica antes de o Spring subir. Um nome que não existe derruba o boot. Ver [Fuso horário](#-fuso-horário) |
| `TZ` | não | Fuso do container. O `backend/Dockerfile` já define `America/Sao_Paulo` (e passa `-Duser.timezone` à JVM); só precisa ser criada à mão em hospedagem que não use esse Dockerfile |
| `MOTOSHIFT_FISCAL_CHAVE` | **sim** | Chave do HMAC que autentica os comprovantes (recarga, Pix, movimentação). Sem ela o boot falha: o código de autenticação viraria um hash que qualquer um refaz. Trocar a chave muda o código de todos os comprovantes já emitidos |
| `MOTOSHIFT_FISCAL_RETER_NA_FONTE` | não | `true` faz a liquidação reter ISS e IRRF do entregador, como lançamentos próprios no extrato; padrão `false`, com os tributos apenas informativos na nota. Ver [`docs/financeiro/FISCAL.md`](docs/financeiro/FISCAL.md) |
| `JWT_EXPIRACAO_HORAS` | não | Validade do token; padrão 168 (7 dias) |
| `ANTHROPIC_MODEL` | não | Modelo da Anthropic usado pela IA (propriedade `anthropic.model`); padrão `claude-sonnet-4-20250514`. Trocar de modelo deixou de pedir commit e deploy de código |
| `MOTOSHIFT_LIMITE_HABILITADO` | não | `false` desliga o limite de requisições (10/h por usuário nas sugestões da IA; 20 a cada 10 min por IP no cadastro e no "esqueci minha senha"). Padrão `true`. Útil na **apresentação com a turma inteira atrás do mesmo Wi-Fi**: todos saem pelo mesmo IP, e o 21º cadastro em 10 minutos levaria 429 |
| `MOTOSHIFT_LIMITE_CABECALHO_IP` | não | De qual cabeçalho o limite lê o IP do cliente. Padrão `X-Forwarded-For` em produção (vazio em dev, onde não há proxy em que confiar). Outro cabeçalho (`True-Client-IP`, `X-Real-IP`) é lido inteiro, sem tratar como lista — ver "Limite de requisições" |
| `MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS` | não | Quantas entradas do **fim** do `X-Forwarded-For` são dos proxies da hospedagem. Padrão **1** em produção (Render: a última entrada é o proxy, a penúltima é o cliente) e 0 em dev. Use 0 onde a última entrada já é o cliente (era o caso do Railway) |
| `LOGGING_LEVEL_COM_MOTOSHIFT_SECURITY_LIMITEDEREQUISICOESFILTER` | não | `DEBUG` faz o filtro do limite registrar, a cada cadastro ou "esqueci minha senha", o cabeçalho cru e o IP escolhido — para conferir em produção que o IP é o seu. Tire depois de conferir |
| `MOTOSHIFT_VERSAO` | não | O que o `/api/status` responde em `versao`. No Render não precisa: o commit publicado vem de `RENDER_GIT_COMMIT`, que a plataforma preenche |
| `MOTOSHIFT_CHECKIN_EXIGIR_PROXIMIDADE` | não | `false` desliga a trava de distância do check-in (o "Cheguei" passa a valer de qualquer lugar). É para a **apresentação feita de casa**, longe de qualquer loja da massa; a janela de horário e a regra de papel continuam valendo. Padrão `true` |
| `MOTOSHIFT_CHECKIN_RAIO_METROS` | não | A que distância do ponto do turno o check-in ainda vale; padrão 500 |
| `MOTOSHIFT_GORJETA_MAXIMO` | não | Teto de uma gorjeta, em reais; padrão 50 |
| `MOTOSHIFT_FINALIZACAO_AUTOMATICA_HORAS` | não | Propriedade `motoshift.finalizacao.automatica-horas`: quantas horas depois do **fim** do turno o job o finaliza sozinho, se ninguém finalizou. Paga quem fez check-in; sem nenhum check-in, devolve a reserva e o turno vai para `expirado`. Mínimo 1; padrão 12 |
| `MOTOSHIFT_JOBS_HABILITADOS` | não | `false` desliga os jobs agendados (vencimento, lembrete, cobrança e finalização automática) nesta instância — para as réplicas extras, deixando uma só com os jobs. Padrão `true` |
| `PORT` | não | Porta do servidor (injetada automaticamente pela hospedagem) |

### 🕒 Fuso horário

O MotoShift tem **um fuso só**, o de Curitiba (`America/Sao_Paulo`).

O app manda as datas do turno como hora local, sem fuso
(`2026-10-07T19:00:00`), as colunas são `timestamp` sem fuso e as entidades
usam `LocalDateTime`: nada é convertido no caminho. A única coisa que precisa
estar certa é o "agora" do servidor — e ele era o do container, que no Render
roda em **UTC**, 3 horas à frente de Brasília. Toda regra que compara uma data
do turno com o agora saía deslocada: as 2 h de antecedência para publicar
viravam 5 h, a expiração e a finalização automática agiam 3 h antes, o lembrete
de 1 h chegava 4 h antes, e na DRE (regime de caixa) o que acontecia depois das
21h caía no dia seguinte — às vezes no mês seguinte.

A correção é pôr o servidor no fuso de quem usa: o
`MotoshiftApplication.main` aplica o fuso (`MOTOSHIFT_FUSO`) antes de o Spring
subir, e o `backend/Dockerfile` já faz a JVM nascer nele (`TZ` e
`-Duser.timezone`). Não há conversão para UTC, o app não passou a mandar fuso
e o `hibernate.jdbc.time_zone` **não** é configurado: o que a JVM grava é o que
volta. A suíte roda no mesmo fuso (`argLine` do surefire no `pom.xml`), para o
CI — que roda em UTC — testar o que a produção executa. O
`GET /api/status` devolve `horaServidor` com o deslocamento (`-03:00`): é por
ali que se confere depois do deploy.

**Por que um fuso só.** Loja e entregador estão na mesma cidade — o check-in
exige estar a 500 m do ponto —, então todo mundo lê o mesmo relógio de parede,
e `LocalDateTime` é exatamente isso. O Brasil não tem horário de verão desde
2019, então não há hora que se repete nem hora que não existe.

**Para atender outro estado** há dois caminhos. Se o sistema inteiro mudasse de
região, basta `MOTOSHIFT_FUSO=America/Manaus`. Para atender **dois fusos ao
mesmo tempo**, o modelo muda: as datas passam a ser instantes (`timestamptz` no
banco, `Instant`/`OffsetDateTime` no código, com uma migração convertendo as
colunas a partir de `America/Sao_Paulo`), o app passa a mandar o deslocamento,
cada loja ganha o seu fuso, e os cortes de "dia" e "mês" da DRE, do extrato e
da agenda passam a ser calculados no fuso de quem consulta.

> Os dados gravados **antes** desta correção foram gravados em UTC. Depois do
> deploy, o [reset da massa](#-resetar-a-massa-de-demonstração) recria tudo na
> hora certa.

### ⏰ Manter o servidor acordado

No plano gratuito, o Render **desliga o serviço depois de 15 minutos sem
requisição**, e a primeira chamada seguinte espera o boot inteiro — medimos
cerca de 3 minutos. O app avisa e espera (ver "Servidor acordando", acima), mas
o melhor é o servidor não dormir:

1. Crie um monitor gratuito — [cron-job.org](https://cron-job.org) ou
   [UptimeRobot](https://uptimerobot.com).
2. Endereço: **`https://motoshift.onrender.com/api/status`**, método `GET`
   (o `HEAD` também responde 200), **a cada 10 minutos**.
3. Resposta esperada: 200 com `"ok": true`.

A rota é pública, não consulta o banco e fica fora do limite de requisições,
então o monitor não gasta nada além de manter a JVM de pé. As **750 horas por
mês** do plano gratuito cobrem um serviço ligado o mês inteiro (31 dias são
744 horas) — desde que seja o único serviço gratuito da conta.

> **Antes de apresentar:** abra o app uns **5 minutos antes**. Se o monitor
> tiver falhado e o servidor estiver dormindo, é tempo de sobra para ele
> acordar antes de alguém olhar para a tela.

---

## 🔑 Credenciais de Teste

Todos os usuários abaixo usam a senha **`senha123`**. Em desenvolvimento são
criados automaticamente na primeira inicialização, desde que o banco esteja
vazio. Em produção, a massa é recriada pelo reset descrito em
[Resetar a massa de demonstração](#-resetar-a-massa-de-demonstração). A massa
inteira mora em `backend/.../config/MassaDemonstracao.java`, e toda data dela é
calculada a partir do momento em que roda.

### 🏪 Lojistas

| Email | Nome | Estabelecimento | Cidade | Selos | Favoritos | Gorjeta |
|-------|------|-----------------|--------|-------|-----------|---------|
| `claudia@teste.com` | Cláudia Oliveira | Hamburgueria da Cláudia | Curitiba/PR | Paga gorjeta · Contrata toda semana | Ricardo, Lucas | R$ 10 a cada três semanas |
| `fernando@teste.com` | Fernando Costa | Pizzaria do Fernando | Curitiba/PR | — | Lucas | duas vezes, R$ 5 |
| `ana@teste.com` | Ana Souza | Farmácia Ana | Curitiba/PR | — | — | nunca |
| `lojista@teste.com` | Maria Andrade | Mercado Andrade | Curitiba/PR | Nota acima de 4,8 · Contrata toda semana | Carlos | nunca |

Lojista não tem score (a reputação é do entregador); a média de avaliação de
cada loja é a das notas que os entregadores deram a ela.

As quatro lojas e os quatro entregadores são de **Curitiba** — inclusive
`lojista@teste.com` e `motoboy@teste.com`, que eram de São Paulo enquanto a
massa inteira acontecia em Curitiba (o "perto de mim" delas partia a 340 km de
tudo). Cada loja tem o ponto marcado no mapa, no próprio endereço, e todo
turno dela parte desse ponto — ver [Testar a localização à mão](#-testar-a-localização-à-mão-chrome).

### 🏍️ Motoboys

| Email | Nome | Veículo | Score | Por quê | Pontualidade | Meta do mês | Selos |
|-------|------|---------|-------|---------|--------------|-------------|-------|
| `ricardo@teste.com` | Ricardo Souza | Honda CG 160 Titan | 5.0 | desistiu de uma vaga com folga — sem penalidade | 100% (chega sempre antes) | R$ 2.000 | Pontual |
| `lucas@teste.com` | Lucas Mendes | Yamaha Factor 150 | 5.0 | nenhuma desistência | ~73% (atrasa às vezes) | — (o painel convida) | 20 turnos concluídos · 30 dias sem cancelar |
| `thiago@teste.com` | Thiago Alves | Honda Biz 125 | 4.5 | desistiu de uma vaga a menos de 1h do início (−0,5) | ~30% (atrasa com frequência) | — | nenhum |
| `motoboy@teste.com` | Carlos Mendes | Honda PCX 150 | 5.0 | nenhuma desistência | ~92% | R$ 1.500 | 20 turnos concluídos · 30 dias sem cancelar · Nota acima de 4,8 · Pontual |

Pontualidade, selos e o "Loja que já te chamou" saem do histórico da massa,
calculados como no app — os valores acima são os de uma massa recém-criada e
se movem um pouco com a data (a janela é de 90 dias).

Nenhum desses números é gravado à mão: o score é o que a regra da RF07 produz
(5,0 inicial, −0,5 por desistência em cima da hora) a partir do que aconteceu na massa,
e a média de avaliação é recalculada pelo `AvaliacaoService` a cada avaliação.

### 📖 O que a massa conta

Cerca de cinco meses de história, gravados pelos mesmos serviços que o app usa
(recarga e saque pelo `CobrancaService`, aceite/finalização/desistência/cancelamento pelo
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
- **Chegada e saída** em todo turno pago, pelo `CheckinService` com a hora do
  turno: o Ricardo chega sempre antes, o Carlos quase sempre no horário, o
  Lucas se atrasa de vez em quando e o Thiago com frequência — daí as
  pontualidades diferentes.
- **Gorjetas** da Cláudia (a cada três semanas) e duas do Fernando, pelo
  `GorjetaService`; aparecem no extrato dos dois lados e nas notificações.
- **Favoritos:** a Cláudia favoritou Ricardo e Lucas; a Maria, o Carlos; o
  Fernando, o Lucas. Os turnos abertos dessas lojas aparecem com o selo
  "Loja que já te chamou" para eles, e a publicação deles avisou os
  favoritos ("A Hamburgueria da Cláudia publicou um turno para amanhã, 18h").
- **Maria e Carlos**, a dupla de toda semana, dão nota 5 um ao outro — de onde
  saem os dois selos "Nota acima de 4,8".
- **O presente:** sete turnos abertos — seis à espera de entregador e um que
  **reabriu** —, um **em andamento com check-in** (o Ricardo chegou 4 min
  antes; a Cláudia recebeu "Ricardo chegou às…"), três aceitos por começar —
  dois amanhã e um da Pizzaria do Fernando com o Lucas daqui a menos de 1 hora,
  que já gerou o **lembrete** para os dois — e as duas **desistências** que
  explicam os scores. O Ricardo desistiu de uma vaga do Fernando com três dias
  de folga: não custou nada, e o turno voltou para os disponíveis. O Thiago
  desistiu de uma vaga da Cláudia a meia hora do início: −0,5 de score para
  ele. Sem entregador em cima da hora, a Cláudia **cancelou** esse turno — a
  reserva voltou inteira e ninguém foi penalizado por isso.
- **Notificações** só dos tipos que o código gera hoje, com os textos de hoje;
  as de mais de três dias já aparecem como lidas.
- **Resultado (lucro e prejuízo):** o Carlos e a Cláudia informam o que a
  plataforma não vê, pelo `LancamentoGerencialService`. Ele: o combustível de
  cada turno (R$ 7,50, 42 km), o DAS do MEI de cada mês e três contas
  recorrentes — celular, seguro e parcela da moto. Ela: a taxa de entrega que
  cobrou dos clientes em cada noite. Nada disso passa pelo ledger.

#### 💰 Lucro e prejuízo: onde ver cada caso

A massa é datada a partir do dia em que é criada, então os meses são relativos
a hoje. Em **Resultado** (menu Financeiro):

| Conta | Mês **passado** | Mês **retrasado** |
|---|---|---|
| `motoboy@teste.com` (Carlos, entregador) | **Lucro** — um turno por semana paga o DAS, o combustível e as contas fixas | **Prejuízo** — a troca da relação e do pneu (R$ 420) custou mais do que o mês rendeu, embora ele tenha trabalhado o mesmo |
| `claudia@teste.com` (Cláudia, lojista) | **Lucro** — as taxas cobradas (R$ 208 por entregador-noite) cobrem os entregadores | **Prejuízo** — promoção de frete grátis: só R$ 48 de taxa por noite, com os entregadores custando o mesmo |

Como chegar a cada um: o **mês passado** é o atalho **"Mês anterior"**; o
**mês retrasado** não tem atalho — toque na barra dele no gráfico **"Mês a
mês"**. A tela abre no mês atual, que é parcial (mostra só o que já aconteceu
até hoje).

Numa massa criada em outubro de 2026, por exemplo: o Carlos fecha setembro com
lucro de R$ 106,95 e agosto com prejuízo de R$ 220,55; a Cláudia, setembro com
lucro de R$ 431,00 e agosto com prejuízo de R$ 338,00. Os centavos mudam com o
dia em que a massa é criada (um mês pode ter quatro ou cinco turnos); o sinal,
não — o `MassaDemonstracaoTest` confere os quatro casos. As outras contas não
informam nada: a DRE delas mostra só o extrato, com o aviso de que o resultado
ignora custos não informados. As contas e a tabela completa estão em
[`docs/financeiro/RESULTADO.md`](docs/financeiro/RESULTADO.md), seção 9.

> 💡 Para explorar o fluxo completo, recomendamos **`claudia@teste.com`**
> (lojista com o turno de três vagas, pendências, gorjetas, favoritos e um turno
> em andamento com check-in) e **`ricardo@teste.com`** (entregador com
> histórico, saques, notas, meta do mês e um turno em andamento). Para o
> lembrete de 1 hora, **`lucas@teste.com`** ou **`fernando@teste.com`**. Para
> o fluxo de nota fiscal dos dois lados, use
> **`lojista@teste.com`** e **`motoboy@teste.com`**. Para **lucro e
> prejuízo**, **`motoboy@teste.com`** (Carlos) e **`claudia@teste.com`** —
> ver a tabela acima.

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

#### Passo a passo no Render (serviço do back-end) — `confirmo-apagar-tudo`

Use quando o banco de produção tem dados velhos ou de teste que não são da
massa e a demonstração precisa começar do zero.

1. **Antes de tudo, um backup.** Este modo apaga contas reais. Faça um
   `pg_dump` pela URL de conexão do Neon (ou crie uma *branch* do banco no
   painel do Neon, que guarda o estado atual).
2. **Faça o deploy da versão que tem este modo.** Em *Settings → Build &
   Deploy*, confira a branch que o serviço publica (a `main`, depois do merge)
   e espere o deploy terminar. Uma versão anterior não conhece o valor
   `confirmo-apagar-tudo` e simplesmente o ignora.
3. **Defina a variável.** Em *Environment*, crie `MOTOSHIFT_SEED_RESET` com o
   valor exato `confirmo-apagar-tudo` e salve. O Render sobe um deploy novo
   com ela.
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
6. **Remova a variável `MOTOSHIFT_SEED_RESET`** em *Environment*. Este passo não
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
| GET | /api/status | **Sem token.** `{ok, horaServidor, fuso, versao}` — o servidor está no ar, que horas são para ele (com o deslocamento do fuso) e qual commit está publicado. Não consulta o banco e fica fora do limite de requisições: é o que o app chama ao abrir e o que o monitor chama para o servidor não dormir |
| POST | /api/auth/registro | Cadastro de usuário. O e-mail é gravado sem espaço nas pontas e em minúsculas; `MARIA@x.com` com `maria@x.com` já cadastrado responde 409. No máximo 20 a cada 10 minutos por IP |
| POST | /api/auth/login | Autenticação. O e-mail não diferencia maiúsculas: `Claudia@Teste.com` entra na conta de `claudia@teste.com` |
| POST | /api/auth/trocar-senha | **Com token.** Troca a senha de quem está logado: `{senhaAtual, senhaNova}`, senha nova com 6 caracteres ou mais. Senha atual errada responde 400 (não 401) e **não conta como tentativa de login** |
| POST | /api/auth/esqueci-senha | `{email}`. Gera um código de 6 dígitos válido por 15 minutos e o envia ao e-mail da conta (**envio simulado** — ver abaixo). Responde **202 sempre**, exista ou não a conta. No máximo 20 a cada 10 minutos por IP |
| POST | /api/auth/redefinir-senha | `{email, codigo, senhaNova}`. Troca a senha e destrava o login bloqueado. Cada código aceita **5 tentativas**; código errado, vencido ou esgotado respondem o mesmo 400 |
| GET | /api/turnos/disponiveis | Listar turnos disponíveis (para o entregador, `lojaQueJaTeChamou` marca os turnos das lojas que o favoritaram) |
| POST | /api/turnos | Criar novo turno (Lojista) |
| PUT | /api/turnos/{id}/aceitar | Aceitar turno (Motoboy) |
| PUT | /api/turnos/{id}/finalizar | Finalizar turno — só depois do início e com pelo menos um check-in (409 fora disso). Paga quem fez check-in; quem aceitou e não chegou fica `faltou` e a parte dele volta ao lojista |
| PUT | /api/turnos/{id}/cancelar | Cancelar turno — **só o lojista que publicou** (o entregador leva 403). O turno inteiro cai, a reserva volta e nenhum entregador é penalizado. Recusado depois do check-in: turno que começou se finaliza |
| PUT | /api/turnos/{id}/desistir | Desistir da vaga — **só o entregador inscrito**, e só da vaga dele: a inscrição é cancelada, a vaga reabre (turno lotado que não começou volta a `aberto`), a reserva continua bloqueada e a loja é avisada. A menos de 1h do início, −0,5 no score de quem desistiu. Recusado (409) depois do check-in |
| PUT | /api/turnos/{id}/checkin | "Cheguei" — só o entregador aceito; de 30 min antes do início até o fim; a até 500 m do ponto (com a trava ligada). O primeiro leva o turno a `em_andamento` e avisa o lojista |
| PUT | /api/turnos/{id}/checkout | "Encerrar turno" — a saída, só depois do check-in. Não finaliza nem paga |
| POST | /api/turnos/{id}/gorjetas | Gorjeta do lojista a um entregador do turno finalizado (até R$ 50, com saldo disponível, uma por entregador — repetir a mesma não cobra de novo) |
| GET | /api/turnos/{id}/gorjetas | Gorjetas do turno: o lojista vê todas, o entregador só a dele |
| PUT | /api/usuarios/{id} | Atualiza o próprio perfil; `metaMensal` (só entregador, R$ 1 a R$ 100.000, `null` tira) |
| GET | /api/favoritos | Meus entregadores favoritos (só lojista) |
| PUT | /api/favoritos/{motoboyId} | Favoritar entregador (só lojista, só entregador; favoritar de novo devolve o que existe) |
| DELETE | /api/favoritos/{motoboyId} | Desfavoritar (sem favorito, não faz nada) |
| GET | /api/dashboard/motoboy/{id} | Métricas do Motoboy |
| GET | /api/dashboard/lojista/{id} | Métricas do Lojista |
| GET | /api/carteira/{id} | Saldo, ganhos e a primeira página do extrato |
| GET | /api/carteira/extrato | Extrato filtrado e paginado (período, tipo, natureza, turno, contraparte, valor, busca) |
| GET | /api/carteira/extrato/exportar | O mesmo extrato sem paginação: `formato=csv` (planilha, padrão) ou `formato=json` (a base do PDF que o app gera). O app entrega a planilha como **arquivo** `.csv` em UTF-8 com BOM (download no navegador, folha de compartilhar no celular) — o BOM é o que faz o Excel em português acertar os acentos |
| GET | /api/carteira/resumo | O resumo do período para o papel de quem pergunta — entregador: recebido, retido, sacado, disponível e a receber; lojista: recarregado, pago, devolvido, disponível e comprometido. Os campos do outro papel não vêm |
| GET | /api/carteira/fluxo | Série de fluxo de caixa por dia, semana ou mês (sem reserva e liberação, que são o dinheiro trocando de bolso) |
| POST | /api/carteira/recargas | Abre uma cobrança Pix simulada (não credita) |
| POST | /api/carteira/recargas/{id}/confirmar | Simula o webhook e credita o saldo (idempotente) |
| POST | /api/carteira/saques | Saque via Pix — estorna sozinho se o gateway recusar |
| GET | /api/carteira/cobrancas | Recargas e saques do usuário |
| GET | /api/sugestoes/turnos/{id} | Sugestões por IA — no máximo 10 por hora por usuário (429 com `Retry-After` acima disso) |
| GET | /api/relatorio/motoboy/{id} | Relatório financeiro por IA — os números incluem o resultado do período, a situação, a margem líquida e o ponto de equilíbrio, lidos da DRE |
| GET | /api/relatorio/lojista/{id} | Relatório operacional por IA — com o resultado da operação de entrega e o custo sobre a receita, lidos da DRE |
| GET | /api/score/{id}/analise | Análise de score por IA |
| GET | /api/financeiro/dre | **DRE do período** (RF13): linhas, resultado, situação (`lucro`, `prejuizo` ou `equilibrio`), indicadores e a comparação com o período anterior de mesmo tamanho. `?dataInicio&dataFim`; sem datas, o mês corrente. O papel vem do token |
| GET | /api/financeiro/dre/mensal | Doze meses do ano (`?ano`): receita, custos e resultado de cada um — o gráfico da tela de resultado |
| GET | /api/financeiro/categorias | As categorias de lançamento do papel do token, com rótulo e grupo da DRE |
| GET | /api/financeiro/lancamentos | Custos e receitas informados que contam no período (`?dataInicio&dataFim`, paginação opcional com `X-Total-Count`) |
| POST | /api/financeiro/lancamentos | Informar um custo ou uma receita. **Não é transação**: não move saldo, não entra no extrato. Categoria de outro papel e turno de que o usuário não participou são recusados (400) |
| PUT | /api/financeiro/lancamentos/{id} | Editar um lançamento — o de outro usuário responde 404 |
| DELETE | /api/financeiro/lancamentos/{id} | Excluir um lançamento — o de outro usuário responde 404 |
| POST | /api/carteira/transacoes/{id}/documento | Gera o documento do lançamento — NFS-e, recibo ou comprovante (idempotente) |
| GET | /api/carteira/transacoes/{id}/documento | O documento já gerado desse lançamento |
| GET | /api/notas-fiscais | Notas fiscais do usuário, com filtros (papel, situação, competência, contraparte) e paginação |
| GET | /api/notas-fiscais/resumo | Informe anual simulado — por contraparte e por mês |
| GET | /api/notas-fiscais/resumo/exportar | O mesmo informe em CSV |
| GET | /api/notas-fiscais/pendentes | Pagamentos de turno ainda sem nota — "a emitir" para o lojista, "aguardando emissão" para o entregador |
| POST | /api/notas-fiscais | Emitir NFS-e do turno (só o lojista; o entregador leva 403) |
| PUT | /api/notas-fiscais/{id}/cancelar | Cancelar a nota (só o lojista) |

Documentação completa: `http://localhost:8080/swagger-ui.html` (em
desenvolvimento; desligada em produção).

### 🚦 Limite de requisições

| Rota | Limite | Chave |
|------|--------|-------|
| `/api/sugestoes/**` | 10 por hora | o usuário logado |
| `POST /api/auth/registro` | 20 a cada 10 minutos | o IP |
| `POST /api/auth/esqueci-senha` | 20 a cada 10 minutos | o IP |

Acima do limite a resposta é **429**, no mesmo formato de erro do resto da API
(`{codigo: "muitas_tentativas", mensagem, campo}`), com o cabeçalho
**`Retry-After`** dizendo em quantos segundos a próxima requisição cabe. A
janela é **deslizante** (10 por hora quer dizer 10 em qualquer intervalo de 60
minutos, não 10 até a virada da hora) e cada rota pública tem a própria conta.
O login não entra: ele já tem o bloqueio por conta do RF01. O `/api/status`
também não: o monitor o chama o dia inteiro.

O estado é **em memória** (`LimiteDeRequisicoesFilter` + `JanelaDeslizante`,
sem dependência nova): some no deploy e é por instância — com duas réplicas, o
limite efetivo dobra. Basta para o que protege, que é o custo da IA e o abuso
de cadastro e de e-mail.

**De onde vem o IP.** Atrás do proxy da hospedagem, o endereço da conexão é o
do *proxy* — o mesmo para todo mundo. Um limite por ele seria um limite global:
vinte cadastros a cada dez minutos para o aplicativo inteiro, e uma pessoa só
trancaria a porta para todas. Por isso, em produção, o IP sai do cabeçalho
**`X-Forwarded-For`**. Cada proxy acrescenta ao **fim** dessa lista o endereço
de quem falou com ele; o que vem antes é o que o cliente quis mandar. Vale a
entrada **N contando da direita**, com `N = 1 + proxies confiáveis`
(`MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS`):

| Hospedagem | O cabeçalho chega como | Proxies confiáveis | Entrada escolhida |
|------------|------------------------|--------------------|-------------------|
| **Render** (padrão de produção) | `cliente, proxy` | 1 | a penúltima |
| Onde a última já é o cliente (era o Railway) | `cliente` | 0 | a última |

No Render o proxy acrescenta também o **próprio** IP. Lendo a última entrada —
como se fazia para o Railway —, a chave do limite era o proxy, e o 21º cadastro
do **sistema inteiro** em 10 minutos levava 429. Com a lista mais curta do que
o pedido vale a primeira entrada, nunca a do proxy; forjar o que vem antes do
IP real não cria um limite novo. Em desenvolvimento o cabeçalho é
**ignorado**: sem proxy na frente, quem o escreve é o próprio cliente.

Se `MOTOSHIFT_LIMITE_CABECALHO_IP` apontar para outro cabeçalho
(`True-Client-IP`, `X-Real-IP`), ele é lido **inteiro**, sem tratar como lista.
Quando o cabeçalho configurado não vem, o filtro tenta o `X-Real-IP` antes de
cair no endereço da conexão.

**Como conferir em produção.** No painel do Render, em *Environment*, crie

```
LOGGING_LEVEL_COM_MOTOSHIFT_SECURITY_LIMITEDEREQUISICOESFILTER=DEBUG
```

e, depois do deploy, faça um "Esqueci minha senha" no app. O log traz uma linha
como

```
limite: cabecalho X-Forwarded-For=[203.0.113.7, 10.210.0.5], proxies confiaveis=1, conexao=10.210.0.5 -> ip escolhido=203.0.113.7
```

O `ip escolhido` tem de ser o **seu** IP público (o que um site como
`https://ifconfig.me` mostra). Se for um endereço interno (`10.x`), há um proxy
a mais: aumente `MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS`. Remova a variável do
log depois de conferir.

> O nome do logger é em minúsculas de propósito: o Spring Boot passa a variável
> `LOGGING_LEVEL_...` para minúsculas, e com o nome da classe ela nunca
> alcançaria o filtro.

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

Os requisitos completos — funcionais, não funcionais e a rastreabilidade até os
cards do Jira, as classes e os testes — estão em
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md). A numeração é a que o código
cita: **RF09 são as notificações**, e o relatório por IA, que esta tabela
chamava de RF09, é o **RF14**.

| RF | Regra |
|----|-------|
| RF01 | Conta bloqueada por 15 min após 5 tentativas de login falhas. O e-mail é o identificador da conta e **não diferencia maiúsculas** (normalizado ao gravar e ao procurar; índice único em `lower(email)`, V23). No app, Enter envia o login e o cadastro, e os campos têm as dicas de autofill |
| RF02 | Dashboard com métricas em tempo real |
| RF03 | Lojista exige CNPJ; Motoboy exige CNH no cadastro |
| RF04 | Turno deve ser agendado com mínimo 2h de antecedência, e **publicar reserva** `valor × vagas` do saldo do lojista — sem lastro, 422 dizendo quanto falta |
| RF05 | Motoboy não pode aceitar turno com conflito de horário, e **a última vaga não é de dois**: o aceite trava a linha do turno (`SELECT ... FOR UPDATE`), então quem chega junto na mesma vaga recebe 409 em vez de entrar também |
| RF06 | Finalização do turno **transfere** o valor reservado: sai do bloqueado do lojista, entra no disponível do entregador, na mesma transação. **Só vale com o turno começado e com check-in, e só paga quem fez check-in** — quem aceitou e não chegou fica `faltou`, sem pagamento e sem penalidade de score. A sobra (vagas vazias e faltas) volta |
| RF07 | Sair do turno tem uma regra para cada lado. **Cancelar** é só do lojista dono: derruba o turno, devolve a reserva inteira (sem multa) e não penaliza ninguém. **Desistir da vaga** é só do entregador inscrito: cancela a inscrição dele, reabre a vaga e, a menos de 1h do início, tira 0,5 do score **dele** — o turno e os colegas de vaga seguem |
| RF12 | O dinheiro entra por recarga (Pix simulado) e sai por saque; a plataforma não cria nem destrói saldo — ver [`docs/financeiro/FLUXO-FINANCEIRO.md`](docs/financeiro/FLUXO-FINANCEIRO.md) |
| RF13 | O usuário acompanha o **resultado financeiro (lucro ou prejuízo)** do período numa DRE simplificada, em regime de caixa, combinando o extrato com custos e receitas que ele informa. O entregador lança combustível, manutenção, DAS do MEI e contas fixas; o lojista, a taxa de entrega que cobrou. O que é informado à mão **não é transação**: não move saldo nem entra no extrato. Indicadores: margem líquida, lucro por hora e por turno, custo por km e ponto de equilíbrio em turnos (entregador); custo sobre a receita e resultado por turno (lojista) — ver [`docs/financeiro/RESULTADO.md`](docs/financeiro/RESULTADO.md) |
| RF19 | **Senha.** Quem está logado troca a senha no Perfil informando a atual. Quem esqueceu recebe um código de 6 dígitos (15 min, 5 tentativas, guardado só como hash BCrypt) e cria uma senha nova em três passos — e-mail, código, senha. A resposta nunca diz se o e-mail tem conta |
| RF08 | Sugestão inteligente de turnos via IA |
| RF09 | **Notificações** dentro do app para o que muda no que é do usuário (aceite, chegada, pagamento, falta, desistência, cancelamento, vencimento, lembrete, nota, gorjeta), com o sino mostrando as não lidas e levando à tela do que aconteceu |
| RF14 | **Relatórios.** Resumo do período, fluxo de caixa e quebra por tipo, com exportação em planilha e PDF; e o relatório financeiro/operacional apurado pelo extrato com análise por IA — se a IA não responde, os números vêm sem a análise |
| RF10 | Turno publicado guarda o ponto de partida (lat/lng), que alimenta o filtro por distância e o mapa das duas pontas |
| RF17 | **Avaliação mútua.** Depois do turno finalizado, lojista e entregador se avaliam com nota de 1 a 5 e comentário; em turno de várias vagas, o lojista avalia cada entregador. Quem faltou ou saiu do turno não avalia nem é avaliado |
| RF15 | **Check-in.** O entregador registra chegada e saída (V16). A pontualidade — % de chegadas até 10 min após o início, nos últimos 90 dias — aparece no perfil e no perfil público; sem check-in, "Sem histórico" |
| RF04 · publicar de novo | Turno finalizado, cancelado ou expirado do lojista abre o formulário de publicar já preenchido (mesmo lugar, raio, valor, vagas e duração), com a data no mesmo dia da semana da semana seguinte. Só no app: publica pelo mesmo `POST /api/turnos`, com a mesma confirmação de custo, antecedência e saldo |
| RF10 · abrir rota | No detalhe do turno, o entregador abre a rota até o ponto no Google Maps (no celular, também no Waze, se instalado) |
| RF21 · calendário | Baixa um `.ics` (RFC 5545, fuso America/Sao_Paulo, alarme 1 h antes) — o entregador nos turnos em que está, a loja nos que publicou |
| RF16 · finalização automática | Turno aceito ou em andamento que terminou e ninguém finalizou é primeiro **cobrado** por notificação; passadas 12 h do fim (`motoshift.finalizacao.automatica-horas`), um job o finaliza pelo mesmo caminho do botão: paga quem fez check-in, marca `faltou` quem não chegou e devolve a sobra. Sem nenhum check-in, a reserva volta inteira e o turno vai para `expirado`. As duas partes são avisadas uma vez só. Antes o dinheiro podia ficar reservado para sempre |
| RF02 e RF09 · telas que se atualizam | O sino busca a contagem de não lidas a cada 45 s enquanto há sessão (para em segundo plano, retoma ao voltar, cancela no logout). Os dois painéis, Turnos do entregador, Turnos do lojista, Agenda e o detalhe do turno têm **puxar para atualizar** no celular e o botão **Atualizar** na topbar do desktop — ver [`docs/ux/NAVEGACAO.md`](docs/ux/NAVEGACAO.md), seção 6.1 |
| RF16 · lembrete | Um job de 5 em 5 min lembra entregador e loja do turno aceito que começa em até 1 h (`turno_lembrete`), uma vez só por pessoa e turno |
| RF20 · meta do mês | O entregador define no perfil quanto quer ganhar no mês; o painel mostra "R$ 1.340 de R$ 2.000 (67%)", somando pagamentos recebidos e gorjetas. Sem meta, um convite — nunca uma barra zerada (V19) |
| RF20 · selos de reputação | Calculados do histórico, sem tabela, no perfil público e no próprio, com o critério ao tocar. Entregador: 20 turnos concluídos (limite ajustado à massa), 30 dias sem cancelar, nota acima de 4,8 (10+ avaliações), pontual (90%+, 10+ check-ins). Loja: paga gorjeta (3+ em 90 dias), nota acima de 4,8, contrata toda semana (4 semanas seguidas) |
| RF18 · favoritos | O lojista marca entregadores com o coração (perfil público, avaliação, turno finalizado) e os vê no próprio perfil. Ao publicar, os favoritos recebem "A Hamburgueria da Cláudia publicou um turno para amanhã, 18h"; na lista de disponíveis do entregador, os turnos dessas lojas levam o selo "Loja que já te chamou". O entregador não vê quem o favoritou (V18) |
| RF18 · gorjeta | Na avaliação do entregador, o lojista pode dar R$ 5, 10, 20 ou outro valor (até R$ 50) do saldo disponível. Transferência no ledger (`bonus_enviado` → `bonus`), com comprovante, não NFS-e |
| RF11 | Turno finalizado gera NFS-e — entregador é o prestador, lojista é o tomador, e **só o lojista emite e cancela**; o entregador vê, baixa e imprime. Todo lançamento do extrato gera o documento correspondente (nota, recibo ou comprovante), sempre simulado — ver [`docs/financeiro/FISCAL.md`](docs/financeiro/FISCAL.md) |

---

## 🔐 Senha: trocar e recuperar

**Trocar** (Perfil → Alterar senha) é de quem está logado e lembra a senha:
`POST /api/auth/trocar-senha` exige o token e a senha atual. A senha atual
errada volta como 400, no próprio campo, e não entra no contador de tentativas
de login — errar um campo do formulário não tranca a conta de quem já está
dentro.

**Recuperar** ("Esqueci minha senha", no login) é de quem não lembra:

1. o app pede o código (`POST /api/auth/esqueci-senha`). O backend responde
   202 exista ou não a conta, e gasta o mesmo tempo nos dois casos;
2. a pessoa digita os 6 dígitos que recebeu;
3. escolhe a senha nova, e o app manda e-mail + código + senha
   (`POST /api/auth/redefinir-senha`).

O código vale por **15 minutos** e por **5 tentativas**; um código novo para a
mesma conta só sai depois de **1 minuto**, e aposenta o anterior. O banco
guarda apenas o **hash BCrypt** do código (tabela `codigos_recuperacao_senha`,
migração V24): quem lê o banco não consegue redefinir a senha de ninguém.
Redefinir também destrava a conta bloqueada por tentativas de login.

### ✉️ O e-mail é simulado

Não há servidor de e-mail neste projeto. O envio passa pela interface
`EnvioDeEmail`, e a implementação que existe — `EnvioDeEmailSimulado` —
**escreve a mensagem no log do servidor**, no mesmo espírito do
`GatewayPagamentoSimulado`: o que se demonstra é que o código sai por um canal
que não é a resposta da API, não a integração com um provedor.

Para testar, peça o código no app e procure no log (o console do backend em
dev; os logs do serviço no Render) a linha:

```
[email-simulado] para: claudia@teste.com | assunto: MotoShift — código para redefinir a senha
Olá, Cláudia.

Seu código para redefinir a senha do MotoShift é: 483920
```

A consequência é honesta e fica registrada: **quem lê o log do servidor
consegue redefinir a senha de uma conta com pedido aberto** — do mesmo jeito
que conseguiria quem lesse a caixa de e-mail dela. Um provedor de verdade
(SMTP, SES, Resend) entra implementando `EnvioDeEmail`, e nada mais muda. A
tela do passo 2 avisa que o envio é simulado, para ninguém ficar esperando um
e-mail que não vem.

Dois limites conhecidos: trocar a senha **não derruba as sessões abertas** (o
JWT não tem revogação e vale até vencer), e a massa de demonstração é recriada
com `senha123` a cada reset.

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

**Os documentos seguem modelos oficiais da legislação brasileira** — sempre
simulados, com a marca **DOCUMENTO SIMULADO — SEM VALOR FISCAL**:

| Documento | Modelo seguido |
|---|---|
| NFS-e | **DANFSe v2.0**, o documento auxiliar da NFS-e do padrão nacional (Nota Técnica SE/CGNFS-e nº 008/2026): chave de acesso de 50 dígitos, DPS, QR Code e os quadros oficiais — prestador, tomador, serviço (LC 116/2003 item 26.01, NBS 1.0702.00.00), ISSQN, tributação federal, IBS/CBS do ano de teste de 2026 (LC 214/2025) e totais. Cabe numa página A4 |
| Recibo de recarga | Quitação do **Código Civil, art. 320**: valor e espécie da dívida, quem pagou, tempo e lugar, com o valor por extenso |
| Comprovante de Pix | Campos mínimos do **Regulamento Pix** (Resolução BCB nº 1/2020): pagador, recebedor, instituições, data e hora e identificador fim a fim |

O detalhe de cada modelo, e o que é simulado em cada um, está em
[`docs/financeiro/FISCAL.md`](docs/financeiro/FISCAL.md), seção 7.

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
