# Roteiro de deploy — revisão de outubro (Fases 16 e 17)

Passo a passo para publicar a branch `feat/SCRUM-25-revisao-outubro` depois do
merge: back-end no **Render**, banco no **Neon**, front-end no **Firebase
Hosting**. Cada passo diz o que conferir antes de seguir.

Endereços usados aqui:

| O quê | Endereço |
|---|---|
| Back-end | `https://motoshift.onrender.com` |
| Status | `https://motoshift.onrender.com/api/status` |
| Front-end | `https://motoshift-8b0d2.web.app` (projeto do `Motoshift/.firebaserc`) |

**Ordem:** primeiro o back-end, depois o front. O app novo funciona contra o
back-end antigo (ele trata o `/api/status` que ainda não existe como "servidor
no ar"), mas as regras novas — data até hoje, editar recorrente a partir deste
mês — só valem com o back-end novo.

---

## 1. Render (back-end)

### 1.1 Qual branch o Render publica

No painel do Render, serviço do back-end → **Settings → Build & Deploy →
Branch**.

- Se for a **`main`** (o padrão): o deploy só acontece **depois do merge do
  PR**. Enquanto o PR está aberto, nada do que está aqui está no ar.
- Se quiser testar antes do merge, troque a branch para
  `feat/SCRUM-25-revisao-outubro`, faça o roteiro e **volte para a `main`**
  depois.

> Não consegui conferir isto daqui: não tenho acesso ao painel do Render.

### 1.2 Variáveis de ambiente

Em **Environment**. As três primeiras linhas são as desta rodada; nenhuma é
obrigatória, porque os padrões já são os do Render — crie só se quiser deixar
explícito.

| Variável | Valor | Precisa criar? |
|---|---|---|
| `MOTOSHIFT_FUSO` | `America/Sao_Paulo` | Não — é o padrão. Um nome que não existe **derruba o boot** |
| `TZ` | `America/Sao_Paulo` | Não — o `backend/Dockerfile` já define |
| `MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS` | `1` | Não — é o padrão do perfil `prod`. Mude só se o passo 2.3 mostrar outro número |
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://<host-do-neon>/<banco>?sslmode=require` | **Conferir** |
| `SPRING_DATASOURCE_USERNAME` | usuário do Neon | **Conferir** |
| `SPRING_DATASOURCE_PASSWORD` | senha do Neon | **Conferir** |
| `JWT_SECRET` | 32+ caracteres | **Conferir** — sem ela o boot falha |
| `MOTOSHIFT_CORS_ORIGINS` | `https://motoshift-8b0d2.web.app,https://motoshift-8b0d2.firebaseapp.com` | **Conferir** — sem a origem do Firebase o app web não fala com a API |
| `MOTOSHIFT_FISCAL_CHAVE` | qualquer segredo | **Conferir** — sem ela o boot falha |
| `ANTHROPIC_API_KEY` | chave da Anthropic | **Conferir** |

`SPRING_PROFILES_ACTIVE=prod` já vem do Dockerfile. O `/api/status` mostra o
commit publicado a partir de `RENDER_GIT_COMMIT`, que o Render preenche; se a
`versao` vier `0.0.1-SNAPSHOT`, crie `MOTOSHIFT_VERSAO` com o que quiser ver.

### 1.3 Acompanhar o build

1. Depois do merge (ou de salvar uma variável), o Render abre um deploy em
   **Events**. O build do Docker leva alguns minutos.
2. Em **Logs**, espere a linha `Started MotoshiftApplication`. Antes dela vêm
   as migrações do Flyway — nesta rodada não há migração nova (a última
   continua sendo a V25).
3. Se o boot falhar com `MOTOSHIFT_FUSO inválido`, o valor da variável não é
   um fuso da base IANA: apague-a ou corrija.

---

## 2. Depois do deploy do back-end

### 2.1 A hora do servidor

Abra `https://motoshift.onrender.com/api/status` no navegador. Se o servidor
estiver dormindo, a página demora até uns 3 minutos na primeira vez.

```json
{ "ok": true, "horaServidor": "2026-10-07T19:30:05-03:00", "fuso": "America/Sao_Paulo", "versao": "72cbcf5" }
```

Confira:

- [ ] `horaServidor` é **a hora de Brasília** (a do seu relógio), terminando em
      `-03:00`. Se vier 3 horas à frente ou terminar em `Z`/`+00:00`, o fuso
      não pegou — não siga.
- [ ] `fuso` é `America/Sao_Paulo`.
- [ ] `versao` é o começo do commit que você acabou de publicar.

### 2.2 Reset da massa

Tudo o que já está no Neon foi gravado com o servidor em UTC — três horas
adiantado. Os horários dos turnos antigos ficariam deslocados em relação aos
novos. O reset recria a massa na hora certa.

É o procedimento do README, seção **"Resetar a massa de demonstração"**:

1. Em **Environment**, crie `MOTOSHIFT_SEED_RESET` com um dos valores:
   - `confirmo` — recria só a massa (contas `@teste.com`); contas reais ficam,
     **com os horários antigos delas**;
   - `confirmo-apagar-tudo` — apaga **todos** os dados de negócio e recria a
     massa. É o indicado aqui se não há conta real para preservar. Antes, um
     `pg_dump` pela URL do Neon.
2. Salve e espere o deploy. No log:
   `[massa] reset concluido` (ou `reset TOTAL concluido`).
3. **Remova a variável `MOTOSHIFT_SEED_RESET`** e deixe o Render subir de novo.
   Enquanto ela existir, todo restart apaga tudo outra vez.

- [ ] O log do último boot não tem nenhuma linha `[massa]`.
- [ ] `lojista@teste.com` / `senha123` entra.

### 2.3 O IP do limite de requisições

1. Em **Environment**, crie
   `LOGGING_LEVEL_COM_MOTOSHIFT_SECURITY_LIMITEDEREQUISICOESFILTER` = `DEBUG`
   e espere o deploy.
2. No app (ou no site antigo), faça um **"Esqueci minha senha"** com qualquer
   e-mail. É uma das duas rotas que passam pelo limite por IP.
3. Em **Logs**, procure a linha:

   ```
   limite: cabecalho X-Forwarded-For=[203.0.113.7, 10.210.0.5], proxies confiaveis=1, conexao=10.210.0.5 -> ip escolhido=203.0.113.7
   ```

4. Compare o `ip escolhido` com o seu IP público (o que `https://ifconfig.me`
   mostra).

- [ ] `ip escolhido` é o **seu** IP.
- Se for um endereço interno (`10.x`, `172.16–31.x`), há um proxy a mais na
  lista: aumente `MOTOSHIFT_LIMITE_PROXIES_CONFIAVEIS` em 1 e repita.
- Se o cabeçalho vier com **uma entrada só** (o seu IP), o proxy do Render não
  está acrescentando o próprio IP: tanto 0 quanto 1 escolhem a entrada certa.
- [ ] **Remova a variável do DEBUG** depois de conferir.

> A regra (penúltima entrada no Render) vem do que a revisão de 07/10
> observou. Este passo é o que confirma em produção — não testei contra o
> Render de verdade.

---

## 3. Firebase (front-end)

Precisa do Flutter **3.41.5** e da CLI do Firebase logada (`firebase login`).

```bash
cd Motoshift
```

```bash
flutter build web --release --dart-define=API_URL=https://motoshift.onrender.com/api
```

```bash
firebase deploy --only hosting
```

O `API_URL` pode ir com ou sem `/api` no fim: a partir desta branch o app não
duplica o sufixo. (Antes dela, `…/api` virava `…/api/api` e toda chamada dava
404.)

Este build foi rodado nesta branch em 07/10/2026, com o comando acima: gera
`build/web` com o `index.html` de título "MotoShift" e os arquivos que o
`firebase.json` marca com `no-cache` (`flutter_bootstrap.js`,
`flutter_service_worker.js`, `version.json`, `manifest.json`). O
`firebase deploy` em si não foi executado daqui.

Depois, numa **janela anônima** (sem cache nem sessão antiga), abra
`https://motoshift-8b0d2.web.app`:

- [ ] O título da aba é **MotoShift**.
- [ ] A tela de login **não** tem mais "Sou Lojista / Sou Motoboy".
- [ ] Entrando com `motoboy@teste.com` / `senha123`, o menu tem **Resultado**
      (em Financeiro) e o painel tem o cartão **Resultado do mês**.
- [ ] Se o servidor estava dormindo: a faixa "Acordando o servidor…" aparece
      no login e some sozinha.

O `firebase.json` desta branch manda `Cache-Control: no-cache` para o
`index.html` e os arquivos de versão. Para conferir, nas ferramentas do
navegador (aba Rede), o `index.html` e o `flutter_bootstrap.js` têm de trazer
esse cabeçalho.

---

## 4. Monitor que mantém o servidor acordado

O plano gratuito do Render desliga o serviço depois de 15 minutos sem
requisição. Um monitor gratuito resolve:

1. Crie uma conta em [cron-job.org](https://cron-job.org) ou
   [UptimeRobot](https://uptimerobot.com).
2. Novo monitor / cron job:
   - **URL:** `https://motoshift.onrender.com/api/status`
   - **Método:** `GET` (o `HEAD`, padrão de alguns monitores, também responde
     200)
   - **Intervalo:** a cada **10 minutos**
3. Resposta esperada: 200, com `"ok": true` no corpo.

A rota é pública, não consulta o banco e não entra no limite de requisições.
As 750 horas mensais do plano gratuito cobrem um serviço ligado o mês inteiro.

**No dia da apresentação**, abra o app uns **5 minutos antes** de qualquer
jeito: se o monitor tiver falhado, dá tempo de o servidor acordar.

---

## 5. Teste de fumaça

Depois de tudo, com a massa recém-recriada. Senha de todas as contas:
`senha123`.

**Como lojista** (`claudia@teste.com`):

- [ ] **Publicar um turno para daqui a 2h30.** Tem de **aceitar**. É o teste
      do fuso: com o servidor em UTC, 2h30 daqui a pouco pareciam "meia hora
      atrás", e a regra das 2 h de antecedência recusava.
- [ ] Abrir **Resultado** (menu Financeiro): a faixa diz a situação por
      extenso, e a demonstração não mostra linhas zeradas.
- [ ] **Informar → lançar uma receita ou um custo de `1.500`.** Embaixo do
      campo aparece `= R$ 1.500,00`; depois de salvar, o lançamento aparece na
      lista com R$ 1.500,00 (e não R$ 1,50).
- [ ] Conferir a **DRE do mês**: o resultado mudou em R$ 1.500,00. Excluir o
      lançamento de teste em seguida.

**Como entregador** (`motoboy@teste.com`):

- [ ] O painel mostra o cartão **Resultado do mês**, os valores em dinheiro
      com separador de milhar e centavos, e o score com vírgula.
- [ ] Abrir **Resultado**, **Informar → Combustível, `1.500`**: `= R$ 1.500,00`
      embaixo do campo. Salvar, conferir a DRE do mês e excluir.
- [ ] No seletor de data do formulário, **amanhã não está disponível**.
- [ ] Editar um lançamento que repete todo mês e aparece na lista (a parcela
      de todo dia 5; em "Mês anterior" aparecem todos): ao salvar, o app
      pergunta "A mudança vale a partir de quando?". Escolha **Aplicar a
      partir deste mês** e confira em "Mês anterior" que o valor antigo
      continua lá.
- [ ] O turno publicado pela Cláudia aparece em **Turnos**, com o horário
      certo.

Se algo aqui falhar, o `/api/status` (hora e commit) e o log do Render são os
dois primeiros lugares para olhar.
