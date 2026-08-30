package com.motoshift.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.config.ApiExceptionHandler;
import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.security.JwtAuthFilter;
import com.motoshift.security.JwtService;
import com.motoshift.security.RespostaDeErro;
import com.motoshift.security.SecurityConfig;
import com.motoshift.service.PagamentoTurnoService;
import com.motoshift.service.TurnoConsultaService;
import com.motoshift.service.TurnoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A camada web do turno, sem banco e sem regra de negocio.
 *
 * O projeto nao tinha nenhum {@code @WebMvcTest}: nada cobria o pedaco entre o
 * HTTP e o service — desserializacao, validacao, o formato do corpo de erro e a
 * decisao de de onde sai o id do usuario. Sao justamente os pontos que mudaram
 * agora, entao os servicos entram mockados e o que se verifica e o contrato.
 */
@WebMvcTest(TurnoController.class)
@Import({SecurityConfig.class, JwtAuthFilter.class, JwtService.class,
         RespostaDeErro.class, ApiExceptionHandler.class})
@ActiveProfiles("test")
class TurnoControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private JwtService jwt;

    @MockBean private TurnoService service;
    @MockBean private TurnoConsultaService consultas;
    @MockBean private PagamentoTurnoService pagamentos;

    @Test
    @DisplayName("publicar turno usa o id do token e ignora o lojistId do corpo")
    void criar_usaIdDoToken() throws Exception {
        when(service.criar(any(), eq(7L))).thenReturn(new TurnoResponse());

        String corpo = json.writeValueAsString(Map.of(
                "lojistId", 999,                       // tentativa de forjar o dono
                "titulo", "Turno da tarde",
                "dataInicio", LocalDateTime.now().plusHours(5).toString(),
                "dataFim", LocalDateTime.now().plusHours(9).toString(),
                "valorEstimado", 120.00));

        mvc.perform(post("/api/turnos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(7L, "lojista"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isCreated());

        ArgumentCaptor<Long> dono = ArgumentCaptor.forClass(Long.class);
        verify(service).criar(any(TurnoRequest.class), dono.capture());
        assertThat(dono.getValue()).isEqualTo(7L);
    }

    @Test
    @DisplayName("motoboy publicando turno leva 403 e o service nem e chamado")
    void criar_perfilErrado_403() throws Exception {
        String corpo = json.writeValueAsString(Map.of(
                "titulo", "Turno indevido",
                "dataInicio", LocalDateTime.now().plusHours(5).toString(),
                "dataFim", LocalDateTime.now().plusHours(9).toString(),
                "valorEstimado", 120.00));

        mvc.perform(post("/api/turnos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(7L, "motoboy"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.codigo").value("acesso_negado"));

        verify(service, never()).criar(any(), any());
    }

    @Test
    @DisplayName("erro de validacao responde no contrato {codigo, mensagem, campo}")
    void criar_semTitulo_devolveContratoDeErro() throws Exception {
        // Sem titulo: o @NotNull do TurnoRequest reprova antes de chegar ao service.
        String corpo = json.writeValueAsString(Map.of(
                "dataInicio", LocalDateTime.now().plusHours(5).toString(),
                "dataFim", LocalDateTime.now().plusHours(9).toString(),
                "valorEstimado", 120.00));

        mvc.perform(post("/api/turnos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(7L, "lojista"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(corpo))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("requisicao_invalida"))
                .andExpect(jsonPath("$.campo").value("titulo"))
                .andExpect(jsonPath("$.mensagem").isNotEmpty());

        verify(service, never()).criar(any(), any());
    }

    @Test
    @DisplayName("sem token a rota de publicar responde 401, tambem no contrato")
    void criar_semToken_401() throws Exception {
        mvc.perform(post("/api/turnos")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.codigo").value("nao_autenticado"));
    }

    private String bearer(long usuarioId, String tipo) {
        return "Bearer " + jwt.gerar(usuarioId, "usuario" + usuarioId + "@teste.com", tipo);
    }
}
