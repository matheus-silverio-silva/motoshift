package com.motoshift.service;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.LoginRequest;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UsuarioRepository repo;

    @InjectMocks
    private AuthService authService;

    private Usuario usuarioValido;

    @BeforeEach
    void setUp() {
        usuarioValido = new Usuario();
        usuarioValido.setEmail("motoboy@teste.com");
        usuarioValido.setSenha("senha123");
        usuarioValido.setNome("Carlos Mendes");
        usuarioValido.setTipo("motoboy");
    }

    @Test
    @DisplayName("Login com credenciais válidas retorna token e perfil do usuário")
    void login_credenciaisValidas_retornaAuthResponse() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));

        LoginRequest req = buildLoginRequest("motoboy@teste.com", "senha123");

        AuthResponse resp = authService.login(req);

        assertThat(resp).isNotNull();
        assertThat(resp.getToken()).isNotBlank();
        assertThat(resp.getUsuario().getEmail()).isEqualTo("motoboy@teste.com");
    }

    @Test
    @DisplayName("Login com senha incorreta lança 401 com tentativas restantes")
    void login_senhaIncorreta_lanca401() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));

        LoginRequest req = buildLoginRequest("motoboy@teste.com", "senhaErrada");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> authService.login(req))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(401));
    }

    @Test
    @DisplayName("Login com e-mail inexistente lança 401")
    void login_emailInexistente_lanca401() {
        when(repo.findByEmail(anyString())).thenReturn(Optional.empty());

        LoginRequest req = buildLoginRequest("naoexiste@teste.com", "qualquer");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> authService.login(req))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(401));
    }

    @Test
    @DisplayName("RF01 — 5ª tentativa falha bloqueia a conta com status 429")
    void login_apos5TentativasFalhas_bloqueiaContaComStatus429() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));

        LoginRequest req = buildLoginRequest("motoboy@teste.com", "senhaErrada");

        // Primeiras 4 tentativas geram 401
        for (int i = 0; i < 4; i++) {
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> authService.login(req))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(401));
        }

        // 5ª tentativa dispara o bloqueio: 429
        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> authService.login(req))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(429));
    }

    @Test
    @DisplayName("RF01 — qualquer tentativa após bloqueio continua retornando 429")
    void login_contaBloqueada_continuaRetornando429() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));

        LoginRequest req = buildLoginRequest("motoboy@teste.com", "senhaErrada");

        // Dispara o bloqueio (5 tentativas)
        for (int i = 0; i < 5; i++) {
            try { authService.login(req); } catch (ResponseStatusException ignored) {}
        }

        // Requisição após bloqueio ainda retorna 429
        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> authService.login(req))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(429));
    }

    @Test
    @DisplayName("Login bem-sucedido reseta o contador de tentativas")
    void login_sucessoAposErros_resetaContador() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));

        LoginRequest reqErrado  = buildLoginRequest("motoboy@teste.com", "senhaErrada");
        LoginRequest reqCorreto = buildLoginRequest("motoboy@teste.com", "senha123");

        // 3 tentativas erradas
        for (int i = 0; i < 3; i++) {
            try { authService.login(reqErrado); } catch (ResponseStatusException ignored) {}
        }

        // Login correto não lança exceção
        assertThatCode(() -> authService.login(reqCorreto)).doesNotThrowAnyException();

        // Depois do reset, uma nova falha volta para 401 (não 429)
        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> authService.login(reqErrado))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(401));
    }

    // --------------------------------------------------------
    private LoginRequest buildLoginRequest(String email, String senha) {
        LoginRequest req = new LoginRequest();
        req.setEmail(email);
        req.setSenha(senha);
        return req;
    }
}
