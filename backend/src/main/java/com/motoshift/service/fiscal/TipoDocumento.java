package com.motoshift.service.fiscal;

import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.Transacao;

import java.util.Optional;

/**
 * Que documento um lançamento do extrato gera — a tabela inteira num lugar só.
 *
 * <pre>
 *   lançamento                          documento                  quem vê
 *   pagamento_recebido (entregador)     NFSE                       os dois
 *   pagamento_enviado (lojista)         NFSE — a MESMA de cima     os dois
 *   recarga                             RECIBO_RECARGA             o dono
 *   saque, Pix concluído                COMPROVANTE_PIX            o dono
 *   saque, Pix recusado                 COMPROVANTE_MOVIMENTACAO   o dono
 *   reserva, liberacao_reserva,         COMPROVANTE_MOVIMENTACAO   o dono
 *   estorno, retencao_*, bonus
 * </pre>
 *
 * <p><b>Reserva e liberação NÃO são serviço prestado</b>, e por isso não geram
 * nota fiscal — só comprovante. Reservar é o lojista separar o próprio
 * dinheiro, do disponível para o bloqueado; liberar é esse dinheiro voltar.
 * Ninguém prestou nada a ninguém. Emitir NFS-e para isso documentaria um
 * serviço inexistente, com tributo sobre dinheiro que não mudou de dono.
 * NFS-e existe para uma coisa só: o pagamento de um turno concluído, que é
 * serviço de entrega do entregador para o lojista.
 *
 * <p>Tudo aqui é SIMULADO — ver {@code docs/financeiro/FISCAL.md}.
 */
public enum TipoDocumento {

    /** Nota fiscal de serviço — o pagamento de um turno. */
    NFSE,
    /** Recibo de dinheiro que entrou na plataforma. */
    RECIBO_RECARGA,
    /** Comprovante de um Pix que saiu da plataforma. */
    COMPROVANTE_PIX,
    /** Todo o resto: movimento que não é serviço nem Pix. */
    COMPROVANTE_MOVIMENTACAO;

    /**
     * O documento de um lançamento, ou vazio quando ele ainda não pode ter um.
     *
     * @param statusDoPix situação da cobrança de um saque — só importa para
     *                    saque; {@code null} quando não se sabe (saque anterior
     *                    ao gateway, que o fluxo antigo dava por concluído)
     */
    public static Optional<TipoDocumento> para(Transacao t, StatusCobranca statusDoPix) {
        // Lançamento que não concluiu não moveu dinheiro: não há o que comprovar.
        if (t.getStatus() != StatusTransacao.CONCLUIDO) return Optional.empty();

        return switch (t.getTipo()) {
            case PAGAMENTO_RECEBIDO, PAGAMENTO_ENVIADO -> Optional.of(NFSE);
            case RECARGA -> Optional.of(RECIBO_RECARGA);
            case SAQUE -> {
                if (statusDoPix == StatusCobranca.PENDENTE) {
                    // O dinheiro saiu da carteira, mas o banco ainda não
                    // respondeu: um comprovante de Pix agora afirmaria uma
                    // transferência que talvez não aconteça.
                    yield Optional.empty();
                }
                yield Optional.of(statusDoPix == StatusCobranca.FALHOU
                        ? COMPROVANTE_MOVIMENTACAO
                        : COMPROVANTE_PIX);
            }
            // Não são serviço prestado — ver o cabeçalho.
            case RESERVA, LIBERACAO_RESERVA -> Optional.of(COMPROVANTE_MOVIMENTACAO);
            case ESTORNO, BONUS, RETENCAO_ISS, RETENCAO_IRRF ->
                    Optional.of(COMPROVANTE_MOVIMENTACAO);
        };
    }
}
