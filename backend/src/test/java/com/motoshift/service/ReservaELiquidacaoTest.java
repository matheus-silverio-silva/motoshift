package com.motoshift.service;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.service.ledger.LedgerService;
import com.motoshift.service.ledger.Movimento;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * O ciclo do dinheiro de um turno, do começo ao fim, contra um banco.
 *
 * <p>Substitui o {@code PagamentoSemLegadoTest}, que provava que a dupla
 * confirmação liquidava pela inscrição e não por uma rota paralela. A dupla
 * confirmação deixou de existir, mas a pergunta que aquele teste fazia
 * continua sendo a certa — <i>o dinheiro anda inteiro e por um caminho só?</i>
 * — e é ela que está aqui, agora sobre reserva e liquidação.
 *
 * <p>Com contexto de verdade porque o que importa é a transação completa:
 * turno publicado com lastro, inscrição paga, saldo movido nos dois lados e
 * nada sobrando bloqueado.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class ReservaELiquidacaoTest {

    @Autowired private TurnoService turnos;
    @Autowired private PagamentoTurnoService pagamentos;
    @Autowired private LedgerService ledger;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    private Usuario lojista;
    private Usuario entregador;
    private Usuario outroEntregador;

    @BeforeEach
    void contas() {
        lojista = conta("lojista");
        entregador = conta("motoboy");
        outroEntregador = conta("motoboy");
    }

    // -- Publicar ------------------------------------------------------------

    @Test
    @DisplayName("publicar reserva o custo total: o disponível cai e o bloqueado sobe")
    void publicar_reservaCustoTotal() {
        recarregar(lojista, "1000.00");

        Turno t = publicar("120.00", 3);

        Carteira c = carteira(lojista);
        assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("640.00");
        assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("360.00");
        assertThat(t.getStatus()).isEqualTo(StatusTurno.ABERTO);

        Transacao reserva = lancamento("reserva:turno:" + t.getId());
        assertThat(reserva.getTipo()).isEqualTo(TipoTransacao.RESERVA);
        assertThat(reserva.getValor()).isEqualByComparingTo("360.00");
    }

    @Test
    @DisplayName("publicar sem saldo é recusado com 422 dizendo quanto falta, e nada é reservado")
    void publicar_semSaldo_recusaENaoReserva() {
        recarregar(lojista, "200.00");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> publicar("120.00", 3))
                .satisfies(e -> {
                    assertThat(e.getStatusCode().value()).isEqualTo(422);
                    // 360 de custo, 200 em caixa, 160 de diferença: os três
                    // números, porque o lojista precisa saber quanto recarregar.
                    assertThat(e.getReason())
                            .contains("360,00")
                            .contains("200,00")
                            .contains("Faltam")
                            .contains("160,00");
                });

        // Nenhuma reserva, saldo intocado.
        //
        // O turno em si também não sobrevive em produção: publicar e reservar
        // estão na mesma transação, e a exceção a derruba inteira. Isso não dá
        // para afirmar aqui — o teste é @Transactional e compartilha a
        // transação com o serviço, então o rollback só aconteceria no fim do
        // método. O que este teste garante é o que importa para o saldo.
        // Filtrado por este lojista: o contexto sobe com a massa de
        // demonstração, que tem reservas legítimas de outras contas.
        assertThat(transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(lojista.getId()))
                .noneMatch(t -> t.getTipo() == TipoTransacao.RESERVA);
        assertThat(carteira(lojista).getSaldoDisponivel()).isEqualByComparingTo("200.00");
        assertThat(carteira(lojista).getSaldoBloqueado()).isEqualByComparingTo("0.00");
    }

    // -- Finalizar -----------------------------------------------------------

    @Test
    @DisplayName("3 vagas com 2 inscritos: 2 transferências, 1 liberação, bloqueado zerado")
    void finalizar_pagaInscritosEDevolveSobra() {
        recarregar(lojista, "1000.00");
        Turno t = publicar("120.00", 3);
        inscrever(t, entregador);
        inscrever(t, outroEntregador);

        turnos.finalizar(t.getId(), lojista.getId());

        // Os dois entregadores receberam.
        assertThat(carteira(entregador).getSaldoDisponivel()).isEqualByComparingTo("120.00");
        assertThat(carteira(outroEntregador).getSaldoDisponivel()).isEqualByComparingTo("120.00");

        // O lojista pagou 240 e recebeu 120 de volta; nada ficou preso.
        Carteira c = carteira(lojista);
        assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("0.00");
        assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("760.00");

        List<Transacao> doTurno = transacaoRepo.findByTurnoId(t.getId());
        assertThat(contarPorTipo(doTurno, TipoTransacao.PAGAMENTO_ENVIADO)).isEqualTo(2);
        assertThat(contarPorTipo(doTurno, TipoTransacao.PAGAMENTO_RECEBIDO)).isEqualTo(2);
        assertThat(contarPorTipo(doTurno, TipoTransacao.LIBERACAO_RESERVA)).isEqualTo(1);

        consistencia.verificarConsistencia().exigirConsistente();
    }

    @Test
    @DisplayName("os dois lados do pagamento nascem com o mesmo operacaoId")
    void finalizar_osDoisLadosCompartilhamAOperacao() {
        recarregar(lojista, "500.00");
        Turno t = publicar("120.00", 1);
        inscrever(t, entregador);

        turnos.finalizar(t.getId(), lojista.getId());

        Transacao enviado = umDoTipo(t, TipoTransacao.PAGAMENTO_ENVIADO);
        Transacao recebido = umDoTipo(t, TipoTransacao.PAGAMENTO_RECEBIDO);
        assertThat(enviado.getOperacaoId()).isNotNull().isEqualTo(recebido.getOperacaoId());
        assertThat(enviado.getContraparteId()).isEqualTo(entregador.getId());
        assertThat(recebido.getContraparteId()).isEqualTo(lojista.getId());
    }

    @Test
    @DisplayName("o entregador também pode finalizar — o dinheiro já era do turno, não de quem clicou")
    void finalizar_peloEntregador_pagaIgual() {
        recarregar(lojista, "500.00");
        Turno t = publicar("120.00", 1);
        inscrever(t, entregador);

        turnos.finalizar(t.getId(), entregador.getId());

        assertThat(carteira(entregador).getSaldoDisponivel()).isEqualByComparingTo("120.00");
        assertThat(carteira(lojista).getSaldoBloqueado()).isEqualByComparingTo("0.00");
    }

    @Test
    @DisplayName("finalizar duas vezes transfere uma vez")
    void finalizar_duasVezes_pagaUmaVez() {
        recarregar(lojista, "500.00");
        Turno t = publicar("120.00", 1);
        TurnoInscricao ins = inscrever(t, entregador);

        turnos.finalizar(t.getId(), lojista.getId());

        // A segunda chamada pela API é barrada pelo status do turno; aqui se
        // força a liquidação de novo, que é o caminho que um retry percorreria.
        pagamentos.liquidar(recarregarTurno(t), List.of(ins));

        assertThat(carteira(entregador).getSaldoDisponivel()).isEqualByComparingTo("120.00");
        assertThat(contarPorTipo(transacaoRepo.findByTurnoId(t.getId()),
                TipoTransacao.PAGAMENTO_RECEBIDO)).isEqualTo(1);
    }

    @Test
    @DisplayName("finalizar marca turno e inscrição como PAGO — não existe mais 'aguardando pagamento'")
    void finalizar_marcaComoPago() {
        recarregar(lojista, "500.00");
        Turno t = publicar("120.00", 1);
        inscrever(t, entregador);

        turnos.finalizar(t.getId(), lojista.getId());

        assertThat(recarregarTurno(t).getPagamentoStatus()).isEqualTo(StatusPagamento.PAGO);
        assertThat(inscricaoRepo.findByTurnoIdAndMotoboyId(t.getId(), entregador.getId())
                .orElseThrow().getPagamentoStatus()).isEqualTo(StatusPagamento.PAGO);
    }

    // -- Cancelar e expirar --------------------------------------------------

    @Test
    @DisplayName("cancelar devolve a reserva inteira, sem multa")
    void cancelar_devolveTudo() {
        recarregar(lojista, "1000.00");
        Turno t = publicar("120.00", 2);

        turnos.cancelar(t.getId(), lojista.getId());

        Carteira c = carteira(lojista);
        assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("1000.00");
        assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("0.00");
        assertThat(lancamento("liberacao:turno:" + t.getId() + ":cancelamento").getValor())
                .isEqualByComparingTo("240.00");
        consistencia.verificarConsistencia().exigirConsistente();
    }

    @Test
    @DisplayName("expirar devolve a reserva inteira")
    void expirar_devolveTudo() {
        recarregar(lojista, "1000.00");
        Turno t = publicar("110.00", 2);

        pagamentos.liberarReserva(t, Movimento.MotivoLiberacao.EXPIRACAO);

        Carteira c = carteira(lojista);
        assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("1000.00");
        assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("0.00");
        consistencia.verificarConsistencia().exigirConsistente();
    }

    @Test
    @DisplayName("liberar duas vezes devolve uma vez")
    void liberar_duasVezes_devolveUmaVez() {
        recarregar(lojista, "1000.00");
        Turno t = publicar("110.00", 2);

        pagamentos.liberarReserva(t, Movimento.MotivoLiberacao.EXPIRACAO);
        pagamentos.liberarReserva(t, Movimento.MotivoLiberacao.EXPIRACAO);

        assertThat(carteira(lojista).getSaldoDisponivel()).isEqualByComparingTo("1000.00");
    }

    // -- Turno anterior ao ledger --------------------------------------------

    @Test
    @DisplayName("turno publicado antes do ledger reserva na hora de liquidar, em vez de estourar")
    void turnoSemReserva_reservaNaHoraDeLiquidar() {
        recarregar(lojista, "500.00");

        // Gravado direto no repositório: é como estão no banco os turnos
        // publicados antes desta versão — sem nenhum lançamento de reserva.
        Turno t = new Turno();
        t.setLojistId(lojista.getId());
        t.setMotoboyId(entregador.getId());
        t.setTitulo("Turno anterior ao ledger");
        t.setDataInicio(LocalDateTime.now().minusHours(6));
        t.setDataFim(LocalDateTime.now().minusHours(2));
        t.setValorEstimado(new BigDecimal("120.00"));
        t.setVagas(1);
        t.setStatus(StatusTurno.ACEITO);
        t = turnoRepo.save(t);
        inscrever(t, entregador);

        turnos.finalizar(t.getId(), lojista.getId());

        assertThat(carteira(entregador).getSaldoDisponivel()).isEqualByComparingTo("120.00");
        assertThat(carteira(lojista).getSaldoDisponivel()).isEqualByComparingTo("380.00");
        assertThat(carteira(lojista).getSaldoBloqueado()).isEqualByComparingTo("0.00");
        consistencia.verificarConsistencia().exigirConsistente();
    }

    // -- Apoio ---------------------------------------------------------------

    private Usuario conta(String tipo) {
        Usuario u = new Usuario();
        u.setNome("Conta " + tipo);
        u.setEmail(tipo + "-" + System.nanoTime() + "@ledger.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }

    private void recarregar(Usuario u, String valor) {
        ledger.aplicar(Movimento.recarga(u.getId(), new BigDecimal(valor), System.nanoTime()));
    }

    private Turno publicar(String valor, int vagas) {
        com.motoshift.dto.TurnoRequest req = new com.motoshift.dto.TurnoRequest();
        req.setTitulo("Turno de teste");
        req.setDataInicio(LocalDateTime.now().plusHours(3));
        req.setDataFim(LocalDateTime.now().plusHours(7));
        req.setValorEstimado(new BigDecimal(valor));
        req.setVagas(vagas);
        return turnoRepo.findById(turnos.criar(req, lojista.getId()).getId()).orElseThrow();
    }

    private TurnoInscricao inscrever(Turno t, Usuario motoboy) {
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(t.getId());
        ins.setMotoboyId(motoboy.getId());
        ins.setStatus(StatusInscricao.ACEITO);
        ins = inscricaoRepo.save(ins);
        if (t.getMotoboyId() == null) {
            t.setMotoboyId(motoboy.getId());
            turnoRepo.save(t);
        }
        return ins;
    }

    private Turno recarregarTurno(Turno t) {
        return turnoRepo.findById(t.getId()).orElseThrow();
    }

    private Carteira carteira(Usuario u) {
        return carteiraRepo.findByUsuarioId(u.getId()).orElseThrow();
    }

    private Transacao lancamento(String chave) {
        return transacaoRepo.findByIdempotencyKey(chave).orElseThrow(
                () -> new AssertionError("nenhum lancamento com a chave " + chave));
    }

    private Transacao umDoTipo(Turno t, TipoTransacao tipo) {
        return transacaoRepo.findByTurnoId(t.getId()).stream()
                .filter(x -> x.getTipo() == tipo)
                .findFirst()
                .orElseThrow(() -> new AssertionError("nenhum lancamento " + tipo));
    }

    private static long contarPorTipo(List<Transacao> lancamentos, TipoTransacao tipo) {
        return lancamentos.stream().filter(t -> t.getTipo() == tipo).count();
    }
}
