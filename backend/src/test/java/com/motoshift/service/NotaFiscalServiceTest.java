package com.motoshift.service;

import com.motoshift.dto.NotaFiscalPendenteResponse;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * A emissão da NFS-e de um pagamento de turno.
 *
 * O que estes testes prendem é a parte da regra que não é óbvia lendo o
 * serviço: que a nota documenta o pagamento que está no extrato (e concorda
 * com ele), que os dois lados emitem o MESMO documento, que a segunda chamada
 * não cria uma segunda nota, e que cancelar a nota não mexe no dinheiro.
 *
 * Pagamentos de verdade, pela liquidação: um turno gravado direto como
 * FINALIZADO não tem pagamento nenhum no extrato, e a nota não tem o que
 * documentar.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class NotaFiscalServiceTest {

    @Autowired private NotaFiscalService notas;
    @Autowired private CenarioFinanceiro cenario;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;

    private Long lojista;
    private Long motoboy;
    private Long estranho;

    @BeforeEach
    void criarPessoas() {
        lojista = cenario.conta("lojista", "Loja de Teste", "12.345.678/0001-90").getId();
        // O cadastro do entregador guarda a CNH em documentoFederal.
        motoboy = cenario.conta("motoboy", "Entregador de Teste", "12345678900").getId();
        estranho = cenario.conta("motoboy", "Terceiro Curioso", "98765432100").getId();
    }

    @Test
    @DisplayName("prestador é o entregador, tomador é o lojista, e os documentos saem mascarados")
    void partesDaNota() {
        Turno turno = cenario.turnoPago(lojista, "120.00", motoboy);

        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThat(nota.getPrestadorId()).isEqualTo(motoboy);
        assertThat(nota.getPrestadorNome()).isEqualTo("Entregador de Teste");
        assertThat(nota.getTomadorId()).isEqualTo(lojista);
        assertThat(nota.getTomadorNome()).isEqualTo("Loja de Teste");
        assertThat(nota.getPapel()).isEqualTo("prestador");
        assertThat(nota.getNumero()).isPositive();
        assertThat(nota.getCodigoVerificacao()).matches("[0-9A-F]{4}-[0-9A-F]{4}");

        // CNPJ mascarado; o "CPF" do entregador não vira a CNH dele.
        assertThat(nota.getTomadorDocumentoTipo()).isEqualTo("CNPJ");
        assertThat(nota.getTomadorDocumento()).isEqualTo("**.345.678/0001-**");
        assertThat(nota.getPrestadorDocumentoTipo()).isEqualTo("CPF");
        assertThat(nota.getPrestadorDocumento()).isNull();
        assertThat(nota.getPrestadorCidade()).isEqualTo("Curitiba/PR");
    }

    @Test
    @DisplayName("sem retenção, os tributos são informativos e o líquido é o que o extrato creditou")
    void tributosInformativosBatemComOExtrato() {
        Turno turno = cenario.turnoPago(lojista, "200.00", motoboy);
        Transacao pagamento = cenario.pagamentoRecebido(turno, motoboy);

        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        // 5% de 200 = 10,00 ; 1,5% de 200 = 3,00 — valor aproximado, não retido.
        assertThat(nota.isTributosRetidos()).isFalse();
        assertThat(nota.getValorServico()).isEqualByComparingTo("200.00");
        assertThat(nota.getIssValor()).isEqualByComparingTo("10.00");
        assertThat(nota.getIrrfValor()).isEqualByComparingTo("3.00");
        assertThat(nota.getTotalTributos()).isEqualByComparingTo("13.00");

        // A discordância que existia: a nota dizia 187 e o extrato, 200.
        assertThat(nota.getValorLiquido()).isEqualByComparingTo(pagamento.getValor());
        assertThat(carteira(motoboy).getSaldoDisponivel()).isEqualByComparingTo("200.00");
        assertThat(transacaoRepo.findByOperacaoIdAndUsuarioIdAndTipoIn(pagamento.getOperacaoId(),
                motoboy, List.of(TipoTransacao.RETENCAO_ISS, TipoTransacao.RETENCAO_IRRF))).isEmpty();
    }

    @Test
    @DisplayName("a nota aponta para o pagamento e para a operação do extrato")
    void vinculoComOExtrato() {
        Turno turno = cenario.turnoPago(lojista, "150.00", motoboy);
        Transacao recebido = cenario.pagamentoRecebido(turno, motoboy);
        Transacao enviado = cenario.pagamentoEnviado(turno, lojista, motoboy);

        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, lojista).nota();

        assertThat(nota.getTransacaoId()).isEqualTo(recebido.getId());
        assertThat(nota.getOperacaoId())
                .isEqualTo(recebido.getOperacaoId())
                .isEqualTo(enviado.getOperacaoId());
        assertThat(nota.getValorServico()).isEqualByComparingTo(recebido.getValor());
        assertThat(nota.getCompetencia()).isEqualTo(turno.getDataInicio());
        assertThat(nota.getDescricaoServico())
                .contains(turno.getTitulo())
                .contains("Data:")
                .contains("Região: Batel, Curitiba");
    }

    @Test
    @DisplayName("lojista e entregador emitem o mesmo documento, não um cada")
    void osDoisLadosEmitemAMesmaNota() {
        Turno turno = cenario.turnoPago(lojista, "90.00", motoboy);

        NotaFiscalService.Emissao pelaLoja = notas.emitir(turno.getId(), motoboy, lojista);
        NotaFiscalService.Emissao peloEntregador = notas.emitirParaPagamento(
                cenario.pagamentoRecebido(turno, motoboy), motoboy);

        assertThat(pelaLoja.criada()).isTrue();
        assertThat(peloEntregador.criada()).isFalse();
        assertThat(peloEntregador.nota().getId()).isEqualTo(pelaLoja.nota().getId());

        // O papel muda com quem pergunta; o documento, não.
        assertThat(pelaLoja.nota().getPapel()).isEqualTo("tomador");
        assertThat(peloEntregador.nota().getPapel()).isEqualTo("prestador");
    }

    @Test
    @DisplayName("turno que ainda não terminou não gera nota")
    void turnoNaoFinalizado() {
        cenario.recarregar(lojista, "80.00");
        Turno turno = cenario.publicar(lojista, "80.00", 1);
        cenario.inscrever(turno, motoboy);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.emitir(turno.getId(), motoboy, motoboy))
                .withMessageContaining("finalizado");
    }

    @Test
    @DisplayName("quem não participou do turno não emite nem lê a nota")
    void estranhoNaoPassa() {
        Turno turno = cenario.turnoPago(lojista, "70.00", motoboy);
        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.emitir(turno.getId(), motoboy, estranho));
        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.emitirParaPagamento(
                        cenario.pagamentoRecebido(turno, motoboy), estranho))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(403));

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.buscar(nota.getId(), estranho))
                .withMessageContaining("não é sua");
    }

    @Test
    @DisplayName("o turno sai das pendências assim que a nota é emitida")
    void pendenciaSomeDepoisDeEmitir() {
        Turno turno = cenario.turnoPago(lojista, "110.00", motoboy);

        assertThat(idsPendentes(motoboy, false)).contains(turno.getId());
        assertThat(idsPendentes(lojista, true)).contains(turno.getId());

        notas.emitir(turno.getId(), motoboy, motoboy);

        assertThat(idsPendentes(motoboy, false)).doesNotContain(turno.getId());
        assertThat(idsPendentes(lojista, true)).doesNotContain(turno.getId());
    }

    @Test
    @DisplayName("cancelar a nota não estorna o pagamento, e gerar de novo devolve a cancelada")
    void cancelarNaoMexeNoDinheiro() {
        Turno turno = cenario.turnoPago(lojista, "60.00", motoboy);
        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.cancelar(nota.getId(), "engano", lojista))
                .withMessageContaining("prestador");

        NotaFiscalResponse cancelada = notas.cancelar(nota.getId(), "engano", motoboy);
        assertThat(cancelada.isCancelada()).isTrue();
        assertThat(cancelada.getMotivoCancelamento()).isEqualTo("engano");

        // O dinheiro continua onde a liquidação o deixou.
        assertThat(carteira(motoboy).getSaldoDisponivel()).isEqualByComparingTo("60.00");
        assertThat(transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(motoboy))
                .noneMatch(t -> t.getTipo() == TipoTransacao.ESTORNO);

        // Uma nota por pagamento: a cancelada não é substituída.
        NotaFiscalService.Emissao denovo = notas.emitir(turno.getId(), motoboy, motoboy);
        assertThat(denovo.criada()).isFalse();
        assertThat(denovo.nota().getId()).isEqualTo(nota.getId());
        assertThat(denovo.nota().isCancelada()).isTrue();
    }

    @Test
    @DisplayName("turno de duas vagas: uma nota por entregador, e uma não apaga a pendência da outra")
    void multiVaga() {
        Turno turno = cenario.turnoPago(lojista, "100.00", motoboy, estranho);

        assertThat(notas.pendentes(lojista, true))
                .extracting(NotaFiscalPendenteResponse::getPrestadorId)
                .containsExactlyInAnyOrder(motoboy, estranho);

        NotaFiscalResponse doEstranho = notas.emitir(turno.getId(), estranho, estranho).nota();

        assertThat(idsPendentes(estranho, false)).doesNotContain(turno.getId());
        assertThat(notas.pendentes(lojista, true))
                .extracting(NotaFiscalPendenteResponse::getPrestadorId)
                .containsExactly(motoboy);

        NotaFiscalResponse doMotoboy = notas.emitir(turno.getId(), motoboy, lojista).nota();
        assertThat(doMotoboy.getId()).isNotEqualTo(doEstranho.getId());
        assertThat(doMotoboy.getTransacaoId()).isNotEqualTo(doEstranho.getTransacaoId());
    }

    @Test
    @DisplayName("a nota aparece na lista dos dois participantes, e só deles")
    void listaDosDoisLados() {
        Turno turno = cenario.turnoPago(lojista, "130.00", motoboy);
        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThat(notas.listarDoUsuario(motoboy))
                .extracting(NotaFiscalResponse::getId).contains(nota.getId());
        assertThat(notas.listarDoUsuario(lojista))
                .extracting(NotaFiscalResponse::getId).contains(nota.getId());
        assertThat(notas.listarDoUsuario(estranho))
                .extracting(NotaFiscalResponse::getId).doesNotContain(nota.getId());
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private List<Long> idsPendentes(Long usuarioId, boolean ehLojista) {
        return notas.pendentes(usuarioId, ehLojista).stream()
                .map(NotaFiscalPendenteResponse::getTurnoId)
                .toList();
    }

    private Carteira carteira(Long usuarioId) {
        return carteiraRepo.findByUsuarioId(usuarioId).orElseThrow();
    }
}
