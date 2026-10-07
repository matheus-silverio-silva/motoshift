package com.motoshift.controller;

import com.motoshift.MotoshiftApplication;
import com.motoshift.dto.StatusResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;

/**
 * "O servidor está acordado?" — a rota mais barata da API (SCRUM-48).
 *
 * <p>No plano gratuito do Render o serviço dorme depois de 15 minutos sem
 * requisição e leva minutos para acordar. Três coisas chamam esta rota:
 * <ul>
 *   <li><b>o app</b>, ao abrir: enquanto ela não responde, a tela de login
 *       mostra "Acordando o servidor…" em vez de deixar o primeiro login
 *       falhar por tempo esgotado;
 *   <li><b>o monitor</b> (cron-job.org, UptimeRobot) a cada 10 minutos, que é
 *       o que impede o servidor de dormir;
 *   <li><b>quem fez o deploy</b>, para conferir que {@code horaServidor} é a
 *       hora de Brasília e qual commit está no ar.
 * </ul>
 *
 * <p>Pública e sem banco: não consulta tabela nenhuma, então responde assim
 * que o Spring sobe e não acorda o Neon à toa. Também fica fora do limite de
 * requisições — o monitor bate nela o dia inteiro. Não há nada sensível aqui:
 * hora, fuso e commit.
 *
 * <p>O {@code /actuator/health} continua existindo para o healthcheck da
 * hospedagem; este é o contrato do app, que não deve depender do formato do
 * Actuator.
 */
@RestController
@RequestMapping("/api/status")
@Tag(name = "Status", description = "Servidor no ar, hora e fuso (SCRUM-48)")
public class StatusController {

    private final String versao;

    /**
     * @param versao {@code motoshift.versao}: o commit que a hospedagem informa
     *               (no Render, {@code RENDER_GIT_COMMIT}) ou o que vier em
     *               {@code MOTOSHIFT_VERSAO}; vazio fora de produção
     */
    public StatusController(@Value("${motoshift.versao:}") String versao) {
        this.versao = resolverVersao(versao,
                MotoshiftApplication.class.getPackage().getImplementationVersion());
    }

    @Operation(summary = "Servidor no ar",
               description = "Responde sem token e sem consultar o banco. horaServidor traz o "
                       + "deslocamento do fuso; versao é o commit publicado ou a versão do pom.")
    @ApiResponse(responseCode = "200", description = "O servidor está respondendo")
    @GetMapping
    public StatusResponse status() {
        String agora = OffsetDateTime.now()
                .truncatedTo(ChronoUnit.SECONDS)
                .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        return new StatusResponse(true, agora, ZoneId.systemDefault().getId(), versao);
    }

    /**
     * O commit, encurtado para os 7 caracteres que o Git mostra; sem commit, a
     * versão do pom (que o jar traz no manifesto); sem nenhum dos dois —
     * rodando da IDE ou nos testes —, "dev".
     */
    static String resolverVersao(String commit, String versaoDoPom) {
        if (commit != null && !commit.isBlank()) {
            String c = commit.trim();
            return c.matches("[0-9a-fA-F]{8,40}") ? c.substring(0, 7) : c;
        }
        if (versaoDoPom != null && !versaoDoPom.isBlank()) return versaoDoPom.trim();
        return "dev";
    }
}
