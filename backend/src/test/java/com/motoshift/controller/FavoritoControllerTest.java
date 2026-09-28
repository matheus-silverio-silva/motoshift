package com.motoshift.controller;

import com.motoshift.config.ApiExceptionHandler;
import com.motoshift.dto.FavoritoResponse;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.security.JwtAuthFilter;
import com.motoshift.security.JwtService;
import com.motoshift.security.RespostaDeErro;
import com.motoshift.security.SecurityConfig;
import com.motoshift.service.FavoritoService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** A camada web dos favoritos: só o lojista, e o dono sai do token. */
@WebMvcTest(FavoritoController.class)
@Import({SecurityConfig.class, JwtAuthFilter.class, JwtService.class,
         RespostaDeErro.class, ApiExceptionHandler.class})
@ActiveProfiles("test")
class FavoritoControllerTest {

    @Autowired private MockMvc mvc;
    @Autowired private JwtService jwt;

    // O filtro JWT confere que a conta do token existe; aqui toda conta existe.
    @MockBean private UsuarioRepository usuariosDoFiltro;
    @MockBean private FavoritoService favoritos;

    private final FavoritoResponse ricardo =
            new FavoritoResponse(9L, "Ricardo Souza", null, 4.9, 4.8, LocalDateTime.now());

    @BeforeEach
    void contasDoTokenExistem() {
        when(usuariosDoFiltro.existsById(anyLong())).thenReturn(true);
    }

    @Test
    @DisplayName("o entregador não tem favoritos: 403 nas três rotas, e o serviço nem é chamado")
    void entregadorRecusado() throws Exception {
        String token = bearer(9L, "motoboy");
        mvc.perform(get("/api/favoritos").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isForbidden());
        mvc.perform(put("/api/favoritos/7").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isForbidden());
        mvc.perform(delete("/api/favoritos/7").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isForbidden());
        verify(favoritos, never()).favoritar(any(), any());
        verify(favoritos, never()).desfavoritar(any(), any());
        verify(favoritos, never()).listar(any());
    }

    @Test
    @DisplayName("o lojista favorita, lista e desfavorita; o id dele sai do token")
    void lojista() throws Exception {
        String token = bearer(2L, "lojista");
        when(favoritos.favoritar(2L, 9L)).thenReturn(ricardo);
        when(favoritos.listar(2L)).thenReturn(List.of(ricardo));

        mvc.perform(put("/api/favoritos/9").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.motoboyId").value(9))
                .andExpect(jsonPath("$.nome").value("Ricardo Souza"));
        mvc.perform(get("/api/favoritos").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].motoboyId").value(9));
        mvc.perform(delete("/api/favoritos/9").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isNoContent());
        verify(favoritos).desfavoritar(2L, 9L);
    }

    @Test
    @DisplayName("dois cliques ao mesmo tempo: a chave barra o segundo, que é refeito e acha o favorito")
    void corrida() throws Exception {
        when(favoritos.favoritar(2L, 9L))
                .thenThrow(new DataIntegrityViolationException("pk_favoritos"))
                .thenReturn(ricardo);

        mvc.perform(put("/api/favoritos/9").header(HttpHeaders.AUTHORIZATION, bearer(2L, "lojista")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.motoboyId").value(9));
        verify(favoritos, times(2)).favoritar(2L, 9L);
    }

    private String bearer(long usuarioId, String tipo) {
        return "Bearer " + jwt.gerar(usuarioId, "usuario" + usuarioId + "@teste.com", tipo);
    }
}
