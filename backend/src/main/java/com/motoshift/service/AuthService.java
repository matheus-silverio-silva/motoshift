package com.motoshift.service;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.LoginRequest;
import com.motoshift.dto.RegistroRequest;
import com.motoshift.dto.UsuarioResponse;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class AuthService {

    private static final int MAX_TENTATIVAS = 5;
    private static final int BLOQUEIO_MINUTOS = 15;

    private final UsuarioRepository repo;

    // RF01: rastreamento de tentativas em memória (suficiente para H2 dev)
    private final ConcurrentHashMap<String, AttemptInfo> tentativas = new ConcurrentHashMap<>();

    // Mapa token → userId (sessão em memória — resets com reinício do servidor)
    private final ConcurrentHashMap<String, Long> tokens = new ConcurrentHashMap<>();

    private static class AttemptInfo {
        int contador = 0;
        LocalDateTime bloqueadoAte = null;
    }

    public AuthService(UsuarioRepository repo) {
        this.repo = repo;
    }

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
        u.setSenha(req.getSenha()); // plain-text apenas em dev

        Usuario salvo = repo.save(u);
        String token = UUID.randomUUID().toString();
        tokens.put(token, salvo.getId());
        return new AuthResponse(token, UsuarioResponse.from(salvo));
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
                .map(u -> u.getSenha().equals(req.getSenha()))
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
        String token = UUID.randomUUID().toString();
        tokens.put(token, u.getId());
        return new AuthResponse(token, UsuarioResponse.from(u));
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

    /**
     * Valida o token Bearer e retorna o userId associado.
     * Lança 401 se o token for inválido ou não existir.
     */
    public Long validarToken(String token) {
        Long userId = tokens.get(token);
        if (userId == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Token inválido ou sessão expirada. Faça login novamente.");
        }
        return userId;
    }
}
