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
 * regerar a massa do Railway, que envelhece. A porta é a variável de ambiente
 * {@code MOTOSHIFT_SEED_RESET}, com um de dois valores exatos:
 * <ul>
 *   <li>{@code confirmo} — apaga só a massa (contas {@code @teste.com} e o
 *       que foi feito com elas) e a recria. Contas reais ficam.</li>
 *   <li>{@code confirmo-apagar-tudo} — apaga TODOS os dados de negócio,
 *       contas reais inclusive, e recria a massa. O schema e o
 *       {@code flyway_schema_history} ficam.</li>
 * </ul>
 * Qualquer outra coisa — ausente, vazia, "sim", "CONFIRMO", " confirmo",
 * "confirmo-apagar", "apagar-tudo" — não faz nada e não loga nada: sem um dos
 * dois valores, o boot é idêntico ao de antes desta classe existir.
 *
 * <p>Uma falha no reset é registrada e o app sobe assim mesmo: cada modo é
 * uma transação só, então falhar significa que nada foi apagado. Derrubar o
 * boot por isso colocaria o Railway num laço de restart por causa de uma
 * operação de manutenção.
 *
 * <p>Procedimento de produção: README, seção "Resetar a massa de demonstração".
 */
@Component
public class ResetDaMassaNoBoot implements ApplicationRunner {

    /** Só a massa. */
    static final String CONFIRMACAO = "confirmo";

    /** Todos os dados de negócio — contas reais inclusive. */
    static final String CONFIRMACAO_TOTAL = "confirmo-apagar-tudo";

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
        if (CONFIRMACAO.equals(trava)) {
            log.warn("[massa] MOTOSHIFT_SEED_RESET=confirmo — resetando a massa de demonstracao");
            executar(massa::resetar);
        } else if (CONFIRMACAO_TOTAL.equals(trava)) {
            log.warn("[massa] MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo — apagando TODOS os dados "
                    + "de negocio (contas reais inclusive) e recriando a massa");
            executar(massa::apagarTudoERecriar);
        }
    }

    private void executar(Runnable reset) {
        try {
            reset.run();
        } catch (RuntimeException e) {
            log.error("[massa] reset falhou e foi desfeito por inteiro; nada foi apagado", e);
        }
        // Repetido de proposito ao final, onde quem le o log do deploy vai olhar.
        log.warn("[massa] REMOVA a variavel MOTOSHIFT_SEED_RESET do servico agora. "
                + "Enquanto ela existir, todo deploy e todo restart apagam e recriam a massa.");
    }
}
