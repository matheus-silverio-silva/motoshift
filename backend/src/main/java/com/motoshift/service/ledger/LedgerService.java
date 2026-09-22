package com.motoshift.service.ledger;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * O unico lugar do backend que altera saldo.
 *
 * <p><b>Por que existe.</b> Antes havia dois: o {@code PagamentoTurnoService}
 * creditava o entregador e o {@code CarteiraService} debitava o saque. Nenhum
 * dos dois conhecia o outro, nenhum tocava em {@code saldoBloqueado}, e a
 * liquidacao de um turno creditava sem debitar ninguem — dinheiro nascendo. Com
 * um ponto so, "quem pode mexer no saldo" tem uma resposta que cabe em uma
 * linha, e as tres invariantes podem ser garantidas aqui em vez de torcidas em
 * cada chamador.
 *
 * <p><b>Toda mutacao passa por {@link #aplicar(Movimento)}</b>, que faz sempre
 * os mesmos cinco passos, nesta ordem:
 * <ol>
 *   <li>procura a chave de idempotencia — se ja existe, devolve o resultado
 *       anterior sem tocar em saldo;</li>
 *   <li>carrega (ou cria) a carteira do dono;</li>
 *   <li>aplica os deltas e recusa saldo negativo em qualquer um dos bolsos;</li>
 *   <li>grava o lancamento com o snapshot dos dois saldos;</li>
 *   <li>salva a carteira.</li>
 * </ol>
 *
 * <p><b>Propagacao MANDATORY, de proposito.</b> Este servico nunca abre
 * transacao: ele exige estar dentro de uma. Duas consequencias queridas — um
 * movimento de dinheiro fora de transacao falha alto em vez de commitar
 * sozinho, e a liquidacao de um turno acontece na MESMA transacao que muda o
 * status do turno, entao nao existe o estado "turno finalizado mas nao pago".
 *
 * <p><b>Onde fica o retry.</b> {@link Carteira} tem {@code @Version}, e duas
 * operacoes simultaneas na mesma carteira fazem a segunda falhar com
 * {@code ObjectOptimisticLockingFailureException}. O retry NAO pode morar aqui
 * dentro: quando essa excecao aparece, a transacao inteira ja esta marcada para
 * rollback, e repetir so a parte do ledger commitaria uma metade. Ele mora em
 * {@link RetentativaOtimista}, aplicado por quem ABRE a transacao — a operacao
 * inteira e refeita do zero. Isso e seguro justamente por causa do passo 1: o
 * que ja tinha sido gravado e reencontrado pela chave em vez de lancado de novo.
 *
 * <p>As invariantes que este servico sustenta estao em
 * {@code docs/financeiro/FLUXO-FINANCEIRO.md} e sao conferidas por
 * {@code ConsistenciaService.verificarConsistencia()}.
 */
@Service
public class LedgerService {

    private static final Logger log = LoggerFactory.getLogger(LedgerService.class);

    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;

    public LedgerService(CarteiraRepository carteiraRepo, TransacaoRepository transacaoRepo) {
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
    }

    /**
     * Aplica um movimento de uma ponta so: recarga, saque, reserva, liberacao.
     *
     * @return o lancamento gravado — ou o anterior, se a chave ja existia
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public Transacao aplicar(Movimento m) {
        return aplicar(m, null);
    }

    /**
     * Transfere entre duas carteiras, gravando os dois lados com o mesmo
     * {@code operacaoId}.
     *
     * <p>Os dois lancamentos sao do mesmo evento visto de lados opostos: o
     * lojista ve um {@code pagamento_enviado}, o entregador um
     * {@code pagamento_recebido}. Na mesma transacao, entao ou os dois existem
     * ou nenhum — o meio do caminho, um lado debitado sem o outro creditado,
     * nao e um estado alcancavel.
     *
     * <p>Se a operacao ja tinha sido feita, os dois lados sao reencontrados
     * pelas chaves e nada se move: e isto que faz finalizar um turno duas vezes
     * transferir uma vez so.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public Transferencia transferir(Movimento debito, Movimento credito) {
        if (debito.valor().compareTo(credito.valor()) != 0) {
            // Uma transferencia com pernas de valor diferente cria ou destroi
            // dinheiro. Nao ha caso de uso legitimo; e sempre erro de quem chamou.
            throw new IllegalArgumentException(
                    "Transferencia desbalanceada: debito " + debito.valor()
                            + " != credito " + credito.valor());
        }

        // Reaproveita o id da operacao quando ela ja foi gravada antes, para que
        // uma repeticao nao invente um agrupamento novo para as mesmas linhas.
        UUID operacaoId = transacaoRepo.findByIdempotencyKey(debito.idempotencyKey())
                .map(Transacao::getOperacaoId)
                .orElseGet(UUID::randomUUID);

        return new Transferencia(aplicar(debito, operacaoId), aplicar(credito, operacaoId));
    }

    /**
     * Aplica um movimento dentro de uma operacao que ja existe.
     *
     * <p>E o caso da retencao na fonte: o tributo retido pertence ao mesmo
     * evento do pagamento que o originou, e o extrato precisa mostrar as tres
     * linhas — pagamento, ISS, IRRF — agrupadas pelo mesmo {@code operacaoId}.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public Transacao aplicarNaOperacao(Movimento m, UUID operacaoId) {
        if (operacaoId == null) {
            throw new IllegalArgumentException("aplicarNaOperacao sem operacaoId.");
        }
        return aplicar(m, operacaoId);
    }

    /** Os dois lados de uma transferencia, ja gravados. */
    public record Transferencia(Transacao debito, Transacao credito) {

        public UUID operacaoId() {
            return debito.getOperacaoId();
        }
    }

    // -- O caminho unico -----------------------------------------------------

    private Transacao aplicar(Movimento m, UUID operacaoId) {
        // 1. Ja aconteceu? Entao o resultado ja existe e nada se move.
        Transacao anterior = transacaoRepo.findByIdempotencyKey(m.idempotencyKey()).orElse(null);
        if (anterior != null) {
            log.debug("[ledger] {} ja aplicado; devolvendo o lancamento {}",
                    m.idempotencyKey(), anterior.getId());
            return anterior;
        }

        // 2. A carteira do dono. Criada na hora quando e o primeiro movimento
        //    da vida daquele usuario — cadastro antigo pode nao ter uma.
        Carteira carteira = carteiraRepo.findByUsuarioId(m.usuarioId())
                .orElseGet(() -> {
                    Carteira nova = new Carteira();
                    nova.setUsuarioId(m.usuarioId());
                    return nova;
                });

        // 3. Os deltas, com o chao em zero nos dois bolsos.
        BigDecimal disponivel = carteira.getSaldoDisponivel().add(m.deltaDisponivel());
        BigDecimal bloqueado = carteira.getSaldoBloqueado().add(m.deltaBloqueado());
        exigirNaoNegativo(m, disponivel, bloqueado);

        carteira.setSaldoDisponivel(disponivel);
        carteira.setSaldoBloqueado(bloqueado);

        // 4. O lancamento vai ao banco com flush ANTES de a carteira ser salva:
        //    se duas execucoes com a mesma chave passarem juntas pelo passo 1, o
        //    indice unico barra a segunda aqui e a transacao inteira volta — o
        //    saldo junto. A checagem do passo 1 e o caminho rapido; a garantia
        //    e o indice.
        Transacao tx = new Transacao();
        tx.setUsuarioId(m.usuarioId());
        tx.setContraparteId(m.contraparteId());
        tx.setTurnoId(m.turnoId());
        tx.setTipo(m.tipo());
        tx.setNatureza(m.natureza());
        tx.setValor(m.valor());
        tx.setDescricao(m.descricao());
        tx.setStatus(StatusTransacao.CONCLUIDO);
        tx.setIdempotencyKey(m.idempotencyKey());
        tx.setOperacaoId(operacaoId);
        tx.setSaldoDisponivelApos(disponivel);
        tx.setSaldoBloqueadoApos(bloqueado);

        try {
            transacaoRepo.saveAndFlush(tx);
        } catch (DataIntegrityViolationException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Esta operação já está sendo processada.");
        }

        // 5. A carteira por ultimo. O @Version dela e o que impede duas
        //    liquidacoes simultaneas de lerem o mesmo saldo e uma sobrescrever
        //    a outra; quem perde a corrida e repetido por RetentativaOtimista.
        carteiraRepo.save(carteira);

        return tx;
    }

    /**
     * Invariante (a): nenhum saldo negativo, em nenhum dos dois bolsos.
     *
     * <p>Barrada aqui e nao em cada chamador porque e justamente o tipo de
     * regra que um caminho novo esquece. Os dois bolsos importam: bloqueado
     * negativo seria liberar uma reserva que nao existe — dinheiro saindo do
     * nada pela porta dos fundos.
     */
    private void exigirNaoNegativo(Movimento m, BigDecimal disponivel, BigDecimal bloqueado) {
        if (disponivel.signum() < 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Saldo disponível insuficiente: faltam "
                            + emReais(disponivel.abs()) + ".");
        }
        if (bloqueado.signum() < 0) {
            // Nao e erro do usuario: significa que o backend tentou liberar mais
            // reserva do que bloqueou. Barulho alto, com a chave no log, e nao
            // um saldo estranho que aparece tres telas adiante.
            log.error("[ledger] {} deixaria o bloqueado de {} em {}",
                    m.idempotencyKey(), m.usuarioId(), bloqueado);
            throw new IllegalStateException(
                    "Liberação maior que a reserva em " + m.idempotencyKey());
        }
    }

    /** "R$ 1234.50" -> "R$ 1.234,50". Mensagem de erro tambem e interface. */
    public static String emReais(BigDecimal valor) {
        return String.format(new java.util.Locale("pt", "BR"), "R$ %,.2f", valor);
    }
}
