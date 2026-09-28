package com.motoshift.controller;

import com.motoshift.config.ApiExceptionHandler;
import com.motoshift.dto.GorjetaResponse;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.security.JwtAuthFilter;
import com.motoshift.security.JwtService;
import com.motoshift.security.RespostaDeErro;
import com.motoshift.security.SecurityConfig;
import com.motoshift.service.GorjetaService;
import com.motoshift.service.ledger.RetentativaOtimista;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** A camada web da gorjeta: só o lojista dá, e o dono sai do token. */
@WebMvcTest(GorjetaController.class)
@Import({SecurityConfig.class, JwtAuthFilter.class, JwtService.class,
         RespostaDeErro.class, ApiExceptionHandler.class, RetentativaOtimista.class})
@ActiveProfiles("test")
class GorjetaControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private JwtService jwt;

    // O filtro JWT confere que a conta do token existe; aqui toda conta existe.
    @MockBean private UsuarioRepository usuariosDoFiltro;
    @MockBean private GorjetaService gorjetas;

    @BeforeEach
    void contasDoTokenExistem() {
        when(usuariosDoFiltro.existsById(anyLong())).thenReturn(true);
    }

    @Test
    @DisplayName("o entregador não dá gorjeta: 403, e o serviço nem é chamado")
    void entregadorRecusado() throws Exception {
        mvc.perform(post("/api/turnos/5/gorjetas")
                        .header(HttpHeaders.AUTHORIZATION, bearer(9L, "motoboy"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"entregadorId\": 9, \"valor\": 10}"))
                .andExpect(status().isForbidden());
        verify(gorjetas, never()).dar(any(), any(), any(), any());
    }

    @Test
    @DisplayName("o lojista dá; o id dele sai do token")
    void lojistaDa() throws Exception {
        when(gorjetas.dar(eq(5L), eq(2L), eq(9L), any()))
                .thenReturn(new GorjetaResponse(5L, 9L, new BigDecimal("10.00"), 77L, LocalDateTime.now()));

        mvc.perform(post("/api/turnos/5/gorjetas")
                        .header(HttpHeaders.AUTHORIZATION, bearer(2L, "lojista"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"entregadorId\": 9, \"valor\": 10}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.transacaoId").value(77));
    }

    @Test
    @DisplayName("sem entregador ou sem valor: 400 no contrato de erro")
    void validacao() throws Exception {
        mvc.perform(post("/api/turnos/5/gorjetas")
                        .header(HttpHeaders.AUTHORIZATION, bearer(2L, "lojista"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"valor\": 10}"))
                .andExpect(status().isBadRequest());
    }

    private String bearer(long usuarioId, String tipo) {
        return "Bearer " + jwt.gerar(usuarioId, "usuario" + usuarioId + "@teste.com", tipo);
    }
}
