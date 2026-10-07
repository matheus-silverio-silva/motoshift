# Requisitos — MotoShift

O que o sistema faz hoje, e onde isso está no código. Este documento descreve
o MotoShift **como ele é**: uma plataforma de **turnos agendados** entre
lojistas e entregadores autônomos. A versão anterior deste arquivo descrevia
outro sistema — um marketplace de frete avulso, com MySQL e rotas
`/api/entregas` que nunca existiram — e foi substituída por inteiro.

- Regras de negócio em detalhe: [`README.md`](../README.md), seção "Regras de
  Negócio Implementadas".
- Dinheiro: [`financeiro/FLUXO-FINANCEIRO.md`](financeiro/FLUXO-FINANCEIRO.md),
  [`financeiro/FISCAL.md`](financeiro/FISCAL.md) e
  [`financeiro/RESULTADO.md`](financeiro/RESULTADO.md).
- Navegação: [`ux/NAVEGACAO.md`](ux/NAVEGACAO.md). Modelo de dados:
  [`DER/DER_MotoShift.md`](DER/DER_MotoShift.md).

---

## 1. Visão geral

O **lojista** publica um turno — um período de trabalho com hora de início e
de fim, um valor por entregador e uma ou mais **vagas** — e reserva o valor na
carteira. O **entregador** aceita uma vaga, faz **check-in** no ponto de
partida e trabalha o turno. Na finalização, quem fez check-in é pago, na
hora, com o dinheiro que estava reservado. Os dois lados se avaliam; o lojista
emite a nota do serviço; e cada um acompanha se o trabalho deu lucro.

Dois papéis, definidos no cadastro e gravados no token: `lojista` e `motoboy`
(o entregador). Não há papel de administrador.

**O que é simulado.** O projeto é um trabalho acadêmico, sem credencial de
banco, de prefeitura ou de provedor de e-mail. Três integrações são simuladas,
cada uma atrás de uma interface própria: o Pix (`GatewayPagamento`), a NFS-e
(`EmissorDeNotas`) e o e-mail (`EnvioDeEmail`). O comportamento em volta delas
— cobrança que nasce pendente, saque que pode ser recusado e estornar, nota
com chave de acesso, código de recuperação que sai por outro canal — é real.

## 2. Como os requisitos são numerados

A numeração segue **o que o código já cita**. Os comentários, as anotações do
Swagger e os nomes dos testes usam RF01 a RF07 e RF09; esses números não
mudam. Os demais continuam os do README (RF08 e RF10 a RF13) e seguem em
ordem a partir do RF14.

Uma correção foi necessária: o README chamava de **RF09** o relatório por IA,
enquanto o código usa RF09 para as **notificações** (`NotificacaoController`,
`NotificacaoApi`). Como o código não se renumera, as notificações ficam no
RF09 e o relatório por IA passou a ser o **RF14**.

Os épicos do Jira trazem no título uma numeração mais antiga, de quando o
escopo era menor. Ela não foi alterada lá; a correspondência é esta:

| Épico no Jira | Requisito neste documento |
|---|---|
| SCRUM-1 — Autenticação (RF01) | RF01 |
| SCRUM-2 — Dashboards (RF02) | RF02 |
| SCRUM-3 — Cadastro de Usuários (RF03) | RF03 |
| SCRUM-4 — Publicação de Turnos (RF04) | RF04 |
| SCRUM-5 — Reserva de Turno (RF05) | RF05 |
| SCRUM-6 — Carteira Digital ("RF06") | **RF12** (carteira e ledger) e **RF13** (resultado). No código, RF06 é a finalização do turno, que é quando a carteira recebe |
| SCRUM-7 — Agenda Visual e Cancelamento (RF07) | RF07 (cancelar e desistir) e **RF21** (agenda) |
| SCRUM-8 — Avaliação Mútua ("RF08") | **RF17**. RF08, aqui, é a sugestão de turnos por IA |
| SCRUM-9 — Turnos Disponíveis e Filtros ("RF09") | **RF10** (localização e filtros), **RF16** (vencimento) e **RF09** (notificações) — as três histórias do épico |

---

## 3. Requisitos funcionais

### Conta e acesso

**RF01 — Autenticação.** O usuário entra com e-mail e senha e recebe um token
JWT, que identifica a conta e o papel em toda requisição. O papel é o da
conta: o login não o pergunta. O e-mail não
diferencia maiúsculas nem espaços nas pontas. Depois de 5 senhas erradas a
conta fica bloqueada por 15 minutos; o contador mora no banco e vale para
todas as instâncias. O app restaura a sessão ao abrir e volta ao login quando
o token deixa de valer.

**RF02 — Painéis.** Cada papel tem um painel inicial com os números do
período: para o entregador, saldo, ganhos do mês, turnos aceitos e
concluídos, a meta do mês e os ganhos dos últimos dias; para o lojista, saldo,
turnos publicados, gasto e reputação dos entregadores que o atenderam. Os dois
painéis mostram o resultado do mês — lucro ou prejuízo, por extenso — e levam
à demonstração. As telas se atualizam ao puxar para baixo (celular) ou pelo
botão "Atualizar" (desktop).

**RF03 — Cadastro.** A conta nasce com um papel e um documento: CNPJ para o
lojista (14 dígitos), CNH para o entregador (11 dígitos). Documento, e-mail e
papel não mudam depois do cadastro. Toda conta nasce com carteira.

**RF19 — Senha.** Quem está logado troca a senha informando a atual. Quem
esqueceu pede um código de 6 dígitos, válido por 15 minutos e por 5
tentativas, e cria uma senha nova com ele. O código é guardado só como hash, a
resposta nunca diz se o e-mail tem conta, e redefinir a senha destrava a conta
bloqueada. O envio do e-mail é simulado: o código sai no log do servidor.

### O turno

**RF04 — Publicar turno.** O lojista publica um turno com título, região,
ponto de partida, início e fim, valor por entregador, raio de entrega e número
de **vagas**. O início tem de estar a pelo menos 2 horas. Publicar **reserva**
`valor × vagas` do saldo disponível; sem saldo, a publicação é recusada
dizendo quanto falta. Um turno encerrado pode ser publicado de novo, com o
formulário já preenchido.

**RF05 — Aceitar turno.** O entregador aceita uma vaga de um turno aberto,
desde que não tenha outro turno no mesmo horário. A última vaga não é de dois:
quem chega junto recebe "vagas preenchidas". O turno de várias vagas continua
aberto até a última ser ocupada.

**RF15 — Check-in e check-out.** O entregador registra a chegada ("Cheguei") a
partir de 30 minutos antes do início e a até 500 m do ponto de partida, e a
saída ao terminar. O primeiro check-in põe o turno em andamento e avisa o
lojista. A hora da chegada alimenta a pontualidade do entregador.

**RF06 — Finalizar e pagar.** O turno só pode ser finalizado depois de começar
e com pelo menos um check-in. A finalização **paga quem fez check-in**, na
mesma transação: o valor sai do saldo bloqueado do lojista e entra no
disponível do entregador. Quem aceitou e não chegou fica como `faltou`, sem
pagamento. A sobra da reserva — vagas vazias e faltas — volta ao lojista.

**RF07 — Cancelar e desistir.** Sair de um turno tem uma regra para cada lado.
**Cancelar** é do lojista que publicou: o turno inteiro cai, a reserva volta e
ninguém é penalizado. **Desistir da vaga** é do entregador inscrito: a vaga
dele reabre, o turno segue para os colegas e a loja é avisada; a menos de 1
hora do início, ele perde 0,5 de score. Depois do check-in, nenhum dos dois é
aceito — turno que começou se finaliza.

**RF16 — Turno que se resolve sozinho.** Jobs agendados cuidam do turno que
ninguém fechou: o que passou do início sem entregador **vence** e devolve a
reserva; o aceito que começa em até 1 hora gera um **lembrete** para os dois
lados; o que terminou e não foi finalizado é **cobrado** por notificação e,
passadas 12 horas do fim, **finalizado automaticamente** pela mesma regra do
botão — paga quem fez check-in, devolve o resto.

**RF10 — Localização.** O turno guarda o ponto de partida (latitude e
longitude), que por padrão é o ponto da loja. O entregador filtra os turnos
disponíveis por distância ("perto de mim") e por período, vê o ponto e o raio
de entrega no mapa e abre a rota até lá.

**RF21 — Agenda.** Os dois papéis veem os turnos num calendário mensal e podem
baixar um turno para o calendário do aparelho (`.ics`).

### Dinheiro

**RF12 — Carteira e ledger.** Toda conta tem uma carteira com saldo disponível
e saldo bloqueado. O dinheiro entra por **recarga** (Pix simulado, creditado
só na confirmação) e sai por **saque** (estornado se o banco recusar). Todo
movimento é um lançamento no extrato, com chave de idempotência, e três
invariantes são conferidas: nenhum saldo negativo, carteira igual à soma do
extrato, e a plataforma não cria nem destrói dinheiro. O extrato tem filtros,
paginação e exportação.

**RF18 — Gorjeta e favoritos.** Ao avaliar o entregador, o lojista pode dar
uma gorjeta do saldo disponível — uma transferência no ledger, com
comprovante. O lojista marca entregadores como favoritos; eles são avisados
quando a loja publica um turno e veem os turnos dela com um selo.

**RF11 — Documentos fiscais simulados.** Cada pagamento de turno pode gerar
uma NFS-e — o entregador presta, o lojista toma, e só o lojista emite e
cancela. Os demais lançamentos do extrato geram recibo ou comprovante. Há um
informe anual por contraparte. Todos levam a marca "documento simulado — sem
valor fiscal".

**RF13 — Resultado financeiro.** O usuário acompanha o resultado (lucro ou
prejuízo) do período numa DRE simplificada, em regime de caixa, que combina o
extrato com custos e receitas que ele informa. O que é informado à mão não é
transação: não move saldo nem entra no extrato. O entregador vê margem
líquida, lucro por hora e por turno, custo por km e ponto de equilíbrio; o
lojista, o custo de entrega sobre a receita e o resultado por turno. A data de
um lançamento é a do pagamento, até hoje. Uma conta que se repete todo mês
pode ter o valor alterado só dali em diante, sem mudar o resultado dos meses
que já passaram.

**RF14 — Relatórios.** Cada papel tem um relatório financeiro do período —
resumo, fluxo de caixa e quebra por tipo, com exportação em planilha e PDF — e
um relatório apurado pelo extrato com análise em linguagem natural feita por
IA. Os números não dependem da IA: se ela não responde, o relatório vem sem a
análise.

### Confiança e comunicação

**RF09 — Notificações.** O usuário recebe notificações dentro do app para o
que muda no que é dele: aceite, chegada e saída do entregador, pagamento,
falta, desistência, cancelamento, vencimento, lembrete, turno esquecido, nota
emitida ou cancelada, gorjeta, avaliação pendente e turno novo de uma loja que
o favoritou.
O sino mostra as não lidas e se atualiza sozinho enquanto há sessão. Cada
notificação leva à tela do que aconteceu.

**RF17 — Avaliação mútua.** Depois do turno finalizado, lojista e entregador
se avaliam com nota de 1 a 5 e comentário. Em turno de várias vagas, o lojista
avalia cada entregador. Quem faltou ou cancelou não avalia nem é avaliado.

**RF20 — Reputação.** O entregador tem um score de 0 a 5, que começa em 5 e só
cai por desistência em cima da hora, e uma média das avaliações. O perfil
público mostra a pontualidade e os selos — calculados do histórico, sem
tabela própria — e o entregador define uma meta de ganhos para o mês.

**RF08 — Sugestão de turnos por IA.** O entregador pede uma sugestão de quais
turnos abertos aceitar, gerada por IA a partir do histórico dele.

---

## 4. Requisitos não funcionais

**RNF01 — Plataformas.** Um único código Flutter para Android, iOS e Web, com
layout de celular e de desktop. O app tem nome, ícone e fontes próprios,
embarcados — abre com a mesma cara sem internet.

**RNF02 — Backend e persistência.** Spring Boot 3 sobre Java 17, com
PostgreSQL em produção. O schema é versionado por **Flyway** e conferido
contra as entidades a cada boot (`ddl-auto=validate`); migração aplicada não é
editada. Em desenvolvimento, H2 em memória.

**RNF03 — Segurança.** Toda rota exige token, exceto as listadas como
públicas. A identidade vem do **JWT**, nunca do corpo da requisição; as senhas
são gravadas com **BCrypt**. Segredos entram por variável de ambiente, e sem
os obrigatórios o servidor de produção não sobe. Em produção a documentação
interativa da API fica desligada e o CORS só aceita as origens configuradas.

**RNF04 — Limites de requisição.** As rotas que custam dinheiro ou convidam
abuso têm limite, com resposta 429 e `Retry-After`: 10 por hora por usuário na
sugestão por IA; 20 a cada 10 minutos por IP no cadastro e no pedido de código
de senha. O IP é o de quem chamou, e não o do proxy da hospedagem.

**RNF05 — Integridade do dinheiro.** O saldo só muda dentro de uma transação e
junto com o lançamento que o explica. Operações repetidas não duplicam
dinheiro (idempotência), e operações simultâneas na mesma carteira ou na mesma
vaga não se atropelam (trava otimista com nova tentativa; trava pessimista no
aceite).

**RNF06 — Qualidade verificada.** O backend e o app têm suítes automatizadas —
unidade, integração com PostgreSQL de verdade, widget e comparação visual
(*golden*). A **integração contínua** roda as duas a cada pull request e a
cada push na `main`. As versões do Flutter e das dependências são fixas: o
mesmo commit gera o mesmo app.

**RNF07 — Acessibilidade.** Todo alvo de toque tem pelo menos 44 px e um
rótulo; o texto atende ao contraste do WCAG 2.1 AA nas telas principais;
gráficos, mapas e estrelas têm um resumo em texto; nenhuma informação é dada
só por cor.

**RNF08 — Operação.** O banco fica no Neon, o backend no Render e o app web no
Firebase Hosting, com verificação de saúde. O sistema tem um fuso só, o de
Curitiba, e o servidor roda nele qualquer que seja o fuso da hospedagem. Uma
rota pública de status diz se o servidor está no ar, a hora e a versão
publicada; como o plano gratuito desliga o servidor parado, o app avisa e
espera enquanto ele acorda, em vez de falhar. Um deploy do app web chega ao
navegador sem esperar o cache vencer. Os jobs agendados podem ser desligados
por instância. Dependências externas opcionais — a IA — não derrubam a
funcionalidade que as usa.

---

## 5. Rastreabilidade

Do requisito ao card do Jira, às classes principais e aos testes que o
prendem. Os cards são os do projeto `SCRUM`; o épico aparece primeiro, quando
há um. Caminhos de teste com `.dart` são do app (`Motoshift/test/`); os demais
são classes do backend.

### Requisitos funcionais

| RF | Cards | Classes principais | Testes |
|---|---|---|---|
| RF01 Autenticação | SCRUM-1, SCRUM-10, SCRUM-28, SCRUM-38, SCRUM-49 | `AuthController`, `AuthService`, `JwtService`, `JwtAuthFilter`, `Usuario` · app: `views/login`, `AuthService` | `AuthServiceTest`, `EmailSemMaiusculasTest`, `SegurancaDaApiTest` · `telas/login_e_cadastro_test.dart` |
| RF02 Painéis | SCRUM-2, SCRUM-11, SCRUM-39, SCRUM-49 | `DashboardController`, `DashboardService` · app: `views/dashboard_motoboy`, `views/dashboard_lojista`, `AdaptiveScaffold` | `CarteiraServiceTest` · `goldens/motoboy_screens_test.dart`, `goldens/lojista_screens_test.dart`, `telas/atualizar_test.dart` |
| RF03 Cadastro | SCRUM-3, SCRUM-12 | `AuthService.registrar`, `RegistroRequest`, `CarteiraService` · app: `views/cadastro`, `Validators` | `AuthServiceTest`, `SegurancaDaApiTest` · `telas/login_e_cadastro_test.dart` |
| RF04 Publicar turno | SCRUM-4, SCRUM-13 | `TurnoController`, `TurnoService.criar`, `PagamentoTurnoService.reservar` · app: `views/agendar_turno` | `TurnoServiceTest`, `ReservaELiquidacaoTest`, `TurnoControllerTest` · `repetir/repetir_turno_test.dart`, `localizacao/publicar_turno_ponto_test.dart` |
| RF05 Aceitar turno | SCRUM-5, SCRUM-14, SCRUM-27 | `TurnoService.aceitar`, `TurnoRepository.buscarTravandoAsVagas`, `TurnoInscricao` · app: `views/detalhe_turno` | `TurnoServiceTest`, `AceiteConcorrentePostgresTest`, `TurnoRepositoryTest` |
| RF06 Finalizar e pagar | SCRUM-25 | `TurnoService.finalizar`, `PagamentoTurnoService`, `LedgerService`, `StatusInscricao` · app: `widgets/acoes_do_turno.dart` | `ReservaELiquidacaoTest`, `ConcorrenciaDoLedgerTest`, `MigracoesPostgresTest` (V21) · `turno/acoes_do_turno_test.dart` |
| RF07 Cancelar e desistir | SCRUM-7, SCRUM-16, SCRUM-26 | `TurnoService.cancelar` / `desistir`, `Reputacao`, `TurnoInscricao` · app: `widgets/acoes_do_turno.dart` | `CancelarEDesistirTest`, `ReputacaoTest`, `TurnoControllerTest`, `MigracoesPostgresTest` (V22) · `turno/acoes_do_turno_test.dart` |
| RF08 Sugestão por IA | SCRUM-36 (limite) | `SugestaoController`, `SugestaoService`, `AnthropicService` | `AnthropicServiceTest`, `LimiteDeRequisicoesTest` |
| RF09 Notificações | SCRUM-9, SCRUM-20, SCRUM-33 | `NotificacaoController`, `NotificacaoService`, `Notificacao` · app: `NotificacaoProvider`, `views/notificacoes` | `TurnoLembreteServiceTest`, `CancelarEDesistirTest`, `FinalizacaoAutomaticaTest` · `notificacoes/polling_do_sino_test.dart`, `navegacao/destino_das_notificacoes_test.dart` |
| RF10 Localização | SCRUM-9, SCRUM-18 | `TurnoConsultaService`, `GeoUtils`, `TurnoRepository` · app: `LocalizacaoService`, `widgets/mapa_raio.dart`, `views/meus_turnos` | `FiltroPorDistanciaTest`, `GeoUtilsTest` · `localizacao/perto_de_mim_test.dart`, `localizacao/ponto_da_loja_test.dart`, `localizacao/localizacao_service_test.dart` |
| RF11 Documentos fiscais | — | `NotaFiscalController`, `NotaFiscalService`, `DocumentoFiscalService`, `InformeRendimentosService`, `EmissorSimulado` · app: `views/notas_fiscais`, `views/documento_fiscal` | `NotaFiscalServiceTest`, `DocumentoFiscalServiceTest`, `NotasEInformeTest`, `RetencaoNaFonteTest`, `NotaFiscalControllerTest` · `fiscal/quem_emite_test.dart`, `documento/documento_fiscal_test.dart` |
| RF12 Carteira e ledger | SCRUM-6, SCRUM-15, SCRUM-30 | `CarteiraController`, `LedgerService`, `Movimento`, `CobrancaService`, `ExtratoService`, `ConsistenciaService`, `GatewayPagamentoSimulado` · app: `views/carteira`, `views/extrato`, `views/recarga` | `LedgerServiceTest`, `InvarianteTest`, `CobrancaServiceTest`, `ExtratoServiceTest`, `CarteiraPeloHttpTest`, `ConsistenciaSemPerfilTest` · `telas/extrato_filtrado_test.dart`, `telas/recarga_test.dart` |
| RF13 Resultado financeiro | SCRUM-6, SCRUM-47, SCRUM-49 | `DreController`, `DreService`, `LancamentoGerencialController`, `LancamentoGerencialService`, `Recorrencia`, `CategoriaLancamento` · app: `views/resultado` | `DreServiceTest`, `RecorrenciaTest`, `LancamentoGerencialHttpTest`, `LancamentosGerenciaisForaDoLedgerTest`, `MigracoesPostgresTest` (V25) · `telas/resultado_test.dart`, `models/dre_test.dart`, `goldens/resultado_screens_test.dart` |
| RF14 Relatórios | — | `RelatorioController`, `RelatorioService`, `ExtratoService`, `AnthropicService` · app: `views/relatorios_financeiros`, `services/relatorio_pdf.dart` | `RelatorioServiceTest`, `ExtratoServiceTest` · `exportacao/exportar_pdf_test.dart`, `telas/cada_papel_ve_o_seu_test.dart` |
| RF15 Check-in e check-out | — | `CheckinService`, `TurnoInscricao`, `Reputacao.pontualidade` · app: `widgets/checkin_do_turno.dart` | `CheckinServiceTest` · `checkin/checkin_test.dart` |
| RF16 Turno que se resolve sozinho | SCRUM-9, SCRUM-19, SCRUM-31 | `TurnoExpiracaoService`, `TurnoExpiracaoJobs`, `TurnoLembreteService`, `TurnoService.finalizarPeloSistema` | `TurnoExpiracaoServiceTest`, `FinalizacaoAutomaticaTest`, `TurnoLembreteServiceTest`, `JobsDesligadosTest` · `telas/turnos_expirados_test.dart` |
| RF17 Avaliação mútua | SCRUM-8, SCRUM-17 | `AvaliacaoController`, `AvaliacaoService`, `Avaliacao` · app: `views/avaliacao`, `views/avaliar_entregadores`, `views/minhas_avaliacoes` | `MassaDemonstracaoTest` · `models/avaliacao_multivaga_test.dart`, `reputacao/reputacao_e_avaliacao_test.dart`, `navegacao/caminhos_para_avaliar_test.dart` |
| RF18 Gorjeta e favoritos | — | `GorjetaController`, `GorjetaService`, `FavoritoController`, `FavoritoService` · app: `widgets/seletor_de_gorjeta.dart`, `FavoritosProvider` | `GorjetaServiceTest`, `GorjetaControllerTest`, `FavoritoServiceTest`, `FavoritoControllerTest` · `gorjeta/gorjeta_test.dart`, `favoritos/favoritos_test.dart` |
| RF19 Senha | SCRUM-32 | `AuthController`, `SenhaService`, `CodigoRecuperacaoSenha`, `EnvioDeEmailSimulado` · app: `views/alterar_senha`, `views/recuperar_senha` | `SenhaPeloHttpTest`, `MigracoesPostgresTest` (V24) · `telas/senha_test.dart` |
| RF20 Reputação | — | `Reputacao`, `ScoreService`, `Selos`, `ScoreController`, `UsuarioController` · app: `views/perfil_publico`, `widgets/selos_de_reputacao.dart`, `widgets/meta_do_mes.dart` | `ReputacaoTest`, `ScoreServiceTest`, `SelosTest` · `reputacao/reputacao_e_avaliacao_test.dart`, `models/usuario_perfil_publico_test.dart` |
| RF21 Agenda | SCRUM-7, SCRUM-16 | `AgendaController`, `AgendaService` · app: `views/agenda`, `utils/calendario_ics.dart` | `goldens/motoboy_screens_test.dart`, `goldens/lojista_screens_test.dart`, `rapidas/calendario_ics_test.dart` |

### Requisitos não funcionais

| RNF | Cards | Onde está | Testes |
|---|---|---|---|
| RNF01 Plataformas | SCRUM-29, SCRUM-37, SCRUM-41 | `Motoshift/` (um código), `android/`, `ios/`, `web/`, `assets/fonts`, `AdaptiveScaffold` | `goldens/*`, `navegacao/master_detail_test.dart`, `navegacao/desktop_voltar_test.dart` |
| RNF02 Backend e persistência | — | `db/migration/V1` a `V25`, `application-prod.properties` | `MigracoesPostgresTest`, `SchemaPostgresTest`, `ContextoESchemaTest`, `BackfillV5Test` |
| RNF03 Segurança | SCRUM-30, SCRUM-36 | `SecurityConfig`, `JwtAuthFilter`, `UsuarioAutenticado`, `ApiExceptionHandler` | `SegurancaDaApiTest`, `PerfilDeProducaoTest`, `ConsistenciaSemPerfilTest`, `PropriedadesDeConfiguracaoTest` |
| RNF04 Limites de requisição | SCRUM-36, SCRUM-48 | `LimiteDeRequisicoesFilter`, `JanelaDeslizante` | `JanelaDeslizanteTest`, `LimiteDeRequisicoesFilterTest`, `LimiteDeRequisicoesTest` |
| RNF05 Integridade do dinheiro | SCRUM-27 | `LedgerService`, `RetentativaOtimista`, `ConsistenciaService`, `TurnoRepository.buscarTravandoAsVagas` | `InvarianteTest`, `ConcorrenciaDoLedgerTest`, `AceiteConcorrentePostgresTest`, `LancamentosGerenciaisForaDoLedgerTest`, `MassaDemonstracaoTest` |
| RNF06 Qualidade verificada | SCRUM-42, SCRUM-45, SCRUM-46 | `.github/workflows/ci.yml`, `Motoshift/pubspec.lock`, `Motoshift/Dockerfile`, `.github/` | As duas suítes, rodadas pelo CI |
| RNF07 Acessibilidade | SCRUM-40 | `utils/resumo_acessivel.dart`, `AppColors.tealTexto`, `widgets/olho_da_senha.dart` | `a11y/alvo_de_toque_test.dart`, `a11y/diretrizes_test.dart`, `a11y/resumos_test.dart` |
| RNF08 Operação | SCRUM-31, SCRUM-36, SCRUM-48 | `TurnoExpiracaoJobs`, `application-prod.properties`, `RelatorioService.analisar`, `MotoshiftApplication.aplicarFuso`, `StatusController`, `backend/Dockerfile`, `services/servidor_service.dart`, `widgets/faixa_do_servidor.dart`, `Motoshift/firebase.json` | `JobsDesligadosTest`, `PerfilDeProducaoTest`, `RelatorioServiceTest`, `FusoHorarioTest`, `StatusHttpTest`, `servidor/servidor_acordando_test.dart` |

"—" na coluna de cards quer dizer que o requisito foi entregue antes de o
projeto usar as chaves do Jira nos commits, ou fora de um card: a
rastreabilidade dele é pelo código e pelos testes.

---

## 6. Fora do escopo

Conhecido, registrado e não implementado:

- **Excluir a conta** (SCRUM-34) e **CPF do entregador** (SCRUM-35).
- **Atualização do Spring Boot** para a linha 3.5 (SCRUM-43).
- **Envio de e-mail por um provedor de verdade**, e revogação das sessões
  abertas ao trocar a senha.
- **Taxa ou comissão da plataforma**, e uma DRE do próprio MotoShift; regime
  de competência e depreciação contábil na DRE dos usuários.
- **Rastreamento do entregador em tempo real** durante o turno.
- **Notificações push**: as notificações são dentro do app, com atualização
  periódica do sino.
- **Limite de requisições compartilhado entre réplicas** e trava distribuída
  para os jobs agendados — hoje, uma instância roda os jobs.
