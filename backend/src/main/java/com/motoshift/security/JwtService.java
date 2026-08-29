package com.motoshift.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;

/**
 * Emissão e validação do token de sessão (JWT HS256).
 *
 * Substitui o {@code ConcurrentHashMap<String, Long> tokens} que o AuthService
 * mantinha. Aquele mapa tinha três defeitos que este serviço resolve de uma vez:
 *
 *   1. sumia a cada deploy — todo mundo deslogado sem motivo;
 *   2. não expirava — token vazado valia para sempre;
 *   3. não funcionava com mais de uma instância — no Railway, a instância que
 *      não recebeu o login não conhecia o token.
 *
 * O token carrega o id no {@code sub} e o tipo/e-mail como claims, então
 * validar não consulta o banco. O preço é não haver logout no servidor: um
 * token continua válido até expirar. Para um TCC com sessão de 7 dias é o
 * negócio certo; a alternativa (lista de revogação) só se paga com refresh
 * token, que não existe aqui.
 */
@Service
public class JwtService {

    private static final Logger log = LoggerFactory.getLogger(JwtService.class);

    /** Segredo de dev. Em produção JWT_SECRET é obrigatório — ver validação abaixo. */
    static final String SEGREDO_DEV =
            "motoshift-desenvolvimento-chave-local-nao-use-em-producao-256bits";

    private final SecretKey chave;
    private final Duration validade;

    public JwtService(
            @Value("${motoshift.jwt.secret:}") String segredo,
            @Value("${motoshift.jwt.expiracao-horas:168}") long expiracaoHoras) {

        String efetivo = (segredo == null || segredo.isBlank()) ? SEGREDO_DEV : segredo;

        // HS256 exige chave de 256 bits. Um segredo curto na variável de
        // ambiente falharia só na hora de assinar — melhor barrar no boot.
        if (efetivo.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                    "motoshift.jwt.secret precisa de pelo menos 32 caracteres (256 bits para HS256).");
        }
        if (SEGREDO_DEV.equals(efetivo)) {
            log.warn("[jwt] usando o segredo de desenvolvimento. "
                    + "Defina JWT_SECRET no ambiente antes de publicar.");
        }

        this.chave = Keys.hmacShaKeyFor(efetivo.getBytes(StandardCharsets.UTF_8));
        this.validade = Duration.ofHours(expiracaoHoras);
    }

    public String gerar(Long usuarioId, String email, String tipo) {
        Instant agora = Instant.now();
        return Jwts.builder()
                .subject(String.valueOf(usuarioId))
                .claim("email", email)
                .claim("tipo", tipo)
                .issuedAt(Date.from(agora))
                .expiration(Date.from(agora.plus(validade)))
                .signWith(chave)
                .compact();
    }

    /**
     * Lê o token e devolve quem ele identifica.
     * Lança 401 para assinatura inválida, formato quebrado ou prazo vencido —
     * o app trata os três do mesmo jeito: mandar logar de novo.
     */
    public UsuarioAutenticado ler(String token) {
        try {
            Claims c = Jwts.parser()
                    .verifyWith(chave)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();

            return new UsuarioAutenticado(
                    Long.valueOf(c.getSubject()),
                    c.get("email", String.class),
                    c.get("tipo", String.class));

        } catch (JwtException | IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                    "Token inválido ou sessão expirada. Faça login novamente.");
        }
    }
}
