package com.motoshift.config;

import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.Carteira;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.Notificacao;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.service.Reputacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A massa de demonstração e o reset leve ({@code confirmo}), contra o banco.
 *
 * Além do escopo do reset, confere a história que a massa conta: meses de
 * recarga, turno e saque; notas emitidas pelo lojista; score e média saídos
 * da regra; notificações dos tipos de hoje.
 *
 * As chaves estrangeiras não existem no H2; os dois modos de reset rodam
 * sobre o PostgreSQL, com as FKs da V11, em ResetDaMassaPostgresTest.
 */
@SpringBootTest
@ActiveProfiles("test")
class MassaDemonstracaoTest {

    @Autowired private MassaDemonstracao massa;
    @Autowired private ResetDaMassaNoBoot resetNoBoot;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private AvaliacaoRepository avaliacaoRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private NotaFiscalRepository notaRepo;
    @Autowired private NotaFiscalService notasFiscais;
    @Autowired private Reputacao reputacao;
    @Autowired private com.motoshift.repository.FavoritoRepository favoritoRepo;
    @Autowired private com.motoshift.service.Selos selos;
    @Autowired private com.motoshift.service.FavoritoService favoritos;
    @Autowired private com.motoshift.service.TurnoConsultaService consultas;
    @Autowired private com.motoshift.service.DreService dre;

    @Test
    @DisplayName("sem MOTOSHIFT_SEED_RESET o boot nao apaga nem cria nada")
    void semTrava_nadaMuda() {
        massa.resetar();
        Estado antes = estado();

        resetNoBoot.run(null);

        assertThat(estado()).isEqualTo(antes);
    }

    @Test
    @DisplayName("resetar duas vezes seguidas deixa o banco no mesmo estado")
    void resetarEIdempotente() {
        massa.resetar();
        Estado primeiro = estado();

        massa.resetar();

        assertThat(estado()).isEqualTo(primeiro);
        assertThat(primeiro.contagem().get("usuarios")).isEqualTo(8);
    }

    @Test
    @DisplayName("conta que nao termina em @teste.com — e tudo que e dela — fica intacta")
    void contaRealIntacta() {
        massa.resetar();

        Usuario loja = usuarioReal("Padaria de Verdade", "contato@padariadeverdade.com.br", "lojista");
        Usuario entregador = usuarioReal("Entregador de Verdade", "entregador@gmail.com", "motoboy");
        // Parecido, mas nao e o sufixo: o @ faz parte dele.
        Usuario quase = usuarioReal("Quase", "fulano@naoteste.com", "motoboy");

        Carteira carteira = new Carteira();
        carteira.setUsuarioId(entregador.getId());
        carteira.setSaldoDisponivel(new BigDecimal("50.00"));
        carteiraRepo.save(carteira);

        Turno turno = new Turno();
        turno.setLojistId(loja.getId());
        turno.setMotoboyId(entregador.getId());
        turno.setTitulo("Turno real");
        turno.setDataInicio(LocalDateTime.now().minusDays(2));
        turno.setDataFim(LocalDateTime.now().minusDays(2).plusHours(4));
        turno.setValorEstimado(new BigDecimal("80.00"));
        turno.setStatus(StatusTurno.FINALIZADO);
        turno.setPagamentoStatus(StatusPagamento.PAGO);
        turno = turnoRepo.save(turno);

        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(turno.getId());
        ins.setMotoboyId(entregador.getId());
        ins.setStatus(StatusInscricao.FINALIZADO);
        inscricaoRepo.save(ins);

        Transacao tx = new Transacao();
        tx.setUsuarioId(entregador.getId());
        tx.setContraparteId(loja.getId());
        tx.setTurnoId(turno.getId());
        tx.setTipo(TipoTransacao.PAGAMENTO_RECEBIDO);
        tx.setNatureza(com.motoshift.entity.NaturezaTransacao.CREDITO);
        tx.setStatus(StatusTransacao.CONCLUIDO);
        tx.setValor(new BigDecimal("80.00"));
        tx.setIdempotencyKey("teste-real:" + UUID.randomUUID());
        transacaoRepo.save(tx);

        Avaliacao av = new Avaliacao();
        av.setTurnoId(turno.getId());
        av.setAvaliadorId(loja.getId());
        av.setAvaliadoId(entregador.getId());
        av.setNota(5);
        avaliacaoRepo.save(av);

        massa.resetar();

        assertThat(usuarioRepo.findById(loja.getId())).isPresent();
        assertThat(usuarioRepo.findById(entregador.getId())).isPresent();
        assertThat(usuarioRepo.findById(quase.getId())).isPresent();
        assertThat(turnoRepo.findById(turno.getId())).get()
                .extracting(Turno::getTitulo).isEqualTo("Turno real");
        assertThat(inscricaoRepo.findById(ins.getId())).isPresent();
        assertThat(transacaoRepo.findById(tx.getId())).isPresent();
        assertThat(avaliacaoRepo.findById(av.getId())).isPresent();
        assertThat(carteiraRepo.findByUsuarioId(entregador.getId())).get()
                .extracting(Carteira::getSaldoDisponivel)
                .satisfies(s -> assertThat(s).isEqualByComparingTo("50.00"));
    }

    @Test
    @DisplayName("o que uma conta real fez DENTRO da massa sai junto; a conta real fica")
    void interacaoComAMassaSaiJunto() {
        massa.resetar();
        Usuario real = usuarioReal("Entregador Curioso", "curioso@gmail.com", "motoboy");
        Usuario claudia = usuarioRepo.findByEmail("claudia@teste.com").orElseThrow();
        Turno daClaudia = turnoRepo.findByLojistId(claudia.getId()).stream()
                .filter(t -> t.getStatus() == StatusTurno.ABERTO)
                .findFirst().orElseThrow();

        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(daClaudia.getId());
        ins.setMotoboyId(real.getId());
        ins = inscricaoRepo.save(ins);

        massa.resetar();

        // O turno da Claudia foi recriado; a vaga que o entregador real ocupou
        // nele era parte da demonstracao. Sem apagar a inscricao, a FK da V11
        // impediria apagar o turno.
        assertThat(inscricaoRepo.findById(ins.getId())).isEmpty();
        assertThat(usuarioRepo.findById(real.getId())).isPresent();
    }

    @Test
    @DisplayName("toda data da massa sai de agora — nada de data fixa envelhecendo")
    void datasDerivadasDeAgora() {
        massa.resetar();
        LocalDateTime agora = LocalDateTime.now();
        LocalDate hoje = agora.toLocalDate();

        List<Usuario> contas = contasDaMassa();
        List<Turno> turnos = turnosDaMassa();

        // Seis publicados à espera de entregador e um sétimo que reabriu: o
        // Ricardo tinha aceitado e desistiu com folga.
        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.ABERTO)
                .hasSize(7)
                .allSatisfy(t -> assertThat(t.getDataInicio()).isAfter(agora));

        // Três aceitos por começar: dois para amanhã e um em menos de 1 hora
        // (o do lembrete).
        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.ACEITO)
                .hasSize(3)
                .allSatisfy(t -> assertThat(t.getDataInicio()).isAfter(agora))
                .filteredOn(t -> t.getDataInicio().isBefore(agora.plusHours(1)))
                .hasSize(1);

        // Um em andamento: começou há pouco, e o Ricardo fez check-in (V16).
        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.EM_ANDAMENTO)
                .singleElement()
                .satisfies(t -> {
                    assertThat(t.getDataInicio()).isBefore(agora);
                    assertThat(t.getDataFim()).isAfter(agora);
                    assertThat(inscricaoRepo.findByTurnoId(t.getId()))
                            .singleElement()
                            .satisfies(i -> assertThat(i.getCheckinEm()).isBefore(agora));
                });

        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.FINALIZADO)
                .hasSizeGreaterThan(60)
                .allSatisfy(t -> assertThat(t.getDataFim()).isBefore(agora));

        // Vencido pelo próprio job de expiração, sem ninguém.
        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.EXPIRADO)
                .singleElement()
                .satisfies(t -> {
                    assertThat(t.getMotoboyId()).isNull();
                    assertThat(t.getExpiradoEm()).isBefore(agora);
                });

        // Duas desistências, cada uma na inscrição de quem desistiu (V22): a
        // do Ricardo com folga — o turno reabriu, sem entregador —, e a do
        // Thiago em cima da hora, a menos de 1h do início.
        Long thiago = id("thiago@teste.com");
        Long ricardo = id("ricardo@teste.com");
        Long claudia = id("claudia@teste.com");
        assertThat(inscricaoRepo.desistenciasDe(ricardo)).singleElement().satisfies(d -> {
            assertThat(d.canceladoEm()).isBefore(d.inicioDoTurno().minusHours(1));
            Turno reaberto = turnoRepo.findById(d.turnoId()).orElseThrow();
            assertThat(reaberto.getStatus()).isEqualTo(StatusTurno.ABERTO);
            assertThat(reaberto.getMotoboyId()).isNull();
        });
        assertThat(inscricaoRepo.desistenciasDe(thiago)).singleElement().satisfies(d ->
                assertThat(d.canceladoEm()).isAfter(d.inicioDoTurno().minusHours(1)));

        // Um turno cancelado — pela loja: sem entregador a meia hora do
        // início, a Cláudia cancelou o turno de que o Thiago tinha desistido.
        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.CANCELADO)
                .singleElement()
                .satisfies(t -> {
                    assertThat(t.getCanceladoPorId()).isEqualTo(claudia);
                    assertThat(t.getMotoboyId()).isNull();
                    assertThat(inscricaoRepo.desistenciasDe(thiago))
                            .extracting(com.motoshift.repository.Desistencia::turnoId)
                            .containsExactly(t.getId());
                });

        assertThat(contas).filteredOn(u -> "motoboy".equals(u.getTipo()))
                .allSatisfy(u -> assertThat(u.getCnhValidade()).isAfter(hoje));
        assertThat(contas)
                .allSatisfy(u -> assertThat(u.getDataNascimento()).isBefore(hoje.minusYears(18)));

        Set<Long> ids = Set.copyOf(idsDaMassa());
        assertThat(transacaoRepo.findAll()).filteredOn(t -> ids.contains(t.getUsuarioId()))
                .isNotEmpty()
                .allSatisfy(t -> assertThat(t.getCriadoEm()).isBeforeOrEqualTo(agora));

        assertThat(notificacaoRepo.findTop50ByUsuarioIdOrderByCriadoEmDesc(id("claudia@teste.com")))
                .isNotEmpty();
    }

    @Test
    @DisplayName("quatro a seis meses de história: recarga e saque por mês, turno pago todo mês")
    void historiaDeMeses() {
        massa.resetar();
        LocalDate hoje = LocalDate.now();
        Set<Long> ids = Set.copyOf(idsDaMassa());
        List<Transacao> extrato = transacaoRepo.findAll().stream()
                .filter(t -> ids.contains(t.getUsuarioId()))
                .toList();

        LocalDate primeira = extrato.stream().map(t -> t.getCriadoEm().toLocalDate())
                .min(LocalDate::compareTo).orElseThrow();
        assertThat(primeira).isBetween(hoje.minusMonths(6), hoje.minusMonths(4));

        // Cada um dos quatro meses anteriores tem recarga, saque e pagamento.
        for (int m = 1; m <= 4; m++) {
            java.time.YearMonth mes = java.time.YearMonth.from(hoje.minusMonths(m));
            Set<TipoTransacao> doMes = extrato.stream()
                    .filter(t -> java.time.YearMonth.from(t.getCriadoEm()).equals(mes))
                    .map(Transacao::getTipo)
                    .collect(Collectors.toSet());
            assertThat(doMes).as("tipos de %s", mes)
                    .contains(TipoTransacao.RECARGA, TipoTransacao.SAQUE,
                              TipoTransacao.PAGAMENTO_ENVIADO, TipoTransacao.PAGAMENTO_RECEBIDO);
        }

        // Todo entregador sacou e toda loja recarregou pelo gateway.
        for (Usuario u : contasDaMassa()) {
            TipoTransacao esperado = "motoboy".equals(u.getTipo()) ? TipoTransacao.SAQUE : TipoTransacao.RECARGA;
            assertThat(extrato).as("%s de %s", esperado, u.getEmail())
                    .anyMatch(t -> t.getUsuarioId().equals(u.getId()) && t.getTipo() == esperado);
        }
    }

    @Test
    @DisplayName("notas: quem emite é o lojista; o turno de três vagas tem três; uma cancelada; recentes sem nota")
    void notasDoLojista() {
        massa.resetar();
        Set<Long> turnos = turnosDaMassa().stream().map(Turno::getId).collect(Collectors.toSet());
        List<NotaFiscal> notas = notaRepo.findByTurnoIdIn(turnos);

        assertThat(notas).hasSizeGreaterThan(50)
                .allSatisfy(n -> assertThat(n.getEmitidaPorId())
                        .as("nota %s emitida pelo tomador", n.getNumero())
                        .isEqualTo(n.getTomadorId()));

        Turno tresVagas = turnosDaMassa().stream()
                .filter(t -> t.getVagas() == 3)
                .findFirst().orElseThrow();
        assertThat(notaRepo.findByTurnoId(tresVagas.getId()))
                .extracting(NotaFiscal::getPrestadorId)
                .containsExactlyInAnyOrder(id("ricardo@teste.com"), id("lucas@teste.com"), id("thiago@teste.com"));

        assertThat(notas).filteredOn(NotaFiscal::isCancelada)
                .singleElement()
                .satisfies(n -> {
                    assertThat(n.getTomadorId()).isEqualTo(id("fernando@teste.com"));
                    assertThat(n.getCanceladaEm()).isAfter(n.getEmitidaEm());
                });

        // Pagamentos ainda sem nota: "a emitir" para a loja, "aguardando
        // emissão" para o entregador — os dois lados da mesma pendência.
        assertThat(notasFiscais.pendentes(id("lojista@teste.com"), true)).hasSize(1);
        assertThat(notasFiscais.pendentes(id("motoboy@teste.com"), false)).hasSize(1);
        assertThat(notasFiscais.pendentes(id("ana@teste.com"), true)).hasSize(1);
        assertThat(notasFiscais.pendentes(id("claudia@teste.com"), true)).hasSize(1);
        assertThat(notasFiscais.pendentes(id("fernando@teste.com"), true)).isEmpty();
    }

    @Test
    @DisplayName("score e média saem da regra: Thiago 4,5 pela desistência em cima da hora, lojista sem score")
    void reputacaoDerivada() {
        massa.resetar();

        for (Usuario u : contasDaMassa()) {
            Double visivel = reputacao.scoreVisivel(u);
            if ("lojista".equals(u.getTipo())) {
                assertThat(visivel).as("score de %s", u.getEmail()).isNull();
            } else if (u.getEmail().equals("thiago@teste.com")) {
                assertThat(visivel).isEqualTo(Reputacao.SCORE_INICIAL - Reputacao.PENALIDADE_CANCELAMENTO_TARDIO);
            } else {
                assertThat(visivel).as("score de %s", u.getEmail()).isEqualTo(Reputacao.SCORE_INICIAL);
            }

            // A média gravada é a média das avaliações recebidas, com uma casa
            // como o AvaliacaoService grava — nunca um número escrito à mão.
            List<Avaliacao> recebidas = avaliacaoRepo.findByAvaliadoIdOrderByCriadoEmDesc(u.getId());
            assertThat(recebidas).as("avaliações de %s", u.getEmail()).isNotEmpty();
            double media = recebidas.stream().mapToInt(Avaliacao::getNota).average().orElseThrow();
            assertThat(u.getMediaAvaliacao()).as("média de %s", u.getEmail())
                    .isEqualTo(Math.round(media * 10.0) / 10.0);
        }

        // Notas variadas, com algumas abaixo de 5.
        List<Integer> notas = avaliacaoRepo.findAll().stream()
                .filter(a -> Set.copyOf(idsDaMassa()).contains(a.getAvaliadoId()))
                .map(Avaliacao::getNota).toList();
        assertThat(notas).contains(3, 4, 5).allSatisfy(n -> assertThat(n).isBetween(1, 5));
    }

    @Test
    @DisplayName("comentários usam as tags do papel de quem é avaliado")
    void comentariosComTagsDoPapel() {
        massa.resetar();
        Map<Long, String> tipo = contasDaMassa().stream()
                .collect(Collectors.toMap(Usuario::getId, Usuario::getTipo));

        List<Avaliacao> comTags = avaliacaoRepo.findAll().stream()
                .filter(a -> tipo.containsKey(a.getAvaliadoId()))
                .filter(a -> a.getComentario() != null && a.getComentario().contains(" • "))
                .toList();
        assertThat(comTags).isNotEmpty();
        for (Avaliacao a : comTags) {
            Set<String> permitidas = "lojista".equals(tipo.get(a.getAvaliadoId())) ? TAGS_DA_LOJA : TAGS_DO_ENTREGADOR;
            String tags = a.getComentario().split(" — ")[0];
            for (String tag : tags.split(" • ")) {
                assertThat(permitidas).as("tag de \"%s\"", a.getComentario()).contains(tag);
            }
        }
    }

    @Test
    @DisplayName("notificações: só os tipos que o código gera hoje, sem texto de fluxo aposentado")
    void notificacoesAtuais() {
        massa.resetar();
        Set<Long> ids = Set.copyOf(idsDaMassa());
        List<Notificacao> todas = notificacaoRepo.findAll().stream()
                .filter(n -> ids.contains(n.getUsuarioId()))
                .toList();

        assertThat(todas).isNotEmpty()
                .allSatisfy(n -> {
                    assertThat(TIPOS_DE_NOTIFICACAO).contains(n.getTipo());
                    assertThat(n.getMensagem()).doesNotContainIgnoringCase("confirme")
                            .doesNotContainIgnoringCase("confirmação");
                });
        assertThat(todas).extracting(Notificacao::getTipo)
                .contains("turno_aceito", "avaliacao_pendente", "turno_cancelado", "turno_expirado",
                          "nota_fiscal_emitida", "nota_fiscal_cancelada",
                          "entregador_chegou", "entregador_saiu", "gorjeta_recebida",
                          "turno_de_favorito", "turno_lembrete", "entregador_desistiu");
    }

    /**
     * A massa passa por tudo o que esta revisão acrescentou — pelos serviços
     * de verdade, com a data de cada passo: check-in (V16), gorjeta (V17),
     * favoritos (V18), meta do mês e selos (V19), lembrete de 1 hora.
     */
    @Test
    @DisplayName("a massa exercita as novidades: presença, gorjeta, favoritos, meta, selos e lembrete")
    void novidadesNaMassa() {
        massa.resetar();
        LocalDateTime agora = LocalDateTime.now();
        Long ricardo = id("ricardo@teste.com"), lucas = id("lucas@teste.com"),
             thiago = id("thiago@teste.com"), carlos = id("motoboy@teste.com");
        Long claudia = id("claudia@teste.com"), fernando = id("fernando@teste.com"),
             ana = id("ana@teste.com"), maria = id("lojista@teste.com");

        // Pontualidades diferentes: Ricardo sempre antes, Carlos quase sempre,
        // Lucas às vezes, Thiago metade das vezes (ou menos).
        Integer pRicardo = reputacao.pontualidade(ricardo).percentual();
        Integer pCarlos = reputacao.pontualidade(carlos).percentual();
        Integer pLucas = reputacao.pontualidade(lucas).percentual();
        Integer pThiago = reputacao.pontualidade(thiago).percentual();
        assertThat(pRicardo).isEqualTo(100);
        assertThat(pCarlos).isBetween(90, 99);
        assertThat(pLucas).isBetween(60, 89);
        assertThat(pThiago).isLessThan(50);

        // Gorjetas: a Cláudia dá; o Fernando deu duas; Maria e Ana, nenhuma.
        Map<Long, Long> gorjetasDadas = transacaoRepo.findAll().stream()
                .filter(t -> t.getTipo() == TipoTransacao.BONUS_ENVIADO)
                .collect(Collectors.groupingBy(Transacao::getUsuarioId, Collectors.counting()));
        assertThat(gorjetasDadas.get(claudia)).isGreaterThanOrEqualTo(3);
        assertThat(gorjetasDadas.get(fernando)).isEqualTo(2);
        assertThat(gorjetasDadas).doesNotContainKeys(maria, ana);
        assertThat(transacaoRepo.findAll()).anyMatch(t -> t.getTipo() == TipoTransacao.BONUS
                && t.getUsuarioId().equals(lucas) || t.getTipo() == TipoTransacao.BONUS
                && t.getUsuarioId().equals(ricardo));

        // Favoritos: Cláudia → Ricardo e Lucas; Maria → Carlos; Fernando → Lucas.
        assertThat(favoritoRepo.findAll())
                .extracting(f -> f.getLojistaId() + ">" + f.getMotoboyId())
                .containsExactlyInAnyOrder(claudia + ">" + ricardo, claudia + ">" + lucas,
                        maria + ">" + carlos, fernando + ">" + lucas);
        // ...e o selo aparece para quem foi chamado.
        List<com.motoshift.dto.TurnoResponse> disponiveis =
                consultas.listarDisponiveis(null).getContent();
        favoritos.marcarLojasQueTeChamaram(disponiveis, lucas);
        assertThat(disponiveis).filteredOn(com.motoshift.dto.TurnoResponse::isLojaQueJaTeChamou)
                .isNotEmpty()
                .allSatisfy(t -> assertThat(t.getLojistId()).isIn(claudia, fernando));

        // Meta: Ricardo e Carlos definiram; Lucas e Thiago não.
        assertThat(usuarioRepo.findById(ricardo).orElseThrow().getMetaMensal()).isEqualByComparingTo("2000");
        assertThat(usuarioRepo.findById(carlos).orElseThrow().getMetaMensal()).isEqualByComparingTo("1500");
        assertThat(usuarioRepo.findById(lucas).orElseThrow().getMetaMensal()).isNull();
        assertThat(usuarioRepo.findById(thiago).orElseThrow().getMetaMensal()).isNull();

        // Selos em uns perfis e não em outros.
        assertThat(codigosDosSelos(carlos)).containsExactly(
                "turnos_concluidos", "sem_cancelar", "nota_alta", "pontual");
        assertThat(codigosDosSelos(lucas)).containsExactly("turnos_concluidos", "sem_cancelar");
        assertThat(codigosDosSelos(ricardo)).as("desistiu de uma vaga, com folga").containsExactly("pontual");
        assertThat(codigosDosSelos(thiago)).isEmpty();
        assertThat(codigosDosSelos(claudia)).containsExactly("paga_gorjeta", "toda_semana");
        assertThat(codigosDosSelos(maria)).containsExactly("nota_alta", "toda_semana");
        assertThat(codigosDosSelos(fernando)).isEmpty();
        assertThat(codigosDosSelos(ana)).isEmpty();

        // Notificações recentes, ainda no sino: a chegada do Ricardo (para a
        // Cláudia), o lembrete de 1 hora (Lucas e Fernando) e os turnos novos
        // das lojas favoritas.
        assertThat(naoLidas(claudia, "entregador_chegou")).isNotEmpty();
        assertThat(naoLidas(lucas, "turno_lembrete")).singleElement()
                .satisfies(n -> assertThat(n.getMensagem()).contains("na Pizzaria do Fernando"));
        assertThat(naoLidas(fernando, "turno_lembrete")).singleElement()
                .satisfies(n -> assertThat(n.getMensagem()).contains("com Lucas"));
        assertThat(naoLidas(ricardo, "turno_de_favorito"))
                .allSatisfy(n -> assertThat(n.getMensagem()).startsWith("A Hamburgueria da Cláudia publicou"))
                .isNotEmpty();
        assertThat(naoLidas(carlos, "turno_de_favorito"))
                .allSatisfy(n -> assertThat(n.getMensagem()).startsWith("O Mercado Andrade publicou"))
                .isNotEmpty();
        assertThat(naoLidas(thiago, "turno_de_favorito")).isEmpty();
        // As antigas já foram lidas; nenhuma é do futuro.
        assertThat(notificacaoRepo.findAll()).allSatisfy(n ->
                assertThat(n.getCriadoEm()).isBeforeOrEqualTo(agora.plusMinutes(1)));
    }

    private List<String> codigosDosSelos(Long usuarioId) {
        return selos.de(usuarioRepo.findById(usuarioId).orElseThrow()).stream()
                .map(com.motoshift.service.Selos.Selo::codigo).toList();
    }

    private List<Notificacao> naoLidas(Long usuarioId, String tipo) {
        return notificacaoRepo.findTop50ByUsuarioIdOrderByCriadoEmDesc(usuarioId).stream()
                .filter(n -> tipo.equals(n.getTipo()) && !Boolean.TRUE.equals(n.getLida()))
                .toList();
    }

    /**
     * A massa tem de passar na mesma conferência que o banco de produção.
     *
     * <p>Antes este teste somava o extrato à mão, com uma regrinha própria
     * ("saque é negativo, o resto é positivo"). Isso funcionava quando havia
     * dois tipos de lançamento, e deixaria de valer no primeiro tipo novo — que
     * é exatamente o que aconteceu: reserva e liberação movem dinheiro entre os
     * bolsos da mesma carteira e pagamento_enviado sai do bloqueado.
     *
     * <p>Agora a conferência é a do próprio sistema
     * ({@link ConsistenciaService#verificarConsistencia()}), o que testa duas
     * coisas de uma vez: que a massa é coerente e que a conferência funciona
     * sobre dados de verdade. Se a massa passar a inventar saldo, isto falha —
     * e falha dizendo qual conta e por quanto.
     */
    @Test
    @DisplayName("a massa fecha nas tres invariantes do ledger")
    void massaFechaNasInvariantes() {
        massa.resetar();

        // So as contas da massa: este mesmo arquivo grava, de proposito, uma
        // conta "real" com saldo sem recarga de origem — dado que o ledger
        // nunca criaria e que o reset nao pode tocar. Ela nao e assunto desta
        // invariante, e conferir o banco inteiro faria o resultado depender da
        // ordem dos metodos.
        consistencia.verificarConsistencia(idsDaMassa()).exigirConsistente();

        // E a história que a massa conta precisa ter todos os capítulos: sem
        // recarga não há origem para o dinheiro, sem reserva não há lastro, sem
        // liberação a demonstração nunca mostra dinheiro voltando.
        assertThat(tiposDaMassa())
                .contains(TipoTransacao.RECARGA, TipoTransacao.RESERVA,
                          TipoTransacao.PAGAMENTO_ENVIADO, TipoTransacao.PAGAMENTO_RECEBIDO,
                          TipoTransacao.LIBERACAO_RESERVA, TipoTransacao.SAQUE);

        for (Usuario u : contasDaMassa()) {
            Carteira c = carteiraRepo.findByUsuarioId(u.getId()).orElseThrow();
            assertThat(c.getSaldoDisponivel().signum())
                    .as("disponivel de %s", u.getEmail()).isNotNegative();
            assertThat(c.getSaldoBloqueado().signum())
                    .as("bloqueado de %s", u.getEmail()).isNotNegative();
        }
    }

    /**
     * A DRE (RF13) tem os dois casos para mostrar, nas duas contas que a
     * documentação aponta: o Carlos (entregador) e a Cláudia (lojista) fecham
     * o MÊS PASSADO com lucro e o MÊS RETRASADO com prejuízo.
     *
     * <p>A massa é datada a partir de hoje, então o teste pergunta pelos meses
     * do calendário relativos a hoje — e os valores foram escolhidos para a
     * resposta não depender de quantas semanas o mês teve: a manutenção de R$
     * 420 do Carlos é maior do que o melhor mês dele, e a taxa da promoção da
     * Cláudia é menor do que o turno mais barato dela.
     */
    @Test
    @DisplayName("resultado: Carlos e Cláudia têm o mês passado com lucro e o retrasado com prejuízo")
    void mesesDeLucroEDePrejuizo() {
        massa.resetar();
        java.time.YearMonth passado = java.time.YearMonth.now().minusMonths(1);
        java.time.YearMonth retrasado = java.time.YearMonth.now().minusMonths(2);
        Long carlos = id("motoboy@teste.com");
        Long claudia = id("claudia@teste.com");

        // ── Carlos, mês passado: um turno por semana paga as contas. ──────
        com.motoshift.dto.DreResponse lucroDoCarlos = dre.dre(carlos, "motoboy",
                passado.atDay(1), passado.atEndOfMonth());
        assertThat(lucroDoCarlos.situacao()).isEqualTo("lucro");
        assertThat(lucroDoCarlos.resultado()).isPositive();
        int turnosDoCarlos = (Integer) lucroDoCarlos.indicadores().get("turnosPagos");
        assertThat(turnosDoCarlos).isGreaterThanOrEqualTo(3);
        assertThat(linhaDaDre(lucroDoCarlos, "das_mei")).isEqualByComparingTo("86.05");
        assertThat(linhaDaDre(lucroDoCarlos, "celular_internet")).isEqualByComparingTo("35.00");
        assertThat(linhaDaDre(lucroDoCarlos, "seguro")).isEqualByComparingTo("32.00");
        assertThat(linhaDaDre(lucroDoCarlos, "parcela_ou_aluguel_veiculo")).isEqualByComparingTo("95.00");
        // Combustível por turno, com os km — é de onde sai o custo por km.
        assertThat(linhaDaDre(lucroDoCarlos, "combustivel"))
                .isEqualByComparingTo(new BigDecimal("7.50").multiply(BigDecimal.valueOf(turnosDoCarlos)));
        assertThat(linhaDaDre(lucroDoCarlos, "manutencao")).isEqualByComparingTo("0.00");
        assertThat((BigDecimal) lucroDoCarlos.indicadores().get("custoPorKm")).isEqualByComparingTo("0.18");
        assertThat(lucroDoCarlos.indicadores().get("pontoDeEquilibrioTurnos")).isNotNull();

        // ── Carlos, mês retrasado: a manutenção custou mais do que o mês rendeu. ──
        com.motoshift.dto.DreResponse prejuizoDoCarlos = dre.dre(carlos, "motoboy",
                retrasado.atDay(1), retrasado.atEndOfMonth());
        assertThat(prejuizoDoCarlos.situacao()).isEqualTo("prejuizo");
        assertThat(prejuizoDoCarlos.resultado()).isNegative();
        assertThat(linhaDaDre(prejuizoDoCarlos, "manutencao")).isEqualByComparingTo("420.00");
        assertThat(linhaDaDre(prejuizoDoCarlos, "receita_bruta")).isPositive();

        // ── Cláudia, mês passado: as taxas cobradas cobrem os entregadores. ──
        com.motoshift.dto.DreResponse lucroDaClaudia = dre.dre(claudia, "lojista",
                passado.atDay(1), passado.atEndOfMonth());
        assertThat(lucroDaClaudia.situacao()).isEqualTo("lucro");
        assertThat(linhaDaDre(lucroDaClaudia, "receita_de_entregas"))
                .isGreaterThan(linhaDaDre(lucroDaClaudia, "custo_dos_entregadores"));
        assertThat(linhaDaDre(lucroDaClaudia, "entrega_fora_do_app")).isEqualByComparingTo("45.00");
        assertThat(linhaDaDre(lucroDaClaudia, "outra_despesa_entrega")).isEqualByComparingTo("60.00");

        // ── Cláudia, mês retrasado: a promoção de frete grátis. ───────────
        com.motoshift.dto.DreResponse prejuizoDaClaudia = dre.dre(claudia, "lojista",
                retrasado.atDay(1), retrasado.atEndOfMonth());
        assertThat(prejuizoDaClaudia.situacao()).isEqualTo("prejuizo");
        assertThat(linhaDaDre(prejuizoDaClaudia, "receita_de_entregas")).isPositive()
                .isLessThan(linhaDaDre(prejuizoDaClaudia, "custo_dos_entregadores"));

        // Quem não informou nada continua com a DRE só do extrato.
        assertThat(dre.dre(id("ricardo@teste.com"), "motoboy", passado.atDay(1), passado.atEndOfMonth())
                .lancamentosManuais()).isZero();

        // E nada disso passou pelo ledger: as invariantes seguem fechando.
        consistencia.verificarConsistencia(idsDaMassa()).exigirConsistente();
    }

    private static BigDecimal linhaDaDre(com.motoshift.dto.DreResponse r, String chave) {
        return r.linhas().stream().filter(l -> l.chave().equals(chave)).findFirst()
                .orElseThrow(() -> new AssertionError("sem a linha " + chave)).valor();
    }

    /**
     * As oito contas na mesma cidade da massa inteira. {@code lojista@teste.com}
     * e {@code motoboy@teste.com} eram de São Paulo, com todos os turnos em
     * Curitiba: na demonstração, o "perto de mim" e o ponto inicial do mapa
     * delas ficavam a 340 km de tudo.
     */
    @Test
    @DisplayName("todas as contas em Curitiba; toda loja com ponto no mapa; o turno parte da loja")
    void tudoEmCuritibaEAPartirDaLoja() {
        massa.resetar();

        for (Usuario u : contasDaMassa()) {
            assertThat(u.getCidade()).as("cidade de %s", u.getEmail()).isEqualTo("Curitiba");
            assertThat(u.getEstado()).as("UF de %s", u.getEmail()).isEqualTo("PR");
            if ("lojista".equals(u.getTipo())) {
                assertThat(com.motoshift.util.GeoUtils.distanciaKm(
                                -25.4284, -49.2733, u.getLatitude(), u.getLongitude()))
                        .as("ponto da loja de %s, a partir do centro de Curitiba", u.getEmail())
                        .isNotNull()
                        .isLessThan(10.0);
            } else {
                assertThat(u.getLatitude()).as("entregador não tem loja").isNull();
            }
        }

        Map<Long, Usuario> lojas = contasDaMassa().stream()
                .filter(u -> "lojista".equals(u.getTipo()))
                .collect(Collectors.toMap(Usuario::getId, u -> u));
        for (Turno t : turnosDaMassa()) {
            Usuario loja = lojas.get(t.getLojistId());
            assertThat(t.getLatitude()).as("pino de %s", t.getTitulo()).isEqualTo(loja.getLatitude());
            assertThat(t.getLongitude()).as("pino de %s", t.getTitulo()).isEqualTo(loja.getLongitude());
            assertThat(t.getRegiao()).as("região de %s", t.getTitulo()).endsWith("Curitiba");
        }

        // Mesmo e-mail e mesma senha de antes.
        assertThat(usuarioRepo.findByEmail("lojista@teste.com")).isPresent();
        assertThat(usuarioRepo.findByEmail("motoboy@teste.com")).isPresent();
    }

    private List<Long> idsDaMassa() {
        return contasDaMassa().stream().map(Usuario::getId).collect(Collectors.toList());
    }

    private java.util.Set<TipoTransacao> tiposDaMassa() {
        java.util.Set<Long> ids = contasDaMassa().stream()
                .map(Usuario::getId).collect(Collectors.toSet());
        return transacaoRepo.findAll().stream()
                .filter(t -> ids.contains(t.getUsuarioId()))
                .map(Transacao::getTipo)
                .collect(Collectors.toSet());
    }

    // ── Apoio ────────────────────────────────────────────────────────────────

    /** O estado observável da massa, sem ids nem carimbos de hora. */
    private record Estado(Map<String, Long> contagem, List<String> contas, List<String> turnos,
                          List<String> extrato, List<String> carteiras) {}

    private Estado estado() {
        List<Usuario> contas = contasDaMassa();
        Map<Long, String> email = contas.stream()
                .collect(Collectors.toMap(Usuario::getId, Usuario::getEmail));
        Function<Long, String> quem = id -> id == null ? "-" : email.getOrDefault(id, "?");

        return new Estado(
                massa.contarEscopo(),
                contas.stream().map(Usuario::getEmail).sorted().toList(),
                turnoRepo.findAll().stream()
                        .filter(t -> email.containsKey(t.getLojistId()))
                        .map(t -> String.join("|", t.getTitulo(), t.getStatus().getValor(),
                                String.valueOf(t.getPagamentoStatus()), quem.apply(t.getLojistId()),
                                quem.apply(t.getMotoboyId()), t.getValorEstimado().toPlainString()))
                        .sorted().toList(),
                transacaoRepo.findAll().stream()
                        .filter(t -> email.containsKey(t.getUsuarioId()))
                        .map(t -> String.join("|", quem.apply(t.getUsuarioId()), t.getTipo().getValor(),
                                t.getStatus().getValor(), t.getValor().stripTrailingZeros().toPlainString()))
                        .sorted().toList(),
                carteiraRepo.findAll().stream()
                        .filter(c -> email.containsKey(c.getUsuarioId()))
                        .map(c -> quem.apply(c.getUsuarioId()) + "|"
                                + c.getSaldoDisponivel().stripTrailingZeros().toPlainString()
                                + "|" + c.getChavePix())
                        .sorted().toList());
    }

    private List<Turno> turnosDaMassa() {
        Set<Long> ids = Set.copyOf(idsDaMassa());
        return turnoRepo.findAll().stream()
                .filter(t -> ids.contains(t.getLojistId()))
                .toList();
    }

    private Long id(String email) {
        return usuarioRepo.findByEmail(email).orElseThrow().getId();
    }

    /** Os tipos que o backend gera hoje — ver o comentário de Notificacao. */
    private static final Set<String> TIPOS_DE_NOTIFICACAO = Set.of(
            "turno_aceito", "turno_lotado", "turno_vencendo", "turno_expirado", "turno_cancelado",
            "turno_pendente_finalizacao", "avaliacao_pendente", "pagamento_confirmado",
            "nota_fiscal_emitida", "nota_fiscal_cancelada",
            "entregador_chegou", "entregador_saiu", "gorjeta_recebida", "turno_de_favorito",
            "turno_lembrete", "entregador_desistiu", "turno_falta");

    /** As tags do app (lib/models/tags_de_avaliacao.dart), por papel de quem é avaliado. */
    private static final Set<String> TAGS_DO_ENTREGADOR = Set.of(
            "Pontual", "Cuidado com a carga", "Educado", "Conhece a região", "Boa comunicação");
    private static final Set<String> TAGS_DA_LOJA = Set.of(
            "Pedidos prontos no horário", "Carga bem embalada", "Endereços corretos",
            "Boa comunicação", "Valor justo");

    private List<Usuario> contasDaMassa() {
        return usuarioRepo.findAll().stream()
                .filter(u -> u.getEmail().endsWith(MassaDemonstracao.SUFIXO_EMAIL))
                .toList();
    }

    private Usuario usuarioReal(String nome, String email, String tipo) {
        Usuario u = new Usuario();
        u.setNome(nome);
        // Sufixo unico por execucao: o banco do contexto e compartilhado.
        u.setEmail(email.replace("@", "+" + System.nanoTime() + "@"));
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        u.setSenha("$2a$10$naoimportaparaestetesteaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        return usuarioRepo.save(u);
    }
}
