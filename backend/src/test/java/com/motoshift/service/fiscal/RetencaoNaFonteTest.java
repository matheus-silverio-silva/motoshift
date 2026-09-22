package com.motoshift.service.fiscal;

import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.service.PagamentoTurnoService;
import com.motoshift.service.ledger.ConsistenciaService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A retenção na fonte ligada: {@code motoshift.fiscal.reter-na-fonte=true}.
 *
 * <p>A outra política (desligada, o padrão) está no NotaFiscalServiceTest. Aqui
 * o contexto sobe com a retenção ligada e a pergunta é a mesma — nota e
 * extrato concordam? — só que agora o dinheiro que sobra é o líquido.
 */
@SpringBootTest(properties = "motoshift.fiscal.reter-na-fonte=true")
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class RetencaoNaFonteTest {

    @Autowired private CenarioFinanceiro cenario;
    @Autowired private NotaFiscalService notas;
    @Autowired private PagamentoTurnoService pagamentos;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private InformeRendimentosService informes;

    private Long lojista;
    private Long entregador;

    @BeforeEach
    void contas() {
        lojista = cenario.conta("lojista", "Loja Retentora", "11222333000144").getId();
        entregador = cenario.conta("motoboy", "Entregador Retido", "12345678900").getId();
    }

    @Test
    @DisplayName("o pagamento entra bruto e ISS e IRRF saem na mesma operação; sobra o líquido")
    void liquidacaoRetem() {
        Turno turno = cenario.turnoPago(lojista, "200.00", entregador);

        Transacao recebido = cenario.pagamentoRecebido(turno, entregador);
        Transacao enviado = cenario.pagamentoEnviado(turno, lojista, entregador);
        Transacao iss = cenario.doTurno(turno, entregador, TipoTransacao.RETENCAO_ISS);
        Transacao irrf = cenario.doTurno(turno, entregador, TipoTransacao.RETENCAO_IRRF);

        // Bruto no pagamento: é o valor do serviço, o mesmo da NFS-e.
        assertThat(recebido.getValor()).isEqualByComparingTo("200.00");
        assertThat(enviado.getValor()).isEqualByComparingTo("200.00");
        assertThat(iss.getValor()).isEqualByComparingTo("10.00");
        assertThat(irrf.getValor()).isEqualByComparingTo("3.00");

        // Quatro linhas, uma operação.
        assertThat(List.of(enviado, iss, irrf))
                .extracting(Transacao::getOperacaoId)
                .containsOnly(recebido.getOperacaoId());

        assertThat(carteiraRepo.findByUsuarioId(entregador).orElseThrow().getSaldoDisponivel())
                .isEqualByComparingTo("187.00");

        // A plataforma continua sem criar nem destruir dinheiro: o que saiu,
        // saiu para o fisco, pela retenção.
        // As duas partes do pagamento, e so elas: recorte fechado, que e a
        // condicao para a invariante (c) valer num subconjunto.
        consistencia.verificarConsistencia(List.of(lojista, entregador))
                .exigirConsistente();
    }

    @Test
    @DisplayName("a nota mostra o que foi retido, e o líquido dela é o saldo que o extrato deixou")
    void notaBateComARetencao() {
        Turno turno = cenario.turnoPago(lojista, "200.00", entregador);

        NotaFiscalResponse nota = notas.emitir(turno.getId(), entregador, entregador).nota();

        assertThat(nota.isTributosRetidos()).isTrue();
        assertThat(nota.getValorServico()).isEqualByComparingTo("200.00");
        assertThat(nota.getIssValor()).isEqualByComparingTo("10.00");
        assertThat(nota.getIrrfValor()).isEqualByComparingTo("3.00");
        assertThat(nota.getIssAliquota()).isEqualByComparingTo("0.05");
        assertThat(nota.getIrrfAliquota()).isEqualByComparingTo("0.015");
        assertThat(nota.getValorLiquido())
                .isEqualByComparingTo("187.00")
                .isEqualByComparingTo(carteiraRepo.findByUsuarioId(entregador).orElseThrow()
                        .getSaldoDisponivel());
    }

    @Test
    @DisplayName("o informe continua bruto e mostra o que foi retido ao lado")
    void informeComRetencao() {
        cenario.turnoPago(lojista, "200.00", entregador);

        var inf = informes.informe(entregador, false, java.time.Year.now().getValue());

        // Rendimento é o bruto — o mesmo valor da NFS-e —, com as retenções ao lado.
        assertThat(inf.total()).isEqualByComparingTo("200.00");
        assertThat(inf.issRetido()).isEqualByComparingTo("10.00");
        assertThat(inf.irrfRetido()).isEqualByComparingTo("3.00");
        assertThat(inf.pagamentos()).isEqualTo(1);
    }

    @Test
    @DisplayName("liquidar de novo não retém de novo")
    void retencaoIdempotente() {
        Turno turno = cenario.turnoPago(lojista, "100.00", entregador);
        List<TurnoInscricao> inscricoes = inscricaoRepo.findByTurnoId(turno.getId());

        pagamentos.liquidar(turno, inscricoes);

        assertThat(transacaoRepo.findByTurnoId(turno.getId()))
                .filteredOn(t -> t.getTipo() == TipoTransacao.RETENCAO_ISS)
                .hasSize(1);
        assertThat(carteiraRepo.findByUsuarioId(entregador).orElseThrow().getSaldoDisponivel())
                .isEqualByComparingTo("93.50");
    }
}
