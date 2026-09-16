package com.motoshift.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * Reset da massa de demonstração no boot, em QUALQUER ambiente — inclusive
 * produção —, atrás de uma trava explícita.
 *
 * <p>Não é {@code @Profile("!prod")} de propósito: o motivo de existir é
 * regerar a massa do Railway, que envelhece. A porta é uma só: a variável de
 * ambiente {@code MOTOSHIFT_SEED_RESET} com o valor exato {@code confirmo}.
 * Ausente, vazia, "sim", "CONFIRMO" ou " confirmo" não fazem nada e não logam
 * nada — sem ela, o boot é idêntico ao de antes desta classe existir.
 *
 * <p>Uma falha no reset é registrada e o app sobe assim mesmo: o reset é uma
 * transação só, então falhar significa que nada foi apagado. Derrubar o boot
 * por isso colocaria o Railway num laço de restart por causa de uma operação
 * de manutenção.
 *
 * <p>Procedimento de produção: README, seção "Resetar a massa de demonstração".
 */
@Component
public class ResetDaMassaNoBoot implements ApplicationRunner {

    static final String CONFIRMACAO = "confirmo";

    private static final Logger log = LoggerFactory.getLogger(ResetDaMassaNoBoot.class);

    private final MassaDemonstracao massa;
    private final String trava;

    public ResetDaMassaNoBoot(MassaDemonstracao massa,
                              @Value("${MOTOSHIFT_SEED_RESET:}") String trava) {
        this.massa = massa;
        this.trava = trava;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!CONFIRMACAO.equals(trava)) return;

        log.warn("[massa] MOTOSHIFT_SEED_RESET=confirmo — resetando a massa de demonstracao");
        try {
            massa.resetar();
        } catch (RuntimeException e) {
            log.error("[massa] reset falhou e foi desfeito por inteiro; nada foi apagado", e);
        }
        // Repetido de proposito ao final, onde quem le o log do deploy vai olhar.
        log.warn("[massa] REMOVA a variavel MOTOSHIFT_SEED_RESET do servico agora. "
                + "Enquanto ela existir, todo deploy e todo restart apagam e recriam a massa.");
    }
}
