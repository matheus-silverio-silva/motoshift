package com.motoshift.service.fiscal;

import com.motoshift.dto.DocumentoResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.ExtratoService;
import com.motoshift.service.gateway.GatewayPagamentoSimulado;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * O "Gerar documento" de cada lançamento do extrato.
 *
 * <p>Prende a tabela de {@link TipoDocumento} contra lançamentos de verdade —
 * gravados pela recarga, publicação, liquidação e saque reais — e as três
 * garantias do brief: os dois lados de um pagamento recebem a mesma nota,
 * gerar de novo devolve o mesmo documento, e o lançamento de outra pessoa não
 * abre nada.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class DocumentoFiscalServiceTest {

    @Autowired private DocumentoFiscalService documentos;
    @Autowired private CenarioFinanceiro cenario;
    @Autowired private CobrancaService cobrancas;
    @Autowired private ExtratoService extrato;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;

    private Long lojista;
    private Long entregador;
    private Long terceiro;

    @BeforeEach
    void contas() {
        lojista = cenario.conta("lojista", "Padaria Documentada", "11222333000144").getId();
        entregador = cenario.conta("motoboy", "Entregador Documentado", "12345678900").getId();
        terceiro = cenario.conta("motoboy", "Curioso", "98765432100").getId();
    }

    // ── Cada lançamento, o seu documento ────────────────────────────────────

    @Test
    @DisplayName("pagamento_recebido gera NFS-e com o entregador como prestador")
    void pagamentoRecebido_nfse() {
        Turno t = cenario.turnoPago(lojista, "150.00", entregador);

        DocumentoResponse doc = gerar(cenario.pagamentoRecebido(t, entregador), entregador);

        assertThat(doc.tipoDocumento()).isEqualTo(TipoDocumento.NFSE);
        assertThat(doc.nota().getPrestadorId()).isEqualTo(entregador);
        assertThat(doc.nota().getTomadorId()).isEqualTo(lojista);
        assertThat(doc.comprovante()).isNull();
        assertThat(doc.simulado()).isTrue();
        assertThat(doc.marca()).isEqualTo("DOCUMENTO SIMULADO — SEM VALOR FISCAL");
    }

    @Test
    @DisplayName("os dois lados de um pagamento recebem a MESMA nota, não uma cada")
    void osDoisLadosMesmaNota() {
        Turno t = cenario.turnoPago(lojista, "150.00", entregador);
        Transacao enviado = cenario.pagamentoEnviado(t, lojista, entregador);
        Transacao recebido = cenario.pagamentoRecebido(t, entregador);

        DocumentoFiscalService.Resultado pelaLoja = documentos.emitir(enviado.getId(), lojista);
        DocumentoFiscalService.Resultado peloEntregador = documentos.emitir(recebido.getId(), entregador);

        assertThat(pelaLoja.criado()).isTrue();
        assertThat(peloEntregador.criado()).isFalse();
        assertThat(peloEntregador.documento().nota().getId())
                .isEqualTo(pelaLoja.documento().nota().getId());
        assertThat(pelaLoja.documento().nota().getPapel()).isEqualTo("tomador");
        assertThat(peloEntregador.documento().nota().getPapel()).isEqualTo("prestador");
    }

    @Test
    @DisplayName("recarga gera recibo de recarga")
    void recarga_recibo() {
        cenario.recarregar(lojista, "300.00");
        Transacao recarga = doTipo(lojista, TipoTransacao.RECARGA);

        DocumentoResponse doc = gerar(recarga, lojista);

        assertThat(doc.tipoDocumento()).isEqualTo(TipoDocumento.RECIBO_RECARGA);
        assertThat(doc.comprovante().numero()).isEqualTo(String.format("RC-%08d", recarga.getId()));
        assertThat(doc.comprovante().valor()).isEqualByComparingTo("300.00");
        assertThat(doc.comprovante().titularDocumento()).isEqualTo("**.222.333/0001-**");
    }

    @Test
    @DisplayName("reserva e liberação geram comprovante de movimentação — nunca nota fiscal")
    void reservaELiberacao_nuncaNfse() {
        cenario.recarregar(lojista, "300.00");
        Turno t = cenario.publicar(lojista, "100.00", 2);
        cenario.inscrever(t, entregador);
        cenario.finalizar(t, lojista); // uma vaga vazia: a sobra volta como liberação

        Transacao reserva = cenario.doTurno(t, lojista, TipoTransacao.RESERVA);
        Transacao liberacao = cenario.doTurno(t, lojista, TipoTransacao.LIBERACAO_RESERVA);

        for (Transacao x : List.of(reserva, liberacao)) {
            DocumentoResponse doc = gerar(x, lojista);
            assertThat(doc.tipoDocumento()).isEqualTo(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
            assertThat(doc.nota()).isNull();
            assertThat(doc.comprovante().detalhes())
                    .anySatisfy(l -> assertThat(l.valor()).contains("não é pagamento nem serviço"));
        }
    }

    @Test
    @DisplayName("saque concluído gera comprovante Pix com a chave mascarada")
    void saque_pix() {
        cenario.recarregar(entregador, "100.00");
        chavePix(entregador, "entregador@pix.com");
        cobrancas.sacar(entregador, new BigDecimal("40.00"), null);

        DocumentoResponse doc = gerar(doTipo(entregador, TipoTransacao.SAQUE), entregador);

        assertThat(doc.tipoDocumento()).isEqualTo(TipoDocumento.COMPROVANTE_PIX);
        assertThat(doc.comprovante().detalhes())
                .anySatisfy(l -> assertThat(l.valor()).isEqualTo("e***@pix.com"))
                .anySatisfy(l -> assertThat(l.valor()).isEqualTo("Transferência concluída"));
    }

    @Test
    @DisplayName("saque recusado não gera comprovante Pix: o saque e o estorno viram movimentação")
    void saqueRecusado_movimentacao() {
        cenario.recarregar(entregador, "100.00");
        chavePix(entregador, GatewayPagamentoSimulado.MARCADOR_DE_RECUSA + "@pix.com");
        try {
            cobrancas.sacar(entregador, new BigDecimal("40.00"), null);
        } catch (ResponseStatusException recusado) {
            // O gateway recusa e o serviço avisa; o estorno já foi gravado.
        }

        assertThat(gerar(doTipo(entregador, TipoTransacao.SAQUE), entregador).tipoDocumento())
                .isEqualTo(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
        assertThat(gerar(doTipo(entregador, TipoTransacao.ESTORNO), entregador).tipoDocumento())
                .isEqualTo(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
    }

    // ── Idempotência ────────────────────────────────────────────────────────

    @Test
    @DisplayName("gerar duas vezes devolve o mesmo documento")
    void idempotencia() {
        Turno t = cenario.turnoPago(lojista, "90.00", entregador);
        Transacao recebido = cenario.pagamentoRecebido(t, entregador);
        Transacao recarga = doTipo(lojista, TipoTransacao.RECARGA);

        DocumentoFiscalService.Resultado a = documentos.emitir(recebido.getId(), entregador);
        DocumentoFiscalService.Resultado b = documentos.emitir(recebido.getId(), entregador);
        assertThat(a.criado()).isTrue();
        assertThat(b.criado()).isFalse();
        assertThat(b.documento().nota().getId()).isEqualTo(a.documento().nota().getId());
        assertThat(b.documento().nota().getNumero()).isEqualTo(a.documento().nota().getNumero());

        DocumentoResponse c1 = gerar(recarga, lojista);
        DocumentoResponse c2 = gerar(recarga, lojista);
        assertThat(c2.comprovante().numero()).isEqualTo(c1.comprovante().numero());
        assertThat(c2.comprovante().codigoAutenticacao())
                .isEqualTo(c1.comprovante().codigoAutenticacao())
                .matches("[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}");
    }

    @Test
    @DisplayName("GET da NFS-e responde 404 até ela ser gerada, e depois devolve a mesma")
    void consultarAntesEDepois() {
        Turno t = cenario.turnoPago(lojista, "80.00", entregador);
        Transacao enviado = cenario.pagamentoEnviado(t, lojista, entregador);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> documentos.buscar(enviado.getId(), lojista))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(404));

        Long nota = documentos.emitir(enviado.getId(), lojista).documento().nota().getId();

        assertThat(documentos.buscar(enviado.getId(), lojista).nota().getId()).isEqualTo(nota);
    }

    // ── Autorização ─────────────────────────────────────────────────────────

    @Test
    @DisplayName("terceiro leva 403 — e a contraparte também, pelo id do lançamento alheio")
    void soODono() {
        Turno t = cenario.turnoPago(lojista, "70.00", entregador);
        Transacao recebido = cenario.pagamentoRecebido(t, entregador);

        for (Long intruso : List.of(terceiro, lojista)) {
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> documentos.emitir(recebido.getId(), intruso))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> documentos.buscar(recebido.getId(), intruso))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));
        }
    }

    // ── O extrato sabe do documento ─────────────────────────────────────────

    @Test
    @DisplayName("o extrato diz que documento cada linha tem, e o id da nota depois de gerada")
    void extratoAnotado() {
        Turno t = cenario.turnoPago(lojista, "120.00", entregador);
        Transacao recebido = cenario.pagamentoRecebido(t, entregador);

        TransacaoResponse antes = linha(entregador, recebido.getId());
        assertThat(antes.isDocumentoDisponivel()).isTrue();
        assertThat(antes.getTipoDocumento()).isEqualTo(TipoDocumento.NFSE);
        assertThat(antes.getDocumentoId()).isNull();

        Long nota = documentos.emitir(recebido.getId(), entregador).documento().nota().getId();

        assertThat(linha(entregador, recebido.getId()).getDocumentoId()).isEqualTo(nota);
        // O lado do lojista aponta para a mesma nota.
        Transacao enviado = cenario.pagamentoEnviado(t, lojista, entregador);
        assertThat(linha(lojista, enviado.getId()).getDocumentoId()).isEqualTo(nota);
        // E a reserva do lojista tem comprovante, não nota.
        Transacao reserva = cenario.doTurno(t, lojista, TipoTransacao.RESERVA);
        assertThat(linha(lojista, reserva.getId()).getTipoDocumento())
                .isEqualTo(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private DocumentoResponse gerar(Transacao t, Long usuario) {
        return documentos.emitir(t.getId(), usuario).documento();
    }

    private Transacao doTipo(Long usuario, TipoTransacao tipo) {
        return transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(usuario).stream()
                .filter(x -> x.getTipo() == tipo)
                .findFirst()
                .orElseThrow(() -> new AssertionError("sem " + tipo.getValor() + " de " + usuario));
    }

    private void chavePix(Long usuario, String chave) {
        Carteira c = carteiraRepo.findByUsuarioId(usuario).orElseThrow();
        c.setChavePix(chave);
        carteiraRepo.save(c);
    }

    private TransacaoResponse linha(Long usuario, Long transacaoId) {
        return extrato.extrato(usuario, new com.motoshift.dto.ExtratoFiltro(), PageRequest.of(0, 50))
                .getContent().stream()
                .filter(r -> r.getId().equals(transacaoId))
                .findFirst()
                .orElseThrow(() -> new AssertionError("lançamento fora do extrato"));
    }
}
