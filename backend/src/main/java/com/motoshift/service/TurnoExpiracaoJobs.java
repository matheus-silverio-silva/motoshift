package com.motoshift.service;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * O relógio dos jobs de turno: de 5 em 5 minutos, chama o
 * {@link TurnoExpiracaoService}.
 *
 * <p>Aqui só há agendamento — a regra de cada job está no serviço. Separados
 * porque as duas coisas têm condições diferentes de existir: o serviço existe
 * sempre (a massa de demonstração o usa para vencer um turno da história, e
 * os testes o chamam direto); o agendamento só com
 * {@code motoshift.jobs.habilitados=true}.
 *
 * <p><b>Com réplica, os jobs rodariam em todas as instâncias.</b> Hoje isso é
 * inofensivo — {@code criarUnica} deduplica a notificação, as mudanças de
 * status são idempotentes e o dinheiro tem chave de idempotência —, mas o
 * trabalho seria feito N vezes. Enquanto não houver um lock distribuído
 * (ShedLock e uma tabela própria), a saída é operacional e está aqui,
 * explícita: subir as réplicas com {@code MOTOSHIFT_JOBS_HABILITADOS=false} e
 * deixar uma só instância com os jobs ligados.
 */
@Component
@ConditionalOnProperty(name = "motoshift.jobs.habilitados", havingValue = "true", matchIfMissing = true)
public class TurnoExpiracaoJobs {

    private final TurnoExpiracaoService servico;

    public TurnoExpiracaoJobs(TurnoExpiracaoService servico) {
        this.servico = servico;
    }

    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    public void expirarTurnosNaoPreenchidos() {
        servico.expirarTurnosNaoPreenchidos();
    }

    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    public void avisarTurnosProximosDoVencimento() {
        servico.avisarTurnosProximosDoVencimento();
    }

    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    public void cobrarFinalizacaoPendente() {
        servico.cobrarFinalizacaoPendente();
    }

    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    public void finalizarTurnosEsquecidos() {
        servico.finalizarTurnosEsquecidos();
    }
}
