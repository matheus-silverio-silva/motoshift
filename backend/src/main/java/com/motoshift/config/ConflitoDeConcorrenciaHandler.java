package com.motoshift.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Traduz o conflito da trava otimista da carteira em 409, com uma mensagem que
 * o app pode mostrar.
 *
 * A Carteira ganhou {@code @Version} para impedir lost update: duas operacoes
 * simultaneas na mesma carteira — o entregador sacando enquanto o lojista
 * confirma um pagamento, por exemplo — faziam leitura-modificacao-escrita em
 * cima do mesmo saldo e uma sobrescrevia a outra em silencio.
 *
 * So que a trava sozinha resolve metade do problema: o lost update silencioso
 * virou um HTTP 500 generico, e 500 e "o servidor quebrou". Aqui nao quebrou
 * nada — duas pessoas mexeram no mesmo saldo ao mesmo tempo, uma perdeu a
 * corrida, e refazer a operacao funciona. Isso e 409 Conflict.
 *
 * A escolha e por mapear em vez de {@code @Retryable}: repetir sozinho uma
 * operacao que mexe em dinheiro exige idempotencia de ponta a ponta (a chave
 * ja existe em Transacao, mas nem todo caminho a preenche). Devolver 409 e
 * deixar o cliente reenviar e o passo honesto enquanto isso nao esta fechado.
 */
@RestControllerAdvice
public class ConflitoDeConcorrenciaHandler {

    private static final Logger log =
            LoggerFactory.getLogger(ConflitoDeConcorrenciaHandler.class);

    @ExceptionHandler(ObjectOptimisticLockingFailureException.class)
    public ProblemDetail conflitoDeVersao(ObjectOptimisticLockingFailureException e) {
        // WARN e nao ERROR: e disputa esperada, nao falha do servico. Vale o
        // registro porque uma enxurrada disto aponta contencao real.
        log.warn("[carteira] conflito de versao em {}: {}",
                e.getPersistentClassName(), e.getMessage());

        ProblemDetail problema = ProblemDetail.forStatusAndDetail(
                HttpStatus.CONFLICT,
                "Outra operação alterou este saldo agora mesmo. Tente de novo.");
        problema.setTitle("Conflito de concorrência");
        return problema;
    }
}
