package com.motoshift.service;

import com.motoshift.dto.GorjetaResponse;
import com.motoshift.dto.ResumoFinanceiroResponse;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.fiscal.TipoDocumento;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Gorjeta (V17): quem pode dar, a quem, quanto, uma vez só — e o ledger
 * fechando depois.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class GorjetaServiceTest {

    @Autowired private CenarioFinanceiro cenario;
    @Autowired private GorjetaService gorjetas;
    @Autowired private CarteiraService carteiras;
    @Autowired private ExtratoService extrato;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private TurnoService turnos;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;

    private Usuario loja;
    private Usuario ricardo;
    private Usuario lucas;
    private Turno turno;

    @BeforeEach
    void turnoPago() {
        loja = cenario.conta("lojista", "Cláudia Oliveira", "12.345.678/0001-90");
        loja.setNomeFantasia("Hamburgueria da Cláudia");
        loja = usuarioRepo.save(loja);
        ricardo = cenario.conta("motoboy", "Ricardo Souza", "12345678900");
        lucas = cenario.conta("motoboy", "Lucas Mendes", "98765432100");
        turno = cenario.turnoPago(loja.getId(), "100.00", ricardo.getId());
        // O turno consumiu a recarga inteira: a gorjeta sai de saldo novo.
        cenario.recarregar(loja.getId(), "30.00");
    }

    @Test
    @DisplayName("sai do disponível do lojista, entra no do entregador, os dois ligados ao turno")
    void daGorjeta() {
        BigDecimal lojaAntes = disponivel(loja);
        BigDecimal ricardoAntes = disponivel(ricardo);

        GorjetaResponse g = gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("10"));

        assertThat(g.valor()).isEqualByComparingTo("10.00");
        assertThat(disponivel(loja)).isEqualByComparingTo(lojaAntes.subtract(new BigDecimal("10")));
        assertThat(disponivel(ricardo)).isEqualByComparingTo(ricardoAntes.add(new BigDecimal("10")));

        Transacao enviada = doTurno(TipoTransacao.BONUS_ENVIADO);
        Transacao recebida = doTurno(TipoTransacao.BONUS);
        assertThat(enviada.getUsuarioId()).isEqualTo(loja.getId());
        assertThat(enviada.getContraparteId()).isEqualTo(ricardo.getId());
        assertThat(enviada.getNatureza()).isEqualTo(NaturezaTransacao.DEBITO);
        assertThat(recebida.getUsuarioId()).isEqualTo(ricardo.getId());
        assertThat(recebida.getNatureza()).isEqualTo(NaturezaTransacao.CREDITO);
        assertThat(enviada.getOperacaoId()).isEqualTo(recebida.getOperacaoId()).isNotNull();

        consistencia.verificarConsistencia(Set.of(loja.getId(), ricardo.getId())).exigirConsistente();
    }

    @Test
    @DisplayName("o entregador recebe \"Você recebeu uma gorjeta de R$ 10 da Hamburgueria da Cláudia\"")
    void notifica() {
        gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("10.00"));

        List<Notificacao> avisos = notificacaoRepo.findAll().stream()
                .filter(n -> n.getUsuarioId().equals(ricardo.getId())
                        && "gorjeta_recebida".equals(n.getTipo()))
                .toList();
        assertThat(avisos).hasSize(1);
        assertThat(avisos.get(0).getMensagem())
                .startsWith("Você recebeu uma gorjeta de R$ 10 da Hamburgueria da Cláudia");
        assertThat(avisos.get(0).getReferenciaTipo()).isEqualTo("carteira");
    }

    @Nested
    @DisplayName("uma por entregador por turno, idempotente")
    class Idempotencia {

        @Test
        @DisplayName("repetir a mesma gorjeta não cobra de novo nem avisa de novo")
        void repetir() {
            BigDecimal lojaAntes = disponivel(loja);
            GorjetaResponse primeira = gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("10"));
            GorjetaResponse segunda = gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("10.00"));

            assertThat(segunda.transacaoId()).isEqualTo(primeira.transacaoId());
            assertThat(disponivel(loja)).isEqualByComparingTo(lojaAntes.subtract(new BigDecimal("10")));
            assertThat(transacaoRepo.findByTurnoId(turno.getId()).stream()
                    .filter(t -> t.getTipo() == TipoTransacao.BONUS_ENVIADO)).hasSize(1);
            assertThat(notificacaoRepo.findAll().stream()
                    .filter(n -> "gorjeta_recebida".equals(n.getTipo())
                            && n.getUsuarioId().equals(ricardo.getId()))).hasSize(1);
        }

        @Test
        @DisplayName("outro valor para o mesmo entregador é uma segunda gorjeta — recusada")
        void segundaGorjeta() {
            gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("10"));
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(),
                    new BigDecimal("20")))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("já deu uma gorjeta de R$ 10,00");
        }
    }

    @Nested
    @DisplayName("regras")
    class Regras {

        @Test
        @DisplayName("só o lojista do turno: outro lojista e o próprio entregador levam 403")
        void soOLojistaDoTurno() {
            Usuario outraLoja = cenario.conta("lojista", "Outra", "11.111.111/0001-11");
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), outraLoja.getId(), ricardo.getId(), BigDecimal.TEN))
                    .hasMessageContaining("Só o lojista do turno");
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), ricardo.getId(), ricardo.getId(), BigDecimal.TEN))
                    .hasMessageContaining("Só o lojista do turno");
        }

        @Test
        @DisplayName("turno ainda não finalizado: 409")
        void soTurnoFinalizado() {
            cenario.recarregar(loja.getId(), "100.00");
            Turno aberto = cenario.publicar(loja.getId(), "100.00", 1);
            turnos.aceitar(aberto.getId(), lucas.getId());
            assertThatThrownBy(() -> gorjetas.dar(aberto.getId(), loja.getId(), lucas.getId(), BigDecimal.TEN))
                    .hasMessageContaining("depois do turno finalizado");
        }

        @Test
        @DisplayName("quem não trabalhou no turno não recebe: 422")
        void soQuemTrabalhou() {
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), lucas.getId(), BigDecimal.TEN))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("não trabalhou neste turno");

            // Inscrição cancelada também não conta.
            TurnoInscricao cancelada = new TurnoInscricao();
            cancelada.setTurnoId(turno.getId());
            cancelada.setMotoboyId(lucas.getId());
            cancelada.setStatus(StatusInscricao.CANCELADO);
            inscricaoRepo.save(cancelada);
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), lucas.getId(), BigDecimal.TEN))
                    .hasMessageContaining("não trabalhou neste turno");
        }

        @Test
        @DisplayName("sem saldo disponível: 422 dizendo quanto há — e nada se move")
        void semSaldo() {
            BigDecimal ricardoAntes = disponivel(ricardo);
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(),
                    new BigDecimal("40")))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("você tem R$ 30,00 disponível");
            assertThat(disponivel(ricardo)).isEqualByComparingTo(ricardoAntes);
        }

        @Test
        @DisplayName("de R$ 1 até o teto (R$ 50)")
        void limites() {
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(),
                    new BigDecimal("0.50"))).hasMessageContaining("pelo menos");
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(),
                    new BigDecimal("50.01"))).hasMessageContaining("vai até R$ 50,00");
            assertThatThrownBy(() -> gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(),
                    new BigDecimal("5.555"))).hasMessageContaining("centavos");

            cenario.recarregar(loja.getId(), "30.00");
            assertThat(gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("50")).valor())
                    .isEqualByComparingTo("50.00");
        }
    }

    @Test
    @DisplayName("gera comprovante, nunca NFS-e — dos dois lados")
    void comprovante() {
        gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), BigDecimal.TEN);

        assertThat(TipoDocumento.para(doTurno(TipoTransacao.BONUS_ENVIADO), null))
                .contains(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
        assertThat(TipoDocumento.para(doTurno(TipoTransacao.BONUS), null))
                .contains(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
    }

    @Test
    @DisplayName("aparece no resumo dos dois papéis e nos ganhos do mês do entregador")
    void resumos() {
        BigDecimal ganhosAntes = carteiras.ganhosDoMes(ricardo.getId());
        gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), new BigDecimal("15"));

        ResumoFinanceiroResponse doEntregador = extrato.resumo(ricardo.getId(), false, null, null);
        assertThat(doEntregador.gorjetas()).isEqualByComparingTo("15.00");
        assertThat(doEntregador.recebido()).isEqualByComparingTo("115.00");

        ResumoFinanceiroResponse doLojista = extrato.resumo(loja.getId(), true, null, null);
        assertThat(doLojista.gorjetas()).isEqualByComparingTo("15.00");
        assertThat(doLojista.pagoAEntregadores()).isEqualByComparingTo("115.00");

        assertThat(carteiras.ganhosDoMes(ricardo.getId()))
                .isEqualByComparingTo(ganhosAntes.add(new BigDecimal("15")));
    }

    @Test
    @DisplayName("as gorjetas do turno: o lojista vê todas, o entregador só a dele")
    void listagem() {
        gorjetas.dar(turno.getId(), loja.getId(), ricardo.getId(), BigDecimal.TEN);

        assertThat(gorjetas.doTurno(turno.getId(), loja.getId())).hasSize(1);
        assertThat(gorjetas.doTurno(turno.getId(), ricardo.getId())).hasSize(1);
    }

    // ── apoio ───────────────────────────────────────────────────────────────

    private BigDecimal disponivel(Usuario u) {
        return carteiras.obterOuCriar(u.getId()).getSaldoDisponivel();
    }

    private Transacao doTurno(TipoTransacao tipo) {
        return transacaoRepo.findByTurnoId(turno.getId()).stream()
                .filter(t -> t.getTipo() == tipo)
                .findFirst()
                .orElseThrow();
    }
}
