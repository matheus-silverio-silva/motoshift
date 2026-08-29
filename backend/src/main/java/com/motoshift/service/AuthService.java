package com.motoshift.service;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.LoginRequest;
import com.motoshift.dto.RegistroRequest;
import com.motoshift.dto.UsuarioResponse;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.security.JwtService;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class AuthService {

    private static final int MAX_TENTATIVAS = 5;
    private static final int BLOQUEIO_MINUTOS = 15;

    private final UsuarioRepository repo;
    private final CarteiraService carteiras;
    private final PasswordEncoder encoder;
    private final JwtService jwt;

    // RF01: rastreamento de tentativas em memória (suficiente para H2 dev)
    private final ConcurrentHashMap<String, AttemptInfo> tentativas = new ConcurrentHashMap<>();

    private static class AttemptInfo {
        int contador = 0;
        LocalDateTime bloqueadoAte = null;
    }

    public AuthService(UsuarioRepository repo,
                       CarteiraService carteiras,
                       PasswordEncoder encoder,
                       JwtService jwt) {
        this.repo = repo;
        this.carteiras = carteiras;
        this.encoder = encoder;
        this.jwt = jwt;
    }

    /**
     * Cadastro. Transacional porque grava duas coisas: o usuario e a carteira
     * dele. Sem isso, uma falha na criacao da carteira deixava o usuario
     * gravado e sem carteira — e o retry do cadastro respondia "E-mail ja
     * cadastrado", com a pessoa presa sem conseguir nem entrar nem repetir.
     */
    @Transactional
    public AuthResponse registrar(RegistroRequest req) {
        if (repo.existsByEmail(req.getEmail())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "E-mail já cadastrado");
        }

        // RF03 — Lojista exige CNPJ (14 dígitos); Motoboy exige CNH (11 dígitos)
        String tipoNorm = req.getTipo() == null ? "" : req.getTipo().toLowerCase();
        String doc = req.getDocumentoFederal();
        String digitos = doc == null ? "" : doc.replaceAll("\\D", "");

        if ("lojista".equals(tipoNorm)) {
            if (doc == null || doc.isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNPJ é obrigatório para cadastro como Lojista.");
            }
            if (digitos.length() != 14) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNPJ inválido. Deve conter 14 dígitos.");
            }
        } else if ("motoboy".equals(tipoNorm)) {
            if (doc == null || doc.isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNH é obrigatória para cadastro como Motoboy.");
            }
            if (digitos.length() != 11) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNH inválida. Deve conter 11 dígitos.");
            }
        } else {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Tipo de usuário inválido. Use 'lojista' ou 'motoboy'.");
        }

        Usuario u = new Usuario();
        u.setNome(req.getNome());
        u.setEmail(req.getEmail());
        u.setTelefone(req.getTelefone());
        u.setTipo(req.getTipo().toLowerCase());
        u.setDocumentoFederal(req.getDocumentoFederal());
        u.setSenha(encoder.encode(req.getSenha()));

        Usuario salvo = repo.save(u);

        // Carteira para QUALQUER usuario, nao so entregador: o lojista precisa
        // dela para reservar o valor do turno ao publicar. Criada zerada aqui
        // para que nenhum fluxo posterior precise lidar com carteira ausente.
        carteiras.obterOuCriar(salvo.getId());

        return new AuthResponse(tokenPara(salvo), UsuarioResponse.from(salvo));
    }

    public AuthResponse login(LoginRequest req) {
        String email = req.getEmail() != null ? req.getEmail().trim() : "";
        AttemptInfo info = tentativas.computeIfAbsent(email, k -> new AttemptInfo());

        // RF01: verifica bloqueio ativo
        if (info.bloqueadoAte != null && LocalDateTime.now().isBefore(info.bloqueadoAte)) {
            long minutos = ChronoUnit.MINUTES.between(LocalDateTime.now(), info.bloqueadoAte) + 1;
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Conta bloqueada. Tente novamente em " + minutos + " minuto(s).");
        }

        boolean credenciaisOk = repo.findByEmail(req.getEmail())
                .map(u -> senhaConfere(u, req.getSenha()))
                .orElse(false);

        if (!credenciaisOk) {
            info.contador++;
            if (info.contador >= MAX_TENTATIVAS) {
                info.bloqueadoAte = LocalDateTime.now().plusMinutes(BLOQUEIO_MINUTOS);
                info.contador = 0;
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "Muitas tentativas incorretas. Tente novamente em " + BLOQUEIO_MINUTOS + " minuto(s).");
            }
            int restantes = MAX_TENTATIVAS - info.contador;
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                    "Credenciais inválidas. " + restantes + " tentativa(s) restante(s).");
        }

        // Sucesso: reset do contador
        info.contador = 0;
        info.bloqueadoAte = null;

        Usuario u = repo.findByEmail(req.getEmail()).orElseThrow();
        return new AuthResponse(tokenPara(u), UsuarioResponse.from(u));
    }

    public UsuarioResponse buscarPorId(Long id) {
        Usuario u = repo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));
        return UsuarioResponse.from(u);
    }

    public UsuarioResponse atualizar(Long id, java.util.Map<String, Object> body) {
        Usuario u = repo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        // SEGURANÇA: campos abaixo são IMUTÁVEIS após o cadastro (anti-fraude).
        // Qualquer envio é silenciosamente ignorado:
        //   - documentoFederal (CNPJ/CNH)
        //   - email, tipo
        //   - cnhNumero, cnhCategoria, cnhValidade (dados legais da CNH)

        if (body.get("nome") instanceof String s && !s.isBlank()) u.setNome(s);
        if (body.get("telefone") instanceof String s) u.setTelefone(s);
        if (body.get("fotoPerfil") instanceof String s) u.setFotoPerfil(s);

        if (body.get("dataNascimento") instanceof String s && !s.isBlank()) {
            u.setDataNascimento(java.time.LocalDate.parse(s));
        }
        if (body.get("cidade") instanceof String s) u.setCidade(s);
        if (body.get("estado") instanceof String s) u.setEstado(s);

        // Veículo: editável (motoboy pode trocar de moto)
        if (body.get("veiculoModelo") instanceof String s) u.setVeiculoModelo(s);
        if (body.get("veiculoPlaca") instanceof String s) u.setVeiculoPlaca(s);
        if (body.get("veiculoAno") instanceof Number n) u.setVeiculoAno(n.intValue());
        if (body.get("veiculoCor") instanceof String s) u.setVeiculoCor(s);

        if (body.get("nomeFantasia") instanceof String s) u.setNomeFantasia(s);
        if (body.get("enderecoComercial") instanceof String s) u.setEnderecoComercial(s);

        return UsuarioResponse.from(repo.save(u));
    }

    private String tokenPara(Usuario u) {
        return jwt.gerar(u.getId(), u.getEmail(), u.getTipo());
    }

    /**
     * Confere a senha aceitando as duas formas que existem no banco.
     *
     * O hash é o caminho normal. O ramo de texto puro existe porque o banco de
     * produção já tem contas gravadas antes do BCrypt: barrar essas pessoas no
     * login seria trocar um problema de segurança por um de acesso. Na primeira
     * entrada correta a senha é regravada com hash e a conta nunca mais passa
     * por aqui — a migração acontece sozinha, uma conta por vez.
     */
    private boolean senhaConfere(Usuario u, String informada) {
        String armazenada = u.getSenha();
        if (armazenada == null || informada == null) return false;

        if (armazenada.startsWith("$2a$") || armazenada.startsWith("$2b$")
                || armazenada.startsWith("$2y$")) {
            return encoder.matches(informada, armazenada);
        }

        // Legado em texto puro: confere e migra.
        if (!armazenada.equals(informada)) return false;

        u.setSenha(encoder.encode(informada));
        repo.save(u);
        return true;
    }
}
