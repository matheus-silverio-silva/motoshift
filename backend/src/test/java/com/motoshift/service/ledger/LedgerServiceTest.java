package com.motoshift.service.ledger;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * O ledger contra um banco de verdade.
 *
 * <p>Deliberadamente NAO e um teste de mock. O que precisa ser provado aqui —
 * que a chave de idempotencia impede o segundo lancamento, que o saldo nunca
 * fica negativo, que os dois lados de uma transferencia sao gravados juntos —
 * depende do indice unico e da transacao, e um mock confirmaria apenas que o
 * codigo chama os metodos que o proprio codigo decidiu chamar.
 *
 * <p>{@code @DataJpaTest} ja abre uma transacao por teste, o que satisfaz a
 * propagacao MANDATORY do {@link LedgerService} — e de quebra prova que ela e
 * satisfeita por um chamador normal.
 */
@DataJpaTest
@ActiveProfiles("test")
@Import({LedgerService.class, ConsistenciaService.class})
class LedgerServiceTest {

    private static final Long LOJISTA = 9_001L;
    private static final Long ENTREGADOR = 9_002L;

    @Autowired private LedgerService ledger;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;

    private static BigDecimal reais(String v) {
        return new BigDecimal(v);
    }

    /** Dinheiro entra na plataforma do unico jeito legitimo: recarga. */
    private void recarregar(Long usuario, String valor, long cobrancaId) {
        ledger.aplicar(Movimento.recarga(usuario, reais(valor), cobrancaId));
    }

    private Carteira carteira(Long usuario) {
        return carteiraRepo.findByUsuarioId(usuario).orElseThrow();
    }

    @BeforeEach
    void limpar() {
        transacaoRepo.deleteAll();
        carteiraRepo.deleteAll();
    }

    // -- Idempotencia --------------------------------------------------------

    @Nested
    @DisplayName("idempotência")
    class Idempotencia {

        @Test
        @DisplayName("o mesmo movimento aplicado duas vezes credita uma vez")
        void mesmaChave_creditaUmaVez() {
            recarregar(LOJISTA, "500.00", 1L);
            recarregar(LOJISTA, "500.00", 1L);

            assertThat(carteira(LOJISTA).getSaldoDisponivel()).isEqualByComparingTo("500.00");
            assertThat(transacaoRepo.findAll()).hasSize(1);
        }

        @Test
        @DisplayName("a repetição devolve o lançamento original, não um novo")
        void mesmaChave_devolveOMesmoLancamento() {
            Transacao primeira = ledger.aplicar(Movimento.recarga(LOJISTA, reais("100.00"), 7L));
            Transacao segunda = ledger.aplicar(Movimento.recarga(LOJISTA, reais("100.00"), 7L));

            assertThat(segunda.getId()).isEqualTo(primeira.getId());
        }

        @Test
        @DisplayName("cobranças diferentes são operações diferentes, mesmo com o mesmo valor")
        void chavesDiferentes_creditamDuasVezes() {
            recarregar(LOJISTA, "100.00", 1L);
            recarregar(LOJISTA, "100.00", 2L);

            assertThat(carteira(LOJISTA).getSaldoDisponivel()).isEqualByComparingTo("200.00");
        }
    }

    // -- Invariante (a) ------------------------------------------------------

    @Nested
    @DisplayName("saldo nunca fica negativo")
    class SaldoNaoNegativo {

        @Test
        @DisplayName("saque maior que o disponível é recusado com 422 dizendo quanto falta")
        void saqueSemSaldo_recusa422() {
            recarregar(ENTREGADOR, "50.00", 1L);

            assertThatThrownBy(() -> ledger.aplicar(
                    Movimento.saque(ENTREGADOR, reais("80.00"), "pix@teste.com", 2L)))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("422")
                    .hasMessageContaining("30,00");

            assertThat(carteira(ENTREGADOR).getSaldoDisponivel()).isEqualByComparingTo("50.00");
        }

        @Test
        @DisplayName("o bloqueado também tem chão: liberar mais do que foi reservado estoura")
        void liberacaoMaiorQueReserva_estoura() {
            recarregar(LOJISTA, "300.00", 1L);
            ledger.aplicar(Movimento.reserva(LOJISTA, reais("100.00"), 40L, "Turno"));

            assertThatThrownBy(() -> ledger.aplicar(Movimento.liberacaoDeReserva(
                    LOJISTA, reais("250.00"), 41L, "Liberação torta",
                    Movimento.MotivoLiberacao.CANCELAMENTO)))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("Liberação maior que a reserva");
        }
    }

    // -- Os dois bolsos ------------------------------------------------------

    @Nested
    @DisplayName("disponível e bloqueado")
    class Bolsos {

        @Test
        @DisplayName("reserva tira do disponível e põe no bloqueado, sem mudar o patrimônio")
        void reserva_movePreservandoOTotal() {
            recarregar(LOJISTA, "500.00", 1L);
            ledger.aplicar(Movimento.reserva(LOJISTA, reais("360.00"), 42L, "Turno Noite"));

            Carteira c = carteira(LOJISTA);
            assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("140.00");
            assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("360.00");
            assertThat(c.getSaldoTotal()).isEqualByComparingTo("500.00");
        }

        @Test
        @DisplayName("reserva é débito na tela, mesmo sem o patrimônio mudar")
        void reserva_naturezaEDebito() {
            recarregar(LOJISTA, "500.00", 1L);
            Transacao tx = ledger.aplicar(Movimento.reserva(LOJISTA, reais("360.00"), 42L, "Turno"));

            assertThat(tx.getNatureza()).isEqualTo(NaturezaTransacao.DEBITO);
            assertThat(tx.getTipo()).isEqualTo(TipoTransacao.RESERVA);
        }

        @Test
        @DisplayName("liberar devolve exatamente o que a reserva tinha tirado")
        void liberacao_desfazAReserva() {
            recarregar(LOJISTA, "500.00", 1L);
            ledger.aplicar(Movimento.reserva(LOJISTA, reais("360.00"), 42L, "Turno"));
            ledger.aplicar(Movimento.liberacaoDeReserva(LOJISTA, reais("360.00"), 42L,
                    "Turno cancelado", Movimento.MotivoLiberacao.CANCELAMENTO));

            Carteira c = carteira(LOJISTA);
            assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("500.00");
            assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("0.00");
        }
    }

    // -- Snapshot ------------------------------------------------------------

    @Test
    @DisplayName("cada lançamento guarda a foto dos dois saldos logo depois dele")
    void lancamento_guardaSnapshotDoSaldo() {
        recarregar(LOJISTA, "500.00", 1L);
        Transacao reserva = ledger.aplicar(
                Movimento.reserva(LOJISTA, reais("120.00"), 42L, "Turno"));

        assertThat(reserva.getSaldoDisponivelApos()).isEqualByComparingTo("380.00");
        assertThat(reserva.getSaldoBloqueadoApos()).isEqualByComparingTo("120.00");
    }

    // -- Transferencia -------------------------------------------------------

    @Nested
    @DisplayName("transferência")
    class Transferencias {

        @Test
        @DisplayName("os dois lados nascem com o mesmo operacaoId")
        void doisLados_mesmaOperacao() {
            recarregar(LOJISTA, "500.00", 1L);
            ledger.aplicar(Movimento.reserva(LOJISTA, reais("120.00"), 42L, "Turno"));

            LedgerService.Transferencia t = ledger.transferir(
                    Movimento.pagamentoEnviado(LOJISTA, ENTREGADOR, reais("120.00"), 42L,
                            "Turno", "liquidacao:inscricao:5:debito"),
                    Movimento.pagamentoRecebido(ENTREGADOR, LOJISTA, reais("120.00"), 42L,
                            "Turno", "liquidacao:inscricao:5:credito"));

            assertThat(t.debito().getOperacaoId())
                    .isNotNull()
                    .isEqualTo(t.credito().getOperacaoId());
        }

        @Test
        @DisplayName("sai do bloqueado do lojista e entra no disponível do entregador")
        void liquidacao_saiDoBloqueadoEntraNoDisponivel() {
            recarregar(LOJISTA, "500.00", 1L);
            ledger.aplicar(Movimento.reserva(LOJISTA, reais("120.00"), 42L, "Turno"));

            ledger.transferir(
                    Movimento.pagamentoEnviado(LOJISTA, ENTREGADOR, reais("120.00"), 42L,
                            "Turno", "liquidacao:inscricao:5:debito"),
                    Movimento.pagamentoRecebido(ENTREGADOR, LOJISTA, reais("120.00"), 42L,
                            "Turno", "liquidacao:inscricao:5:credito"));

            assertThat(carteira(LOJISTA).getSaldoDisponivel()).isEqualByComparingTo("380.00");
            assertThat(carteira(LOJISTA).getSaldoBloqueado()).isEqualByComparingTo("0.00");
            assertThat(carteira(ENTREGADOR).getSaldoDisponivel()).isEqualByComparingTo("120.00");
        }

        @Test
        @DisplayName("liquidar duas vezes transfere uma vez")
        void liquidacaoRepetida_transfereUmaVez() {
            recarregar(LOJISTA, "500.00", 1L);
            ledger.aplicar(Movimento.reserva(LOJISTA, reais("120.00"), 42L, "Turno"));

            for (int i = 0; i < 2; i++) {
                ledger.transferir(
                        Movimento.pagamentoEnviado(LOJISTA, ENTREGADOR, reais("120.00"), 42L,
                                "Turno", "liquidacao:inscricao:5:debito"),
                        Movimento.pagamentoRecebido(ENTREGADOR, LOJISTA, reais("120.00"), 42L,
                                "Turno", "liquidacao:inscricao:5:credito"));
            }

            assertThat(carteira(ENTREGADOR).getSaldoDisponivel()).isEqualByComparingTo("120.00");
            assertThat(transacaoRepo.findAll()).hasSize(4); // recarga, reserva, débito, crédito
        }

        @Test
        @DisplayName("pernas de valor diferente criariam dinheiro e são recusadas")
        void transferenciaDesbalanceada_recusada() {
            assertThatThrownBy(() -> ledger.transferir(
                    Movimento.pagamentoEnviado(LOJISTA, ENTREGADOR, reais("120.00"), 42L,
                            "Turno", "a:debito"),
                    Movimento.pagamentoRecebido(ENTREGADOR, LOJISTA, reais("100.00"), 42L,
                            "Turno", "a:credito")))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("desbalanceada");
        }
    }

    // -- Recusas de entrada --------------------------------------------------

    @Test
    @DisplayName("valor zero ou negativo não é movimento — o sinal mora no tipo")
    void valorInvalido_recusado() {
        assertThatThrownBy(() -> Movimento.recarga(LOJISTA, BigDecimal.ZERO, 1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("O sinal esta no tipo");

        assertThatThrownBy(() -> Movimento.recarga(LOJISTA, reais("-10.00"), 1L))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("movimento sem chave de idempotência não existe")
    void semChave_recusado() {
        assertThatThrownBy(() -> new Movimento(LOJISTA, null, null,
                TipoTransacao.RECARGA, NaturezaTransacao.CREDITO,
                reais("10.00"), reais("10.00"), BigDecimal.ZERO, "sem chave", "  "))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("idempotencia");
    }

    @Test
    @DisplayName("todo lançamento do ledger nasce concluído — pendente é coisa do legado")
    void lancamento_nasceConcluido() {
        Transacao tx = ledger.aplicar(Movimento.recarga(LOJISTA, reais("10.00"), 1L));
        assertThat(tx.getStatus()).isEqualTo(StatusTransacao.CONCLUIDO);
    }

    // -- Invariantes ---------------------------------------------------------

    @Test
    @DisplayName("um ciclo completo mantém as três invariantes")
    void cicloCompleto_mantemInvariantes() {
        recarregar(LOJISTA, "500.00", 1L);
        ledger.aplicar(Movimento.reserva(LOJISTA, reais("240.00"), 42L, "Turno 2 vagas"));
        ledger.transferir(
                Movimento.pagamentoEnviado(LOJISTA, ENTREGADOR, reais("120.00"), 42L,
                        "Turno", "liquidacao:inscricao:5:debito"),
                Movimento.pagamentoRecebido(ENTREGADOR, LOJISTA, reais("120.00"), 42L,
                        "Turno", "liquidacao:inscricao:5:credito"));
        ledger.aplicar(Movimento.liberacaoDeReserva(LOJISTA, reais("120.00"), 42L,
                "Vaga não preenchida", Movimento.MotivoLiberacao.SOBRA));
        ledger.aplicar(Movimento.saque(ENTREGADOR, reais("100.00"), "pix@teste.com", 9L));

        consistencia.verificarConsistencia().exigirConsistente();

        // O dinheiro que entrou (500) menos o que saiu (100) esta nas carteiras.
        assertThat(carteira(LOJISTA).getSaldoTotal()).isEqualByComparingTo("380.00");
        assertThat(carteira(ENTREGADOR).getSaldoTotal()).isEqualByComparingTo("20.00");
    }

    @Test
    @DisplayName("saque recusado: o débito fica no extrato e o estorno devolve o valor")
    void saqueEstornado_somaZero() {
        recarregar(ENTREGADOR, "200.00", 1L);
        ledger.aplicar(Movimento.saque(ENTREGADOR, reais("50.00"), "pix@teste.com", 9L));
        ledger.aplicar(Movimento.estornoDeSaque(ENTREGADOR, reais("50.00"), 9L));

        assertThat(carteira(ENTREGADOR).getSaldoDisponivel()).isEqualByComparingTo("200.00");
        // As duas linhas continuam no extrato: o saque aconteceu de verdade.
        assertThat(transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(ENTREGADOR)).hasSize(3);
        consistencia.verificarConsistencia().exigirConsistente();
    }
}
