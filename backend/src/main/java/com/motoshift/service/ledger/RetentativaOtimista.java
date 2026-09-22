package com.motoshift.service.ledger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Component;

import java.util.function.Supplier;

/**
 * Repete uma operacao de dinheiro que perdeu a corrida pela carteira.
 *
 * <p><b>O problema.</b> {@link com.motoshift.entity.Carteira} tem
 * {@code @Version}. Quando duas operacoes mexem na mesma carteira ao mesmo
 * tempo — o turno de um lojista liquidando enquanto ele publica outro, dois
 * entregadores sendo pagos no mesmo instante — a segunda a commitar descobre
 * que a versao mudou e falha com
 * {@code ObjectOptimisticLockingFailureException}. Sem a trava, uma
 * sobrescreveria o saldo da outra e o dinheiro sumiria; com a trava, a operacao
 * simplesmente precisa ser refeita.
 *
 * <p><b>Por que o retry fica aqui e nao dentro do {@link LedgerService}.</b>
 * Quando a excecao aparece, a transacao inteira ja esta condenada ao rollback:
 * repetir so a chamada do ledger tentaria gravar dentro de uma transacao morta.
 * O retry so faz sentido em volta de quem ABRE a transacao, refazendo a
 * operacao do zero — e por isso ele e aplicado no controller e no job, nao no
 * meio do servico.
 *
 * <p><b>Por que repetir e seguro.</b> Toda gravacao do ledger passa por uma
 * chave de idempotencia deterministica. Na segunda tentativa, o que ja tinha
 * commitado e reencontrado pela chave em vez de lancado outra vez; o que nao
 * commitou e refeito. O pior caso de uma repeticao e trabalho perdido, nunca
 * dinheiro em dobro.
 *
 * <p>Tres tentativas porque a colisao e rara e nao se acumula: se tres seguidas
 * falharem, o problema nao e concorrencia pontual e insistir so empurra a fila.
 * Quem chamou recebe a excecao e o usuario recebe 409.
 */
@Component
public class RetentativaOtimista {

    private static final Logger log = LoggerFactory.getLogger(RetentativaOtimista.class);

    static final int TENTATIVAS = 3;

    /**
     * Espera base entre tentativas, em milissegundos.
     *
     * <p><b>Repetir na hora não resolve nada.</b> Quando várias operações
     * disputam a mesma carteira, todas falham no mesmo instante e, sem espera,
     * todas tentam de novo no mesmo instante — colidindo em bloco outra vez. O
     * teste de concorrência mostrou isso: oito liquidações simultâneas
     * esgotavam as três tentativas em ~70 ms, sem que nenhuma tivesse chance de
     * passar sozinha.
     *
     * <p>A espera cresce a cada tentativa e leva um componente aleatório, que é
     * o que de fato desempata: com atrasos iguais, as threads voltariam a
     * marchar juntas.
     */
    private static final long ESPERA_BASE_MS = 15;

    public <T> T executar(String operacao, Supplier<T> acao) {
        ObjectOptimisticLockingFailureException ultima = null;

        for (int tentativa = 1; tentativa <= TENTATIVAS; tentativa++) {
            try {
                return acao.get();
            } catch (ObjectOptimisticLockingFailureException e) {
                ultima = e;
                log.warn("[ledger] {} perdeu a corrida pela carteira (tentativa {}/{})",
                        operacao, tentativa, TENTATIVAS);
                if (tentativa < TENTATIVAS) {
                    esperar(tentativa);
                }
            }
        }

        log.error("[ledger] {} falhou em {} tentativas por concorrencia na carteira",
                operacao, TENTATIVAS);
        throw ultima;
    }

    /**
     * Recuo com jitter antes da próxima tentativa.
     *
     * <p>Três tentativas cobrem a disputa que acontece de verdade: duas ou três
     * operações caindo na mesma carteira no mesmo momento. Uma carteira sob
     * dezenas de escritas simultâneas é outro problema — pressão sustentada,
     * não colisão pontual — e insistir ali só empurra a fila para a frente. Quem
     * chamou recebe a exceção, e o usuário, um 409.
     */
    private static void esperar(int tentativa) {
        long espera = ESPERA_BASE_MS * tentativa
                + java.util.concurrent.ThreadLocalRandom.current().nextLong(ESPERA_BASE_MS);
        try {
            Thread.sleep(espera);
        } catch (InterruptedException e) {
            // Alguém pediu para parar: propaga o sinal e desiste do retry em
            // vez de engolir a interrupção e continuar trabalhando.
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Retry do ledger interrompido", e);
        }
    }

    /** Mesma garantia, para operacao que nao devolve nada. */
    public void executar(String operacao, Runnable acao) {
        executar(operacao, () -> {
            acao.run();
            return null;
        });
    }
}
