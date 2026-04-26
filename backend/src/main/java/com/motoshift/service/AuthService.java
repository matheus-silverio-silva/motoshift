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

import java.util.UUID;

@Service
public class AuthService {

    private final UsuarioRepository repo;

    public AuthService(UsuarioRepository repo) {
        this.repo = repo;
    }

    public AuthResponse registrar(RegistroRequest req) {
        if (repo.existsByEmail(req.getEmail())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "E-mail já cadastrado");
        }

        // RF01/RF03 — Lojista exige CNPJ; Motoboy exige CNH
        String tipoNorm = req.getTipo() == null ? "" : req.getTipo().toLowerCase();
        if ("lojista".equals(tipoNorm)) {
            if (req.getDocumentoFederal() == null || req.getDocumentoFederal().isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNPJ é obrigatório para cadastro como Lojista.");
            }
        } else if ("motoboy".equals(tipoNorm)) {
            if (req.getDocumentoFederal() == null || req.getDocumentoFederal().isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNH é obrigatória para cadastro como Motoboy.");
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
        return new AuthResponse(token, UsuarioResponse.from(salvo));
    }

    public AuthResponse login(LoginRequest req) {
        Usuario u = repo.findByEmail(req.getEmail())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Credenciais inválidas"));

        if (!u.getSenha().equals(req.getSenha())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Credenciais inválidas");
        }

        String token = UUID.randomUUID().toString();
        return new AuthResponse(token, UsuarioResponse.from(u));
    }

    public UsuarioResponse buscarPorId(Long id) {
        Usuario u = repo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));
        return UsuarioResponse.from(u);
    }
}
