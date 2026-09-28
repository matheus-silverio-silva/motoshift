package com.motoshift.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
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
 *
 * <p><b>Token válido de conta que não existe mais também para aqui.</b> A
 * assinatura e a validade (7 dias) não dizem se a conta ainda está no banco.
 * O reset da massa de demonstração recria as contas com ids novos, e a sessão
 * aberta antes dele seguia autenticada com o id antigo: a carteira tentava
 * nascer para um usuário inexistente e a {@code fk_carteira_usuario} da V11
 * devolvia 500; as leituras respondiam 200 vazias, como se a conta estivesse
 * zerada. Agora é 401, e o app trata 401 de sessão ativa como "entre de
 * novo" — o novo login devolve o id certo. Custa uma consulta por chave
 * primária por requisição autenticada.
 */
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private static final String PREFIXO = "Bearer ";

    private final JwtService jwt;
    private final RespostaDeErro erros;
    private final UsuarioRepository usuarios;

    public JwtAuthFilter(JwtService jwt, RespostaDeErro erros, UsuarioRepository usuarios) {
        this.jwt = jwt;
        this.erros = erros;
        this.usuarios = usuarios;
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
            if (!usuarios.existsById(usuario.id())) {
                SecurityContextHolder.clearContext();
                erros.escrever(resp, HttpStatus.UNAUTHORIZED.value(), "nao_autenticado",
                        "A conta desta sessão não existe mais. Entre de novo.");
                return;
            }

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
