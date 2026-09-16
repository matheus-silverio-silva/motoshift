package com.motoshift.service;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.LoginRequest;
import com.motoshift.dto.RegistroRequest;
import com.motoshift.entity.Usuario;
import com.motoshift.security.JwtService;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UsuarioRepository repo;

    // Cadastro cria carteira para qualquer usuario; sem este mock registrar()
    // estoura com NullPointerException.
    @Mock
    private CarteiraService carteiras;

    // Encoder e JWT entram de verdade, nao mockados: a regra que interessa
    // testar aqui e justamente "a senha confere?" e "sai um token valido?".
    private final PasswordEncoder encoder = new BCryptPasswordEncoder();

    private AuthService authService;

    private Usuario usuarioValido;

    @BeforeEach
    void setUp() {
        authService = new AuthService(repo, carteiras, encoder, new JwtService("", 168));

        usuarioValido = new Usuario();
        // id é gerado pelo JPA (sem setter); simula um usuário já persistido
        ReflectionTestUtils.setField(usuarioValido, "id", 1L);
        usuarioValido.setEmail("motoboy@teste.com");
        usuarioValido.setSenha(encoder.encode("senha123"));
        usuarioValido.setNome("Carlos Mendes");
        usuarioValido.setTipo("motoboy");

        // O contador do RF01 mora no banco e e escrito por UPDATE direto. Com o
        // repositorio mockado, estes stubs fazem o papel do banco: aplicam o
        // UPDATE na mesma instancia que o findByEmail devolve.
        lenient().doAnswer(inv -> {
            usuarioValido.setTentativasLogin(usuarioValido.getTentativasLogin() + 1);
            return 1;
        }).when(repo).registrarFalhaDeLogin(1L);
        lenient().doAnswer(inv -> {
            usuarioValido.setTentativasLogin(0);
            usuarioValido.setBloqueadoAte(inv.getArgument(1));
            return 1;
        }).when(repo).bloquearLogin(eq(1L), any());
        lenient().doAnswer(inv -> {
            usuarioValido.setTentativasLogin(0);
            usuarioValido.setBloqueadoAte(null);
            return 1;
        }).when(repo).liberarLogin(1L);
    }

    @Test
    @DisplayName("Cadastro cria carteira — inclusive para lojista, que antes nao tinha")
    void registrar_criaCarteiraParaQualquerTipo() {
        RegistroRequest req = new RegistroRequest();
        req.setNome("Padaria Central");
        req.setEmail("lojista@teste.com");
        req.setTelefone("41999999999");
        req.setTipo("lojista");
        req.setDocumentoFederal("12345678000199"); // CNPJ: 14 digitos
        req.setSenha("senha123");

        Usuario salvo = new Usuario();
        ReflectionTestUtils.setField(salvo, "id", 42L);
        salvo.setNome("Padaria Central");
        salvo.setEmail("lojista@teste.com");
        salvo.setTelefone("41999999999");
        salvo.setTipo("lojista");

        when(repo.existsByEmail("lojista@teste.com")).thenReturn(false);
        when(repo.save(any(Usuario.class))).thenReturn(salvo);

        authService.registrar(req);

        verify(carteiras).obterOuCriar(42L);
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

    @Test
    @DisplayName("Cadastro grava a senha com hash BCrypt, nunca em texto puro")
    void registrar_gravaSenhaComHash() {
        RegistroRequest req = new RegistroRequest();
        req.setNome("Carlos Mendes");
        req.setEmail("novo@teste.com");
        req.setTelefone("41988887777");
        req.setTipo("motoboy");
        req.setDocumentoFederal("12345678900");
        req.setSenha("senha123");

        when(repo.existsByEmail("novo@teste.com")).thenReturn(false);
        when(repo.save(any(Usuario.class))).thenAnswer(inv -> {
            Usuario u = inv.getArgument(0);
            ReflectionTestUtils.setField(u, "id", 7L);
            return u;
        });

        authService.registrar(req);

        ArgumentCaptor<Usuario> captor = ArgumentCaptor.forClass(Usuario.class);
        verify(repo).save(captor.capture());

        String gravada = captor.getValue().getSenha();
        assertThat(gravada).isNotEqualTo("senha123");
        assertThat(gravada).startsWith("$2a$");
        assertThat(encoder.matches("senha123", gravada)).isTrue();
    }

    @Test
    @DisplayName("Senha em texto puro no banco nao entra mais — o login so conhece BCrypt")
    void login_senhaEmTextoPuro_naoConfere() {
        // Havia um ramo que comparava a senha em claro e a migrava. A V9
        // converteu as contas antigas no banco e o ramo saiu: se sobrar uma
        // linha assim, ela nao autentica, e nada e regravado pelo login.
        Usuario legado = new Usuario();
        ReflectionTestUtils.setField(legado, "id", 2L);
        legado.setEmail("legado@teste.com");
        legado.setSenha("senha123");
        legado.setTipo("motoboy");

        when(repo.findByEmail("legado@teste.com")).thenReturn(Optional.of(legado));

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> authService.login(buildLoginRequest("legado@teste.com", "senha123")))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(401));

        assertThat(legado.getSenha()).isEqualTo("senha123");
        verify(repo, never()).save(any());
    }

    @Test
    @DisplayName("RF01 — e-mail sem conta nao gera contador nem bloqueio")
    void login_emailInexistente_naoGuardaEstado() {
        when(repo.findByEmail(anyString())).thenReturn(Optional.empty());

        // O mapa antigo criava uma entrada por e-mail digitado. Agora, sem
        // conta, nao ha onde (nem por que) contar.
        for (int i = 0; i < 10; i++) {
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> authService.login(buildLoginRequest("inventado@x.com", "a")))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(401));
        }

        verify(repo, never()).registrarFalhaDeLogin(any());
        verify(repo, never()).bloquearLogin(any(), any());
    }

    @Test
    @DisplayName("RF01 — o bloqueio vem do banco: outra instancia do servico tambem barra")
    void login_bloqueioSobreviveANovaInstancia() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));
        LoginRequest errado = buildLoginRequest("motoboy@teste.com", "senhaErrada");

        for (int i = 0; i < 5; i++) {
            try { authService.login(errado); } catch (ResponseStatusException ignored) {}
        }

        // "Restart": um AuthService novo, sem nenhum estado em memoria. Com o
        // mapa antigo este login passaria; o bloqueio estava so no objeto velho.
        AuthService depoisDoDeploy = new AuthService(repo, carteiras, encoder, new JwtService("", 168));
        LoginRequest certo = buildLoginRequest("motoboy@teste.com", "senha123");

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> depoisDoDeploy.login(certo))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(429));
    }

    @Test
    @DisplayName("O token emitido no login identifica o usuario que logou")
    void login_tokenCarregaIdentidadeDoUsuario() {
        when(repo.findByEmail("motoboy@teste.com")).thenReturn(Optional.of(usuarioValido));

        AuthResponse resp = authService.login(buildLoginRequest("motoboy@teste.com", "senha123"));

        UsuarioAutenticado lido = new JwtService("", 168).ler(resp.getToken());

        assertThat(lido.id()).isEqualTo(1L);
        assertThat(lido.email()).isEqualTo("motoboy@teste.com");
        assertThat(lido.tipo()).isEqualTo("motoboy");
    }

    // --------------------------------------------------------
    private LoginRequest buildLoginRequest(String email, String senha) {
        LoginRequest req = new LoginRequest();
        req.setEmail(email);
        req.setSenha(senha);
        return req;
    }
}
