package com.motoshift;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

import java.time.DateTimeException;
import java.time.ZoneId;
import java.util.TimeZone;

@SpringBootApplication
@EnableScheduling
public class MotoshiftApplication {

    /** A variável de ambiente que escolhe o fuso do sistema. */
    public static final String VARIAVEL_DO_FUSO = "MOTOSHIFT_FUSO";

    /** O fuso de quem usa o MotoShift: Curitiba (horário de Brasília). */
    public static final String FUSO_PADRAO = "America/Sao_Paulo";

    public static void main(String[] args) {
        aplicarFuso(System.getenv(VARIAVEL_DO_FUSO));
        SpringApplication.run(MotoshiftApplication.class, args);
    }

    /**
     * Põe a JVM no fuso do sistema, antes de o Spring subir (SCRUM-48).
     *
     * <p>O MotoShift tem um fuso só. O app manda as datas do turno como hora
     * local, sem fuso ("2026-10-07T19:00:00"), as colunas são {@code timestamp}
     * sem fuso e as entidades usam {@code LocalDateTime}: nada é convertido no
     * caminho, então a única coisa que precisa estar certa é o "agora" do
     * servidor. Sem isto ele era o do container — UTC no Render, três horas à
     * frente de Curitiba —, e toda regra que compara uma data do turno com
     * {@code LocalDateTime.now()} saía deslocada: as 2 h de antecedência viravam
     * 5 h, o turno expirava e era finalizado 3 h antes, e na DRE o que
     * acontecia depois das 21h caía no dia seguinte.
     *
     * <p>Aqui, e não num {@code @PostConstruct}: tem de valer antes do primeiro
     * {@code now()}, do Flyway, do Hibernate e dos jobs agendados.
     *
     * <p>Um fuso que não existe derruba o boot. {@code TimeZone.getTimeZone}
     * devolveria GMT em silêncio para um nome errado — exatamente o defeito
     * que isto veio corrigir.
     *
     * @param configurado o valor de {@value #VARIAVEL_DO_FUSO}; nulo ou vazio
     *                    vale {@value #FUSO_PADRAO}
     * @return o fuso aplicado
     */
    static ZoneId aplicarFuso(String configurado) {
        String nome = configurado == null || configurado.isBlank() ? FUSO_PADRAO : configurado.trim();
        ZoneId fuso;
        try {
            fuso = ZoneId.of(nome);
        } catch (DateTimeException e) {
            throw new IllegalStateException(
                    VARIAVEL_DO_FUSO + " inválido: \"" + nome + "\". Use um fuso da base IANA, como "
                            + FUSO_PADRAO + " ou America/Manaus.", e);
        }
        TimeZone.setDefault(TimeZone.getTimeZone(fuso));
        return fuso;
    }
}
