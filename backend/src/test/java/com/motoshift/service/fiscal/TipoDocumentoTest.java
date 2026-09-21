package com.motoshift.service.fiscal;

import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import java.lang.reflect.Field;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A tabela lançamento → documento, tipo por tipo, sem banco.
 *
 * <p>Percorre TODOS os valores de {@link TipoTransacao}: um tipo novo que
 * entrar no enum cai aqui e precisa de decisão explícita. A regra que mais
 * importa — só pagamento de turno é serviço prestado — é conferida contra a
 * lista inteira, e não contra os tipos que alguém lembrou de testar.
 */
class TipoDocumentoTest {

    @ParameterizedTest(name = "{0}")
    @EnumSource(TipoTransacao.class)
    @DisplayName("só pagamento de turno gera NFS-e; todo o resto é recibo ou comprovante")
    void soPagamentoEServico(TipoTransacao tipo) {
        var doc = TipoDocumento.para(lancamento(tipo, StatusTransacao.CONCLUIDO), StatusCobranca.CONCLUIDO);

        boolean pagamento = tipo == TipoTransacao.PAGAMENTO_RECEBIDO
                || tipo == TipoTransacao.PAGAMENTO_ENVIADO;
        assertThat(doc).isPresent();
        assertThat(doc.get() == TipoDocumento.NFSE).isEqualTo(pagamento);
    }

    @Test
    @DisplayName("reserva e liberação são comprovante de movimentação, com ou sem Pix no meio")
    void reservaELiberacao() {
        for (TipoTransacao t : new TipoTransacao[]{TipoTransacao.RESERVA, TipoTransacao.LIBERACAO_RESERVA}) {
            for (StatusCobranca s : new StatusCobranca[]{null, StatusCobranca.CONCLUIDO, StatusCobranca.FALHOU}) {
                assertThat(TipoDocumento.para(lancamento(t, StatusTransacao.CONCLUIDO), s))
                        .contains(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
            }
        }
    }

    @Test
    @DisplayName("saque: Pix concluído é comprovante Pix, recusado é movimentação, pendente ainda não tem")
    void saque() {
        Transacao saque = lancamento(TipoTransacao.SAQUE, StatusTransacao.CONCLUIDO);
        assertThat(TipoDocumento.para(saque, StatusCobranca.CONCLUIDO)).contains(TipoDocumento.COMPROVANTE_PIX);
        assertThat(TipoDocumento.para(saque, StatusCobranca.FALHOU)).contains(TipoDocumento.COMPROVANTE_MOVIMENTACAO);
        assertThat(TipoDocumento.para(saque, StatusCobranca.PENDENTE)).isEmpty();
    }

    @Test
    @DisplayName("lançamento que não concluiu não moveu dinheiro e não tem documento")
    void naoConcluido() {
        assertThat(TipoDocumento.para(
                lancamento(TipoTransacao.PAGAMENTO_RECEBIDO, StatusTransacao.PENDENTE), null)).isEmpty();
    }

    @Test
    @DisplayName("o código de autenticação é estável e depende da chave")
    void hmacEstavelEPorChave() {
        Transacao t = lancamento(TipoTransacao.RECARGA, StatusTransacao.CONCLUIDO);
        ComprovanteService a = new ComprovanteService("chave-a", null, null);
        ComprovanteService b = new ComprovanteService("chave-b", null, null);

        assertThat(a.codigoDeAutenticacao(t)).isEqualTo(a.codigoDeAutenticacao(t));
        assertThat(b.codigoDeAutenticacao(t)).isNotEqualTo(a.codigoDeAutenticacao(t));

        // Mudar o valor gravado muda o código: adulteração aparece.
        Transacao adulterada = lancamento(TipoTransacao.RECARGA, StatusTransacao.CONCLUIDO);
        adulterada.setValor(new BigDecimal("999.00"));
        assertThat(a.codigoDeAutenticacao(adulterada)).isNotEqualTo(a.codigoDeAutenticacao(t));
    }

    @Test
    @DisplayName("sem chave configurada, o serviço de comprovantes não sobe")
    void semChave() {
        org.assertj.core.api.Assertions.assertThatIllegalStateException()
                .isThrownBy(() -> new ComprovanteService(" ", null, null))
                .withMessageContaining("MOTOSHIFT_FISCAL_CHAVE");
    }

    private static final UUID OPERACAO = UUID.fromString("00000000-0000-0000-0000-000000000042");

    private static Transacao lancamento(TipoTransacao tipo, StatusTransacao status) {
        Transacao t = new Transacao();
        definir(t, "id", 42L);
        t.setUsuarioId(7L);
        t.setTipo(tipo);
        t.setValor(new BigDecimal("100.00"));
        t.setStatus(status);
        t.setOperacaoId(OPERACAO);
        t.setIdempotencyKey("teste:" + tipo.getValor());
        t.setCriadoEm(LocalDateTime.of(2026, 9, 1, 10, 0));
        return t;
    }

    /** O id é do banco e não tem setter — o teste o fixa por reflexão. */
    private static void definir(Transacao t, String campo, Object valor) {
        try {
            Field f = Transacao.class.getDeclaredField(campo);
            f.setAccessible(true);
            f.set(t, valor);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
