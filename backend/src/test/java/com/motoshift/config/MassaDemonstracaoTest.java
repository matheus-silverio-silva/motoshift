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
import com.motoshift.repository.AvaliacaoRepository;
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
 * O reset leve da massa de demonstração, contra o banco.
 *
 * As chaves estrangeiras não existem no H2; a mesma operação roda sobre o
 * PostgreSQL com as FKs da V11 em SchemaPostgresTest.
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
        Set<Long> ids = contas.stream().map(Usuario::getId).collect(Collectors.toSet());
        List<Turno> turnos = turnoRepo.findAll().stream()
                .filter(t -> ids.contains(t.getLojistId()))
                .toList();

        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.ABERTO)
                .hasSize(5)
                .allSatisfy(t -> assertThat(t.getDataInicio()).isAfter(agora));

        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.ACEITO)
                .hasSize(2)
                .anySatisfy(t -> {
                    // em andamento: comecou e ainda nao terminou
                    assertThat(t.getDataInicio()).isBefore(agora);
                    assertThat(t.getDataFim()).isAfter(agora);
                })
                .anySatisfy(t -> assertThat(t.getDataInicio()).isAfter(agora));

        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.FINALIZADO)
                .hasSize(11)
                .allSatisfy(t -> assertThat(t.getDataFim()).isBefore(agora));

        // Dois cancelados, um deles tardio pela regra do ScoreService
        // (atualizado a menos de 1h do inicio) — e o tardio e do Thiago.
        Long thiago = usuarioRepo.findByEmail("thiago@teste.com").orElseThrow().getId();
        assertThat(turnos).filteredOn(t -> t.getStatus() == StatusTurno.CANCELADO)
                .hasSize(2)
                .anySatisfy(t -> {
                    assertThat(t.getMotoboyId()).isEqualTo(thiago);
                    assertThat(t.getAtualizadoEm()).isAfter(t.getDataInicio().minusHours(1));
                });

        assertThat(contas).filteredOn(u -> "motoboy".equals(u.getTipo()))
                .allSatisfy(u -> assertThat(u.getCnhValidade()).isAfter(hoje));
        assertThat(contas)
                .allSatisfy(u -> assertThat(u.getDataNascimento()).isBefore(hoje.minusYears(18)));

        assertThat(transacaoRepo.findAll()).filteredOn(t -> ids.contains(t.getUsuarioId()))
                .isNotEmpty()
                .allSatisfy(t -> assertThat(t.getCriadoEm()).isBeforeOrEqualTo(agora));

        Long claudia = usuarioRepo.findByEmail("claudia@teste.com").orElseThrow().getId();
        assertThat(notificacaoRepo.findTop50ByUsuarioIdOrderByCriadoEmDesc(claudia)).isNotEmpty();
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
