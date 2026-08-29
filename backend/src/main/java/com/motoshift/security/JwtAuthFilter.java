package com.motoshift.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.util.List;

/**
 * Lê o Bearer de cada requisição e coloca o usuário no SecurityContext.
 *
 * Não decide quem pode o quê: rota liberada segue sem token (o
 * {@link SecurityConfig} é quem lista as públicas), rota protegida sem
 * autenticação cai no entry point com 401. Token presente e inválido para
 * aqui mesmo, com 401 explícito — deixar passar como anônimo daria 401
 * também, mas sem dizer que o problema era o token vencido.
 */
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private static final String PREFIXO = "Bearer ";

    private final JwtService jwt;
    private final RespostaDeErro erros;

    public JwtAuthFilter(JwtService jwt, RespostaDeErro erros) {
        this.jwt = jwt;
        this.erros = erros;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req,
                                    HttpServletResponse resp,
                                    FilterChain chain) throws ServletException, IOException {

        String header = req.getHeader(HttpHeaders.AUTHORIZATION);

        if (header == null || !header.startsWith(PREFIXO)) {
            chain.doFilter(req, resp);
            return;
        }

        try {
            UsuarioAutenticado usuario = jwt.ler(header.substring(PREFIXO.length()).trim());

            var auth = new UsernamePasswordAuthenticationToken(
                    usuario, null,
                    List.of(new SimpleGrantedAuthority("ROLE_" + usuario.tipo().toUpperCase())));
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(req));
            SecurityContextHolder.getContext().setAuthentication(auth);

        } catch (ResponseStatusException e) {
            SecurityContextHolder.clearContext();
            erros.escrever(resp, e.getStatusCode().value(), "nao_autenticado", e.getReason());
            return;
        }

        chain.doFilter(req, resp);
    }
}
