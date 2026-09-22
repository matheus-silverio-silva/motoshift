package com.motoshift.service;

import com.motoshift.dto.CobrancaResponse;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.TipoCobranca;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.gateway.GatewayPagamentoSimulado;
import com.motoshift.service.ledger.ConsistenciaService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * As duas portas por onde o dinheiro entra e sai da plataforma.
 *
 * <p>O que precisa ser provado aqui não é que o gateway funciona — ele é
 * simulado —, é que o MotoShift reage direito ao que vem de fora: a recarga só
 * vira saldo quando alguém confirma, o aviso repetido credita uma vez só, e um
 * saque recusado depois do débito é desfeito sem quebrar nenhuma invariante.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class CobrancaServiceTest {

    @Autowired private CobrancaService cobrancas;
    @Autowired private CarteiraService carteiras;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    private Usuario usuario;

    @BeforeEach
    void conta() {
        Usuario u = new Usuario();
        u.setNome("Entregador de teste");
        u.setEmail("cobranca-" + System.nanoTime() + "@ledger.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo("motoboy");
        usuario = usuarioRepo.save(u);
    }

    private BigDecimal disponivel() {
        return carteiraRepo.findByUsuarioId(usuario.getId())
                .map(c -> c.getSaldoDisponivel())
                .orElse(BigDecimal.ZERO);
    }

    private List<Transacao> extrato() {
        return transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(usuario.getId());
    }

    /** Recarrega e confirma, que é como o dinheiro entra de verdade. */
    private void comSaldo(String valor) {
        CobrancaResponse r = cobrancas.criarRecarga(usuario.getId(), new BigDecimal(valor), null);
        cobrancas.confirmarRecarga(usuario.getId(), r.getId());
    }

    // -- Recarga -------------------------------------------------------------

    @Test
    @DisplayName("criar a recarga não credita nada — ninguém pagou ainda")
    void criarRecarga_naoCreditaSaldo() {
        CobrancaResponse r = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("500.00"), null);

        assertThat(r.getStatus()).isEqualTo(StatusCobranca.PENDENTE);
        assertThat(r.getTipo()).isEqualTo(TipoCobranca.RECARGA);
        assertThat(r.getCodigoPix()).isNotBlank().contains("BR.GOV.BCB.PIX");
        assertThat(disponivel()).isEqualByComparingTo("0.00");
        assertThat(extrato()).isEmpty();
    }

    @Test
    @DisplayName("confirmar credita o valor e conclui a cobrança")
    void confirmarRecarga_creditaSaldo() {
        CobrancaResponse r = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("500.00"), null);

        CobrancaResponse confirmada = cobrancas.confirmarRecarga(usuario.getId(), r.getId());

        assertThat(confirmada.getStatus()).isEqualTo(StatusCobranca.CONCLUIDO);
        assertThat(confirmada.getConcluidaEm()).isNotNull();
        assertThat(disponivel()).isEqualByComparingTo("500.00");
        assertThat(extrato()).singleElement()
                .satisfies(t -> assertThat(t.getTipo()).isEqualTo(TipoTransacao.RECARGA));
    }

    @Test
    @DisplayName("confirmar a mesma recarga duas vezes credita uma vez")
    void confirmarRecarga_duasVezes_creditaUmaVez() {
        CobrancaResponse r = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("300.00"), null);

        cobrancas.confirmarRecarga(usuario.getId(), r.getId());
        cobrancas.confirmarRecarga(usuario.getId(), r.getId());

        assertThat(disponivel()).isEqualByComparingTo("300.00");
        assertThat(extrato()).hasSize(1);
    }

    @Test
    @DisplayName("com Idempotency-Key, repetir o pedido devolve a mesma cobrança")
    void criarRecarga_mesmaChave_mesmaCobranca() {
        CobrancaResponse a = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("100.00"), "tela-123");
        CobrancaResponse b = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("100.00"), "tela-123");

        assertThat(b.getId()).isEqualTo(a.getId());
        assertThat(b.getCodigoPix()).isEqualTo(a.getCodigoPix());
    }

    @Test
    @DisplayName("sem Idempotency-Key, duas recargas iguais são dois pedidos legítimos")
    void criarRecarga_semChave_saoDoisPedidos() {
        CobrancaResponse a = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("100.00"), null);
        CobrancaResponse b = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("100.00"), null);

        assertThat(b.getId()).isNotEqualTo(a.getId());
    }

    @Test
    @DisplayName("a cobrança de outra pessoa responde 404, não 403")
    void confirmarRecarga_deOutro_naoRevelaQueExiste() {
        CobrancaResponse r = cobrancas.criarRecarga(usuario.getId(), new BigDecimal("100.00"), null);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> cobrancas.confirmarRecarga(usuario.getId() + 9_999, r.getId()))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(404));
    }

    @Test
    @DisplayName("valor zero, negativo ou acima do teto é recusado")
    void criarRecarga_valorInvalido_recusa() {
        for (String valor : List.of("0.00", "-10.00", "10000.01")) {
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> cobrancas.criarRecarga(
                            usuario.getId(), new BigDecimal(valor), null))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));
        }
    }

    // -- Saque ---------------------------------------------------------------

    @Test
    @DisplayName("saque aprovado debita o disponível e conclui a cobrança")
    void sacar_aprovado_debita() {
        comSaldo("500.00");
        carteiras.atualizarPix(usuario.getId(), "entregador@pix.com");

        CobrancaResponse saque = cobrancas.sacar(usuario.getId(), new BigDecimal("200.00"), null);

        assertThat(saque.getStatus()).isEqualTo(StatusCobranca.CONCLUIDO);
        assertThat(disponivel()).isEqualByComparingTo("300.00");
        // So esta conta: o banco de teste e compartilhado, e outras classes
        // gravam nele saldo que nao veio do ledger. Ver o Javadoc do metodo.
        consistencia.verificarConsistencia(List.of(usuario.getId())).exigirConsistente();
    }

    @Test
    @DisplayName("saque recusado pelo gateway é estornado, e o débito continua no extrato")
    void sacar_recusado_estorna() {
        comSaldo("500.00");
        // A chave com o marcador é o gancho determinístico do gateway simulado.
        carteiras.atualizarPix(usuario.getId(),
                GatewayPagamentoSimulado.MARCADOR_DE_RECUSA + "@pix.com");

        CobrancaResponse saque = cobrancas.sacar(usuario.getId(), new BigDecimal("200.00"), null);

        assertThat(saque.getStatus()).isEqualTo(StatusCobranca.FALHOU);
        assertThat(disponivel()).isEqualByComparingTo("500.00");

        // Duas linhas, não zero: o débito aconteceu e foi desfeito. Apagar o
        // débito seria reescrever o passado.
        assertThat(extrato()).extracting(Transacao::getTipo)
                .containsExactlyInAnyOrder(TipoTransacao.RECARGA,
                        TipoTransacao.SAQUE, TipoTransacao.ESTORNO);
        // So esta conta: o banco de teste e compartilhado, e outras classes
        // gravam nele saldo que nao veio do ledger. Ver o Javadoc do metodo.
        consistencia.verificarConsistencia(List.of(usuario.getId())).exigirConsistente();
    }

    @Test
    @DisplayName("saque abaixo de R$ 20,00 é recusado")
    void sacar_abaixoDoMinimo_recusa() {
        comSaldo("500.00");
        carteiras.atualizarPix(usuario.getId(), "entregador@pix.com");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> cobrancas.sacar(usuario.getId(), new BigDecimal("19.99"), null))
                .satisfies(e -> {
                    assertThat(e.getStatusCode().value()).isEqualTo(400);
                    assertThat(e.getReason()).contains("R$ 20,00");
                });
    }

    @Test
    @DisplayName("saque sem chave Pix cadastrada é recusado")
    void sacar_semChavePix_recusa() {
        comSaldo("500.00");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> cobrancas.sacar(usuario.getId(), new BigDecimal("50.00"), null))
                .satisfies(e -> assertThat(e.getReason()).contains("chave Pix"));
    }

    @Test
    @DisplayName("saque maior que o disponível responde 422 com o saldo real")
    void sacar_semSaldo_recusa422() {
        comSaldo("50.00");
        carteiras.atualizarPix(usuario.getId(), "entregador@pix.com");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> cobrancas.sacar(usuario.getId(), new BigDecimal("80.00"), null))
                .satisfies(e -> {
                    assertThat(e.getStatusCode().value()).isEqualTo(422);
                    assertThat(e.getReason()).contains("50,00").contains("80,00");
                });
    }

    @Test
    @DisplayName("o bloqueado não é sacável: só o disponível conta")
    void sacar_naoAlcancaOBloqueado() {
        comSaldo("500.00");
        carteiras.atualizarPix(usuario.getId(), "entregador@pix.com");
        // Simula dinheiro comprometido com um turno publicado.
        carteiraRepo.findByUsuarioId(usuario.getId()).ifPresent(c -> {
            c.setSaldoDisponivel(new BigDecimal("100.00"));
            c.setSaldoBloqueado(new BigDecimal("400.00"));
            carteiraRepo.save(c);
        });

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> cobrancas.sacar(usuario.getId(), new BigDecimal("300.00"), null))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(422));
    }

    @Test
    @DisplayName("com Idempotency-Key, o mesmo saque repetido debita uma vez")
    void sacar_mesmaChave_debitaUmaVez() {
        comSaldo("500.00");
        carteiras.atualizarPix(usuario.getId(), "entregador@pix.com");

        cobrancas.sacar(usuario.getId(), new BigDecimal("100.00"), "botao-1");
        cobrancas.sacar(usuario.getId(), new BigDecimal("100.00"), "botao-1");

        assertThat(disponivel()).isEqualByComparingTo("400.00");
        assertThat(extrato()).filteredOn(t -> t.getTipo() == TipoTransacao.SAQUE).hasSize(1);
    }
}
