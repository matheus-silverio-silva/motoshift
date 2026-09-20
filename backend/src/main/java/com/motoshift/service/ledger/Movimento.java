package com.motoshift.service.ledger;

import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.TipoTransacao;

import java.math.BigDecimal;

/**
 * Uma perna de movimentacao de saldo, pronta para o {@link LedgerService} aplicar.
 *
 * <p><b>Esta classe e a tabela de verdade do projeto sobre dinheiro.</b> Cada
 * fabrica estatica aqui embaixo responde, para um tipo de lancamento, as tres
 * perguntas que ninguem mais no backend tem o direito de responder: quanto sai
 * do disponivel, quanto entra no bloqueado e que sinal a tela mostra. Isso
 * estava espalhado — o credito do entregador no PagamentoTurnoService, o
 * debito do saque no CarteiraService, e o bloqueado em lugar nenhum porque
 * ninguem o movia. Espalhado, "o dinheiro sai de onde?" so tinha resposta
 * lendo os dois arquivos e torcendo para nao existir um terceiro.
 *
 * <p><b>Os dois deltas nao sao redundantes com a natureza.</b> Natureza e o
 * sinal que o extrato desenha; os deltas sao a aritmetica. Numa reserva eles
 * discordam de proposito: a natureza e DEBITO (para o lojista, R$ 360 sairam
 * do bolso de onde ele pode gastar) mas o patrimonio dele nao mudou — o
 * dinheiro foi do disponivel para o bloqueado. Por isso somar o extrato pela
 * natureza nao devolve o saldo, e as invariantes somam pelos deltas.
 *
 * <p>Tabela completa, com o total sendo disponivel + bloqueado:
 * <pre>
 *   tipo                 disponivel  bloqueado   total   natureza
 *   recarga                  +v          0        +v     credito
 *   reserva                  -v         +v         0     debito
 *   liberacao_reserva        +v         -v         0     credito
 *   pagamento_enviado         0         -v        -v     debito
 *   pagamento_recebido       +v          0        +v     credito
 *   saque                    -v          0        -v     debito
 *   estorno                  +v          0        +v     credito
 * </pre>
 *
 * Repare que a coluna do total fecha: reserva e liberacao nao criam nem
 * destroem nada, e pagamento_enviado (-v no lojista) e pagamento_recebido (+v
 * no entregador) se anulam. E dai que sai a invariante (c) — a soma de todas as
 * carteiras so muda por recarga, saque e estorno.
 *
 * @param usuarioId       dono do lancamento: de quem e este extrato
 * @param contraparteId   o outro lado, quando existe
 * @param turnoId         turno que originou o movimento, quando existe
 * @param tipo            o que aconteceu
 * @param natureza        o sinal que a tela mostra
 * @param valor           sempre positivo — o sinal esta no tipo, nunca no numero
 * @param deltaDisponivel quanto somar ao saldo disponivel (pode ser negativo)
 * @param deltaBloqueado  quanto somar ao saldo bloqueado (pode ser negativo)
 * @param descricao       texto que aparece no extrato
 * @param idempotencyKey  deterministica: repetir a operacao nao move dinheiro de novo
 */
public record Movimento(
        Long usuarioId,
        Long contraparteId,
        Long turnoId,
        TipoTransacao tipo,
        NaturezaTransacao natureza,
        BigDecimal valor,
        BigDecimal deltaDisponivel,
        BigDecimal deltaBloqueado,
        String descricao,
        String idempotencyKey) {

    private static final BigDecimal ZERO = BigDecimal.ZERO;

    public Movimento {
        if (usuarioId == null) {
            throw new IllegalArgumentException("Movimento sem dono.");
        }
        if (valor == null || valor.signum() <= 0) {
            throw new IllegalArgumentException("Movimento com valor invalido: " + valor
                    + ". O sinal esta no tipo, nao no numero.");
        }
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            throw new IllegalArgumentException(
                    "Movimento sem chave de idempotencia — ver Transacao.idempotencyKey.");
        }
    }

    // -- Fronteira com o mundo de fora ---------------------------------------

    /** Dinheiro entrando na plataforma: o Pix da recarga foi confirmado. */
    public static Movimento recarga(Long usuarioId, BigDecimal valor, Long cobrancaId) {
        return new Movimento(usuarioId, null, null,
                TipoTransacao.RECARGA, NaturezaTransacao.CREDITO,
                valor, valor, ZERO,
                "Recarga via Pix", "recarga:" + cobrancaId);
    }

    /** Dinheiro saindo da plataforma para a chave Pix. */
    public static Movimento saque(Long usuarioId, BigDecimal valor, String chavePix, Long cobrancaId) {
        return new Movimento(usuarioId, null, null,
                TipoTransacao.SAQUE, NaturezaTransacao.DEBITO,
                valor, valor.negate(), ZERO,
                "Transferência Pix — " + chavePix, "saque:" + cobrancaId);
    }

    /**
     * Devolucao de um saque que o gateway recusou.
     *
     * O debito original NAO e apagado nem marcado como estornado: ele
     * aconteceu, o dinheiro saiu da carteira, e o extrato e o registro do que
     * aconteceu. O estorno e um segundo lancamento que traz o valor de volta.
     * As duas linhas juntas somam zero, que e exatamente a verdade — e as
     * invariantes continuam valendo sem excecao para "saque que nao valeu".
     */
    public static Movimento estornoDeSaque(Long usuarioId, BigDecimal valor, Long cobrancaId) {
        return new Movimento(usuarioId, null, null,
                TipoTransacao.ESTORNO, NaturezaTransacao.CREDITO,
                valor, valor, ZERO,
                "Estorno de saque recusado", "estorno:saque:" + cobrancaId);
    }

    // -- Ciclo do turno ------------------------------------------------------

    /**
     * Reserva ao publicar: o lojista compromete valorEstimado x vagas.
     *
     * E o lastro do turno. Sem isto, publicado e so uma promessa — e era por
     * isso que a finalizacao conseguia creditar um entregador sem debitar
     * ninguem.
     */
    public static Movimento reserva(Long lojistaId, BigDecimal valor, Long turnoId, String tituloTurno) {
        return new Movimento(lojistaId, null, turnoId,
                TipoTransacao.RESERVA, NaturezaTransacao.DEBITO,
                valor, valor.negate(), valor,
                "Reserva do turno: " + tituloTurno, "reserva:turno:" + turnoId);
    }

    /**
     * Volta do bloqueado para o disponivel: turno cancelado, expirado, ou vaga
     * que ninguem preencheu.
     *
     * O motivo entra na chave porque um mesmo turno pode liberar por mais de
     * uma razao ao longo da vida — a sobra das vagas vazias na finalizacao e um
     * evento diferente do cancelamento, e cada um precisa da propria chave.
     */
    public static Movimento liberacaoDeReserva(Long lojistaId, BigDecimal valor, Long turnoId,
                                               String descricao, MotivoLiberacao motivo) {
        return new Movimento(lojistaId, null, turnoId,
                TipoTransacao.LIBERACAO_RESERVA, NaturezaTransacao.CREDITO,
                valor, valor, valor.negate(),
                descricao, "liberacao:turno:" + turnoId + ":" + motivo.chave());
    }

    /**
     * Lado do lojista na liquidacao: sai do BLOQUEADO, nao do disponivel.
     *
     * O dinheiro ja tinha sido separado quando o turno foi publicado —
     * finalizar so transfere o que o lojista comprometeu naquele momento. E por
     * isso que finalizar nao pode dar saldo insuficiente e nao precisa da
     * confirmacao de ninguem.
     */
    public static Movimento pagamentoEnviado(Long lojistaId, Long entregadorId, BigDecimal valor,
                                             Long turnoId, String tituloTurno, String chave) {
        return new Movimento(lojistaId, entregadorId, turnoId,
                TipoTransacao.PAGAMENTO_ENVIADO, NaturezaTransacao.DEBITO,
                valor, ZERO, valor.negate(),
                "Pagamento do turno: " + tituloTurno, chave);
    }

    /** Lado do entregador na liquidacao: entra no disponivel, sacavel na hora. */
    public static Movimento pagamentoRecebido(Long entregadorId, Long lojistaId, BigDecimal valor,
                                              Long turnoId, String tituloTurno, String chave) {
        return new Movimento(entregadorId, lojistaId, turnoId,
                TipoTransacao.PAGAMENTO_RECEBIDO, NaturezaTransacao.CREDITO,
                valor, valor, ZERO,
                "Turno finalizado: " + tituloTurno, chave);
    }

    /** Efeito no patrimonio (disponivel + bloqueado). Zero em movimento interno. */
    public BigDecimal deltaTotal() {
        return deltaDisponivel.add(deltaBloqueado);
    }

    /** Por que uma reserva voltou ao disponivel — entra na chave de idempotencia. */
    public enum MotivoLiberacao {

        CANCELAMENTO("cancelamento"),
        EXPIRACAO("expiracao"),
        /** Vagas que ninguem preencheu, devolvidas quando o turno e finalizado. */
        SOBRA("sobra");

        private final String chave;

        MotivoLiberacao(String chave) {
            this.chave = chave;
        }

        public String chave() {
            return chave;
        }
    }
}
