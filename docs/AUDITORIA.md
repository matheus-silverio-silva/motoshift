# Auditoria do MotoShift — Fase 1 (somente leitura)

Gerado em 2026-08-19. **Nenhum arquivo do projeto foi alterado** para produzir este
relatório; o único arquivo criado é este.

## Como ler os níveis de confiança

| Nível | Significa |
|---|---|
| **certeza** | Verificado mecanicamente e sem caminho de uso plausível. Seguro remover. |
| **provável** | Forte indício de código morto, mas depende de intenção de produto. |
| **suspeito** | Parece órfão, mas há mecanismo (reflexão, anotação, serialização) que a análise estática não enxerga. **Não remover sem verificação manual.** |

## Escopo: três branches divergentes

O repositório tem hoje três linhas de código diferentes. Vários achados existem em
uma e não na outra, então **cada item indica a branch**.

| Branch | HEAD | Conteúdo exclusivo |
|---|---|---|
| `main` | `d4984cb` | Base publicada |
| `feat/scrum-19-20-vencimento-notificacoes` | `6e330d5` | Expiração, notificações, scheduler, eventos |
| `feat/layout-responsivo-desktop` | `a0e6228` | Correções de bug, baseline de goldens estável |

Onde o achado vale para as três, está marcado como **(todas)**.

---

# 1.1 Código morto — Backend (Java/Spring)

## 1.1.1 Imports não utilizados

Varredura em todos os `.java` comparando cada import com o corpo do arquivo.

| Arquivo | Linha | Import | Confiança |
|---|---|---|---|
| `backend/.../controller/AuthController.java` | 6 | `com.motoshift.dto.UsuarioResponse` | **certeza** |

**Um único import morto em 30 arquivos.** O backend está limpo nesse aspecto.

## 1.1.2 Métodos e campos privados sem referência

**Nenhum encontrado.** Todos os membros `private` dos serviços e controllers têm ao
menos uma chamada dentro do próprio arquivo.

## 1.1.3 Classes sem referência estática — todas falso positivo

Quinze classes não são referenciadas por nenhum outro `.java`. **Todas** são
instanciadas por component scan ou anotação, ou seja, a ausência de referência é
esperada e correta:

| Classe | Mecanismo |
|---|---|
| `MotoshiftApplication` | `@SpringBootApplication` |
| `DataInitializer` | `@Component` + `CommandLineRunner` |
| `OpenApiConfig`, `WebConfig`, `SchedulingConfig` | `@Configuration` |
| `AgendaController`, `AuthController`, `AvaliacaoController`, `DashboardController`, `NotificacaoController`, `RelatorioController`, `ScoreController`, `TurnoController`, `UsuarioController` | `@RestController` |
| `TurnoScheduler` | `@Component` + `@Scheduled` |

Confiança: **suspeito** por regra — mas verifiquei uma a uma e **nenhuma é código
morto**. Não remover.

O mesmo vale para os DTOs (`UsuarioResponse`, `CarteiraResponse`,
`TransacaoResponse`, `NotificacaoResponse`, `RegistroRequest`) e para as entidades
JPA: são alcançados por serialização Jackson e por reflexão do Hibernate.

## 1.1.4 Endpoints REST que o Flutter nunca chama

Cruzei os **45 mapeamentos** dos 11 controllers com todos os caminhos usados na
camada HTTP do app.

**Resultado: nenhum endpoint órfão.** Todo mapeamento declarado tem ao menos uma
referência no Flutter.

### O problema está no sentido inverso

| Achado | Confiança |
|---|---|
| `ApiService.listarTransacoes()` chama `GET /api/transacoes?motoboyId=…&limit=…` — **não existe nenhum `TransacaoController`**. A chamada retorna 404. | **certeza** |

Hoje isso não quebra nada porque `listarTransacoes` também não é chamado por
nenhuma tela (ver 1.2.2) — é uma mina terrestre: a primeira tela que usar esse
método recebe 404. As transações chegam à UI dentro de `CarteiraResponse.transacoes`,
pelo endpoint `/api/carteira/{id}`.

## 1.1.5 Blocos comentados, `System.out.println`, logs de debug

**Nenhuma ocorrência** de `System.out.println`, `System.err`, `printStackTrace` ou
bloco de código comentado em `backend/src` — nas duas branches. O logging usa SLF4J
com níveis apropriados.

## 1.1.6 TODO / FIXME

**Nenhum** em todo o backend, nas duas branches.

## 1.1.7 `mvn dependency:analyze`

```
[WARNING] Unused declared dependencies found:
   spring-boot-starter-web            spring-boot-starter-data-jpa
   spring-boot-starter-validation     spring-boot-starter-webflux
   spring-boot-starter-actuator       spring-boot-starter-test
   springdoc-openapi-starter-webmvc-ui
   com.h2database:h2 (runtime)        org.postgresql:postgresql (runtime)
```

**Todas as nove são falso positivo — não remova nenhuma.** Duas razões:

1. **Starters são POMs agregadores sem classes próprias.** O plugin procura
   referências a classes do artefato; um starter não tem nenhuma. As classes reais
   vêm das transitivas, que aparecem na lista oposta ("Used undeclared":
   `spring-web`, `spring-webmvc`, `spring-context`, `spring-data-jpa`,
   `spring-tx`, `spring-webflux`…). Remover o starter quebraria o build.
2. **Drivers JDBC (`h2`, `postgresql`) são `runtime`** e carregados por nome de
   classe — nunca haverá referência em tempo de compilação.

Confiança de todas: **suspeito / não remover**. Este relatório roda o comando
porque foi pedido, mas a saída dele não é acionável neste projeto.

---

# 1.2 Código morto — Frontend (Flutter/Dart)

## 1.2.1 Saída das ferramentas

```
$ dart fix --dry-run
Computing fixes in motoshift (dry run)...
Nothing to fix!

$ flutter analyze
Analyzing Motoshift...
No issues found! (ran in 2.0s)
```

Ambas limpas nas três branches.

## 1.2.2 Arquivos `.dart` que ninguém importa

| Arquivo | O que é | Confiança |
|---|---|---|
| `lib/views/relatorio/relatorio_screen.dart` | Tela de relatório IA (RF09) | **provável** |
| `lib/views/score/score_analise_screen.dart` | Tela de análise de score IA | **provável** |
| `lib/views/perfil_publico/perfil_publico_screen.dart` | Perfil público de usuário | **provável** |
| `lib/data/repositories/auth_repository_impl.dart` | Implementação Clean Arch de auth | **provável** |
| `lib/widgets/kinetic_app_bar.dart` | AppBar de um design anterior | **certeza** |
| `lib/widgets/kinetic_bottom_nav.dart` | Bottom nav de um design anterior | **certeza** |

### O achado mais relevante desta seção

As três primeiras telas **não estão registradas em `AppRoutes` nem em `app.dart`**.
São inalcançáveis pelo app. Isso significa que **duas funcionalidades de IA
implementadas de ponta a ponta estão desligadas**:

- `RelatorioController` + `AnthropicService` + `relatorio_screen.dart` → RF09
- `ScoreController` + `AnthropicService` + `score_analise_screen.dart` → RF08

O backend responde, o `ApiService` tem os métodos, a tela existe — só falta a rota.
Classifiquei como **provável** e não "certeza" justamente porque a decisão aqui
provavelmente é **ligar**, não apagar. O README anuncia RF08 e RF09 como
implementados.

`auth_repository_impl.dart` é resíduo de uma migração para Clean Architecture que
ficou pela metade: `PedidoRepositoryImpl` e `HistoricoRepositoryImpl` são usados,
o de auth não — `AuthService` fala direto com `ApiService`.

## 1.2.3 Métodos do `ApiService` sem nenhum chamador

| Método | Endpoint | Observação | Confiança |
|---|---|---|---|
| `buscarRelatorioMotoboy` / `buscarRelatorioLojista` | `/relatorio/*` | Órfãos porque a tela é órfã (1.2.2) | **provável** |
| `buscarAnaliseScore` | `/score/{id}/analise` | Idem | **provável** |
| `buscarSugestoesTurnos` | `/sugestoes/turnos/{id}` | Idem — RF08 | **provável** |
| `listarTransacoes` | `/transacoes` | **Endpoint não existe** (1.1.4) | **certeza** |
| `buscarGrafico` | `/carteira/{id}/grafico` | Backend implementado, UI não consome | **provável** |
| `buscarAgendaSemanal` | `/agenda/{id}/semana` | Só a visão mensal é usada | **provável** |
| `atualizarPix` | `/carteira/{id}/pix` | Sem tela de cadastro de chave Pix | **provável** |
| `atualizarUsuario` | `/usuarios/{id}` | Substituído por `atualizarPerfil` | **provável** |
| `verificarPendente` | `/avaliacoes/turno/…/pendentes/…` | Telas usam `buscarTurnosAvaliados` | **provável** |
| `iniciarTurno` | `/turnos/{id}/iniciar` | **Esperado**: endpoint novo (SCRUM-20), UI ainda não ligada | **não é morto** |

Só em `feat/scrum-19-20`: `iniciarTurno`.

⚠️ **`atualizarPix` merece atenção**: `CarteiraService.saque()` **exige chave Pix
cadastrada** e devolve 400 se não houver. Como nenhuma tela chama `atualizarPix`,
**o saque é inalcançável na prática** para qualquer motoboy — a única forma de ter
chave Pix é o seed do `DataInitializer`. Isso é um bug funcional, não código morto.

## 1.2.4 Dependências no `pubspec.yaml` sem import

| Dependência | Imports | Veredito | Confiança |
|---|---|---|---|
| `dio: ^5.7.0` | 0 | Remover — o app usa `http` | **certeza** |
| `fl_chart: ^0.68.0` | 0 | Remover — `MiniBarChart` é desenhado à mão, só com `material` | **certeza** |
| `cupertino_icons` | 0 | **Manter** — fonte de ícones, não se importa | suspeito |
| `flutter_lints` | 0 | **Manter** — consumido por `analysis_options.yaml` | suspeito |
| `http`, `provider`, `google_fonts`, `intl`, `shared_preferences`, `flutter_map`, `latlong2`, `flutter_localizations` | 1–26 | Em uso | — |

## 1.2.5 Assets

`pubspec.yaml` **não declara nenhum asset** (`uses-material-design: true` apenas).
Nada a limpar.

## 1.2.6 `print()` de debug e código comentado

Três `print()`, todos em `test/test_helpers.dart` (linhas 529, 533, 559), todos com
`// ignore: avoid_print` e diagnósticos legítimos do carregamento de fonte.
**Nenhum `print()` em `lib/`.** Nenhum bloco de código comentado.

## 1.2.7 TODO / FIXME no Dart

| Arquivo | Linha | Texto |
|---|---|---|
| `lib/views/dashboard_motoboy/dashboard_motoboy_screen.dart` | 31 | `integrar ganhosDiarios com backend` |
| `lib/views/turno_lojista/turno_lojista_screen.dart` | 372 | `endpoint GET /usuarios/{id} não retorna veículo` |
| `lib/views/meus_turnos/meus_turnos_screen.dart` | 512 | `remover após migração completa para AvaliacaoScreen` |
| `lib/views/perfil/perfil_screen.dart` | 15 | `integrar turnosConcluidos e pontualidade` — **já resolvido** em `feat/layout-responsivo-desktop` |

## 1.2.8 Strings duplicadas que deveriam ser constantes

| String | Ocorrências | Risco |
|---|---|---|
| `'valorAsc'` | 6 | Chave de ordenação replicada entre UI e query da API |
| `'finalizado'` | 5 | Status de domínio como literal |
| `'dataInicio'` | 5 | Idem |
| `'Sem conexao com o servidor'` | 5 | Mensagem de erro replicada |
| `'em_andamento'`, `'cancelado'`, `'aceito'`, `'aberto'` | 2–3 cada | Status de domínio |
| `'Erro interno, tente novamente'` | 2 | Mensagem de erro |

Os literais de status são o caso mais grave: o backend tem `StatusTurno` como
constantes (em `feat/scrum-19-20`), o Dart tem o enum `StatusTurno`, mas as strings
de ordenação e de status **continuam soltas nas telas**. Um typo aqui não é pego por
compilador nem por analyzer.

---

# 1.3 Testes

## 1.3.1 Números

| Suíte | Testes | Resultado |
|---|---|---|
| Backend (`feat/scrum-19-20`) | 29 | ✅ 29 passando |
| Backend (`main`) | 14 | ❌ **3 falhando** — NPE em `TurnoServiceTest` |
| Flutter (`feat/layout-responsivo-desktop`) | 33 | ✅ 28 passando, 5 pulados |
| Flutter (demais branches) | 25 | ❌ **8 falhando** (goldens) |

**Cobertura Flutter: 38,0% (1774 / 4670 linhas).**
**Cobertura backend: não medida — não há plugin de cobertura configurado.**

> ❓ **Pergunta antes de agir:** adiciono o JaCoCo ao `pom.xml` para medir a cobertura
> do backend? Isso altera o `pom.xml`, então não fiz nada na Fase 1.

## 1.3.2 Classificação dos testes existentes

### Testes vazios ou sem assert
**Nenhum.** Todos os 29 testes de backend têm asserção real; os 25 goldens comparam
imagem.

### Testes tautológicos
**Nenhum crítico.** Os testes de `TurnoServiceTest`/`TurnoExpiracaoServiceTest`
exercitam ramos de decisão reais (prazo vencido, vagas esgotadas, conflito de
agenda) e não apenas devolvem o mock. `TurnoExpiracaoServiceTest` tem dois casos
que se apoiam no recorte da query em vez da lógica do serviço — mas **de propósito
e documentado**, com `verify` de que o filtro por status é o correto, para o teste
falhar se alguém trocar por `findAll()`.

### Testes duplicados
`perfil_screen_lojista` / `perfil_screen_motoboy` e `agenda_screen_lojista` /
`agenda_screen_motoboy` renderizam a **mesma tela** com o mesmo estado, mudando só o
tipo de usuário — e para a Agenda os dois PNGs eram byte-a-byte idênticos antes da
estabilização. Confiança: **provável** duplicação.

### Testes desabilitados

| Arquivo | Linhas | Motivo declarado |
|---|---|---|
| `test/goldens/lojista_screens_test.dart` | 61, 87, 159 | "Timer HTTP do retry de socket fica pendente após dispose" |
| `test/goldens/motoboy_screens_test.dart` | 41, 97 | idem |

**Cinco testes pulados desde `a6ab282` (2026-06-29) — quase 2 meses.** As telas sem
cobertura por causa disso são justamente as mais complexas do app:
`MeusTurnosScreen` (435 linhas), `HistoricoTurnosScreen` (350),
`TurnosLojistaListaScreen`. A causa é real (o `ApiService` deixa um timer de retry
pendente), mas a solução foi desligar o teste em vez de tornar o serviço
cancelável no `dispose`.

### Testes acoplados a detalhe de implementação
**Os 25 goldens, por natureza.** Comparam pixels: qualquer mudança de padding, fonte
ou cor os quebra sem que o comportamento mude. Isso é aceitável como rede de
regressão visual, desde que se saiba que **eles não testam lógica alguma**.

Dois agravantes encontrados:

1. **`setupGoldenTests()` silencia `RenderFlex overflowed`**
   (`test/test_helpers.dart`, linhas 70–82). A suíte é **estruturalmente incapaz**
   de detectar overflow de layout — que é um dos defeitos mais comuns em Flutter.
2. **A baseline apodrecia sozinha.** Os fakes usavam `DateTime.now()` cru e os cards
   renderizam `HH:mm`, então o golden mudava **a cada minuto**. Já corrigido em
   `feat/layout-responsivo-desktop` (`hojeAncorado()`), mas **as outras duas branches
   ainda têm o problema** — por isso a suíte está vermelha nelas.

## 1.3.3 Lacunas de cobertura em código crítico

Classes de regra de negócio **sem nenhum teste**:

| Classe | Regra que fica descoberta | Prioridade |
|---|---|---|
| `NotificacaoService` | Deduplicação `(usuario, tipo, turno)`; criação em `REQUIRES_NEW` | **alta** |
| `NotificacaoListener` | Tradução evento → notificação para os 5 tipos | **alta** |
| `TurnoScheduler` | Disparo dos jobs através do proxy | **alta** |
| `CarteiraService` | Saque: mínimo R$20, saldo insuficiente, exigência de Pix | **alta** |
| `AvaliacaoController.atualizarMedia` | Recálculo da média de avaliações | média |
| `DashboardController` | Agregações de `turnosAtivos`, `totalGasto`, `avaliacaoMedia` | média |
| Todos os 11 controllers | Contratos HTTP, códigos de status, validação de entrada | média |

Transições de status **testadas**: `aberto→aceito`, `aberto→expirado`,
`aceito→409 ao reaceitar`, vagas esgotadas, conflito de agenda.
Transições **não testadas**: `aceito→em_andamento` (`iniciar`), `→finalizado`,
`→cancelado` com penalidade de score, e todo o fluxo de dupla confirmação de
pagamento — que é o caminho por onde **o dinheiro anda**.

## 1.3.4 O que teste unitário não cobre, por natureza

Dois bugs reais atravessaram a suíte inteira sem serem detectados. Não foi
descuido: **nenhum teste unitário poderia tê-los pego**, porque ambos vivem no
container do Spring, não no código.

| Bug | Por que o unitário não pega |
|---|---|
| `NotificacaoService.criar` sem `REQUIRES_NEW` | Em `@Transactional` com Mockito não existe transação real. O `save()` era chamado (o mock confirmava) e o teste passava — mas em produção o insert era descartado, porque em `AFTER_COMMIT` a transação original já foi commitada. **O teste unitário verifica que o método foi chamado, não que a linha chegou ao banco.** |
| `@Scheduled` no mesmo bean dos métodos `@Transactional` | Auto-invocação não passa pelo proxy do Spring. Em teste unitário **não há proxy nenhum** — o objeto é instanciado com `new`, então a chamada direta sempre "funciona". O defeito só existe quando o Spring gerencia o bean. |

O padrão comum: **os dois falhavam em silêncio, com log de sucesso e nada no banco.**
Foram encontrados rodando o backend de verdade e conferindo o estado via HTTP.

### Recomendação

Áreas que exigem **teste de integração com `@SpringBootTest`**, não unitário:

1. **Propagação transacional e eventos `AFTER_COMMIT`** — `@SpringBootTest` +
   `@Transactional` real (H2), publicando o evento e **consultando o repositório**
   depois para provar que a notificação existe. Um `verify(repo).save(...)` não
   serve.
2. **Jobs agendados** — `@SpringBootTest` com o bean real, invocando
   `TurnoScheduler.executar()` e verificando o efeito no banco. Cobre a classe de
   bug do proxy.
3. **Contratos HTTP** — `@WebMvcTest` + `MockMvc` para os códigos de status
   (400/403/404/409) que hoje só existem como `ResponseStatusException` não
   exercitada.
4. **Concorrência de carteira** — quando a Tarefa 5 entrar, saldo sob operações
   simultâneas só se testa com transações reais.

Custo estimado: um `@SpringBootTest` com H2 já sobe em poucos segundos neste
projeto (o `DataInitializer` popula tudo). Cinco a dez testes de integração cobririam
todos os pontos acima.

---

# 1.4 Higiene do repositório

## 1.4.1 Arquivos indevidamente versionados

**Nenhum.** A varredura por `build/`, `target/`, `.idea/`, `.vscode/`, `*.log`,
`*.env`, `*.iml`, `*.jar`, `*.class`, `node_modules/` no índice do git não retornou
nada. O `.gitignore` (108 linhas) cobre Flutter, Maven, IDEs, SO e chaves.

## 1.4.2 Dois itens do `.gitignore` que causam problema

| Regra | Efeito colateral | Confiança |
|---|---|---|
| `**/mvnw` | O wrapper POSIX **não está versionado** — só existe `mvnw.cmd`. Qualquer CI Linux/macOS ou colaborador não-Windows não consegue buildar com `./mvnw`. | **certeza** |
| `**/pubspec.lock` | Build do Flutter **não é reproduzível**: cada `pub get` pode resolver versões diferentes. Para aplicação (ao contrário de biblioteca), o Dart recomenda versionar o lock. | **certeza** |

O `.gitignore` também documenta explicitamente por que `application*.properties`
**é** versionado — decisão correta e bem justificada no próprio arquivo.

## 1.4.3 Arquivos grandes

`.git` inteiro: **13 MB** — saudável, sem necessidade de reescrita de histórico.

| Blob | Tamanho | Situação |
|---|---|---|
| `Motoshift/MatheusSilverio.docx` | **2,53 MB** | **Ainda na árvore.** Documento Word dentro do diretório do app Flutter. Sozinho é ~20% do repo. |
| `design/prototipos/*.png` (11 arquivos) | ~2,5 MB total | Protótipos de design. Legítimos, mas poderiam sair para outro lugar. |
| `Motoshift/*/screen.png` | ~800 KB | Capturas por tela, aparentemente resíduo de scaffolding. |

Confiança sobre o `.docx`: **provável** que não deva estar aí — mas é decisão sua,
pode ser entregável acadêmico.

## 1.4.4 Credenciais

Varri **todos os blobs do histórico** procurando `sk-ant-*`, `AKIA*`, `ghp_*`,
blocos `BEGIN PRIVATE KEY` e strings de conexão com senha embutida
(`mysql://user:pass@`, `postgresql://user:pass@`).

**Resultado: nenhum segredo real encontrado, em nenhum commit.**

Também conferi todas as versões históricas de `application.properties` e
`application-prod.properties`: sempre usaram `${VARIAVEL_DE_AMBIENTE}`. Inclusive na
época em que o perfil de produção era MySQL (`cf4b740`).

Duas observações que **não são vazamento**, mas são risco:

1. `DataInitializer` semeia todos os usuários com a senha `senha123`, e o `README`
   documenta essas credenciais. Correto para dados de demonstração — desde que o
   `DataInitializer` nunca rode em produção (hoje ele roda: só é barrado por
   `if (usuarioRepo.count() > 0) return`).
2. `Usuario.senha` é gravada em **texto simples** (comentado na própria entidade).
   Já registrado em `DEBITO-TECNICO.md` na branch `feat/scrum-19-20`.

---

# 1.5 Estado das branches

## 1.5.1 Situação atual

```
* feat/layout-responsivo-desktop           a0e6228   3 commits à frente de main
  feat/scrum-19-20-vencimento-notificacoes 6e330d5   4 commits à frente de main
  main                                     d4984cb   = origin/main (limpa)
```

Nenhuma das duas branches de trabalho foi mesclada. **`main` está idêntica ao
remoto**, sem commits locais pendentes.

## 1.5.2 Commits ainda não empurrados — os únicos reescrevíveis

Sete commits, todos locais:

```
a0e6228  fix(avaliacao): separa reputacao de avaliacao e remove stats fixas
82136a7  test(goldens): regrava baseline nesta maquina
2a7afd7  fix(dashboard): "Proximos turnos" nao lista mais turnos encerrados
6e330d5  feat: sistema de notificacoes in-app com eventos de dominio (SCRUM-20)
0bdd4e8  feat: expiracao automatica de turnos nao aceitos (SCRUM-19)
b29dc26  fix(test): repara suite quebrada de TurnoServiceTest e AuthServiceTest
f400cf2  docs: registra debito tecnico de schema (ddl-auto e Flyway pendente)
```

Tudo que está em `origin/*` (incluindo `d4984cb` e anteriores) **não deve ser
reescrito** — já foi publicado.

## 1.5.3 Branches remotas obsoletas

| Branch remota | Situação | Confiança |
|---|---|---|
| `origin/railway/fix-deploy-2a9806` | Conteúdo já em `main` via `eed4407` | **provável** obsoleta |
| `origin/railway/fix-deploy-942dc0` | Já em `main` via `eb822f7` | **provável** obsoleta |
| `origin/railway/fix-deploy-e39a87` | Já em `main` via `b711234` | **provável** obsoleta |

São branches automáticas do Railway cujo conteúdo foi mesclado por PR. Podem ser
apagadas no remoto.

## 1.5.4 Qualidade das mensagens de commit

Os 7 commits locais seguem Conventional Commits com corpo explicativo. O histórico
publicado é majoritariamente bom. Problemas encontrados:

| Commit | Problema | Confiança |
|---|---|---|
| `d4984cb` | **Mistura `fix` e `feat` no mesmo assunto**: "fix: vagas nullable + feat vagas/pagamento por entregador, preco recomendado, validacoes e UI" — cinco assuntos não relacionados sob um prefixo `fix:` | **certeza** |
| `042e0a4` | Cinco assuntos num commit: "vagas multiplas, pagamento por entregador, preco recomendado, validacoes e polimento visual" | **certeza** |
| `042e0a4` + `d4984cb` | **Quase duplicados** — o segundo refaz o primeiro (episódio em que o deploy não subiu) | **provável** |
| `5d3bf99` | "feat: remover notificações + documentar imutabilidade de CNPJ/CNH" — `feat:` para uma **remoção**, e dois assuntos | **provável** |

Nenhuma mensagem genérica do tipo "wip", "ajustes" ou "fix" isolado.

⚠️ Nota histórica relevante: `5d3bf99` **removeu** notificações do projeto, e
`feat/scrum-19-20` as reintroduziu. Vale conferir se a remoção anterior deixou
resíduos antes de mesclar.

---

# Resumo priorizado

## Corrigir — são defeitos, não limpeza

1. **`atualizarPix` sem tela** torna o saque inalcançável (1.2.3) — `certeza`
2. **`listarTransacoes` aponta para endpoint inexistente** (1.1.4) — `certeza`
3. **RF08 e RF09 implementados mas sem rota** — o README os anuncia (1.2.2) — `provável`
4. **Suíte vermelha em `main` e `feat/scrum-19-20`** por goldens instáveis (1.3.1)

## Remover com segurança

5. Import `UsuarioResponse` em `AuthController.java:6` — `certeza`
6. Dependências `dio` e `fl_chart` — `certeza`
7. `kinetic_app_bar.dart` e `kinetic_bottom_nav.dart` — `certeza`

## Higiene

8. Versionar `mvnw` e `pubspec.lock` (revisar `.gitignore`) — `certeza`
9. Decidir sobre `MatheusSilverio.docx` (2,5 MB) — `provável`
10. Apagar as 3 branches `railway/fix-deploy-*` no remoto — `provável`

## Testes

11. Adicionar **testes de integração `@SpringBootTest`** para transação, eventos e
    jobs — é a lacuna que deixou passar dois bugs reais (1.3.4)
12. Reativar os 5 goldens pulados tornando o `ApiService` cancelável no `dispose`
13. Remover o silenciador de `RenderFlex overflowed` do harness (1.3.2)
14. Extrair constantes para os literais de status e ordenação (1.2.8)

## Não tocar

15. As 15 classes "sem referência" — todas gerenciadas pelo Spring
16. As 9 dependências do `dependency:analyze` — starters e drivers runtime
17. `cupertino_icons` e `flutter_lints` — usados por configuração, não por import

---

**Fim da Fase 1.** Nenhuma alteração foi feita. Aguardando sua aprovação item a item
para a Fase 2.
