package com.motoshift.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.util.Set;
import java.util.function.LongSupplier;

/**
 * Limite de requisições nas rotas que custam dinheiro ou convidam abuso (SCRUM-36).
 *
 * <ul>
 *   <li><b>{@code /api/sugestoes/**} — 10 por hora, por usuário.</b> Cada
 *       chamada vira uma chamada à API da Anthropic, que é paga por uso. O
 *       cache do {@code AnthropicService} segura a repetição idêntica; este
 *       limite segura a conta logada que pede em laço.
 *   <li><b>{@code POST /api/auth/registro} e {@code POST /api/auth/esqueci-senha}
 *       — 20 a cada 10 minutos, por IP e por rota.</b> São as duas rotas
 *       públicas que escrevem: uma cria conta, a outra gera código de
 *       recuperação e dispara e-mail. Sem limite, um laço enche o banco de
 *       contas falsas ou a caixa de entrada de alguém. Como não há usuário, a
 *       chave é o IP.
 * </ul>
 *
 * <p>O login não está aqui de propósito: ele já tem o bloqueio por conta do
 * RF01 (5 tentativas, 15 minutos), que mora no banco.
 *
 * <p><b>De onde vem o IP.</b> Atrás do proxy do Railway, o
 * {@code getRemoteAddr()} é o endereço do PROXY — o mesmo para todo mundo. Um
 * limite por esse endereço seria um limite global: vinte cadastros a cada dez
 * minutos para o aplicativo inteiro, e uma pessoa só trancaria a porta para
 * todas. O IP de quem chamou vem no cabeçalho que o proxy preenche, e o nome
 * dele é a propriedade {@code motoshift.limite.cabecalho-do-ip}:
 * {@code X-Forwarded-For} em produção, vazio em desenvolvimento.
 *
 * <p>Vazio em dev porque, sem proxy na frente, quem escreve esse cabeçalho é o
 * próprio cliente: confiar nele seria deixar cada requisição escolher a chave
 * do próprio limite. E, do {@code X-Forwarded-For}, vale a <b>última</b>
 * entrada da lista: cada proxy acrescenta ao fim o endereço de quem falou com
 * ele, então a última foi escrita pelo proxy em que se confia, e as anteriores
 * são o que o cliente quis mandar.
 *
 * <p><b>Onde roda.</b> Dentro da cadeia do Spring Security, logo depois do
 * {@link JwtAuthFilter}: o limite por usuário precisa saber quem é o usuário,
 * e o 429 sai com os cabeçalhos de CORS que o filtro de CORS já pôs.
 *
 * <p>O estado é em memória — ver {@link JanelaDeslizante} para o que isso
 * significa com mais de uma réplica.
 */
@Component
public class LimiteDeRequisicoesFilter extends OncePerRequestFilter {

    public static final int SUGESTOES_POR_HORA = 10;
    public static final int PUBLICAS_POR_JANELA = 20;
    public static final Duration JANELA_DAS_PUBLICAS = Duration.ofMinutes(10);

    private static final String PREFIXO_SUGESTOES = "/api/sugestoes";
    private static final Set<String> ROTAS_PUBLICAS_LIMITADAS =
            Set.of("/api/auth/registro", "/api/auth/esqueci-senha");

    private final JanelaDeslizante porUsuario =
            new JanelaDeslizante(SUGESTOES_POR_HORA, Duration.ofHours(1));
    private final JanelaDeslizante porIp =
            new JanelaDeslizante(PUBLICAS_POR_JANELA, JANELA_DAS_PUBLICAS);

    private final RespostaDeErro erros;
    private final boolean habilitado;
    private final String cabecalhoDoIp;
    private LongSupplier relogio = System::currentTimeMillis;

    public LimiteDeRequisicoesFilter(
            RespostaDeErro erros,
            @Value("${motoshift.limite.habilitado:true}") boolean habilitado,
            @Value("${motoshift.limite.cabecalho-do-ip:}") String cabecalhoDoIp) {
        this.erros = erros;
        this.habilitado = habilitado;
        this.cabecalhoDoIp = cabecalhoDoIp == null ? "" : cabecalhoDoIp.trim();
    }

    /** Só para teste: o relógio que diz "agora" à janela. */
    void usarRelogio(LongSupplier relogio) {
        this.relogio = relogio;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req,
                                    HttpServletResponse resp,
                                    FilterChain chain) throws ServletException, IOException {

        JanelaDeslizante.Decisao decisao = habilitado ? decidir(req) : null;

        if (decisao != null && !decisao.permitido()) {
            long minutos = (decisao.esperarSegundos() + 59) / 60;
            resp.setHeader(HttpHeaders.RETRY_AFTER, String.valueOf(decisao.esperarSegundos()));
            erros.escrever(resp, HttpStatus.TOO_MANY_REQUESTS.value(), "muitas_tentativas",
                    "Muitas requisições. Tente de novo em " + minutos + " minuto(s).");
            return;
        }
        chain.doFilter(req, resp);
    }

    /** Nulo quando a rota não tem limite (ou não há a quem atribuí-lo). */
    private JanelaDeslizante.Decisao decidir(HttpServletRequest req) {
        // O preflight do CORS não é a requisição: contá-lo gastaria o limite
        // do navegador em dobro.
        if ("OPTIONS".equalsIgnoreCase(req.getMethod())) return null;

        String rota = req.getRequestURI().substring(req.getContextPath().length());

        if (rota.equals(PREFIXO_SUGESTOES) || rota.startsWith(PREFIXO_SUGESTOES + "/")) {
            Long usuarioId = usuarioAutenticado();
            // Sem token a requisição vai morrer em 401 logo adiante; não há
            // de quem descontar.
            return usuarioId == null ? null : porUsuario.registrar("u:" + usuarioId, relogio.getAsLong());
        }

        if ("POST".equalsIgnoreCase(req.getMethod()) && ROTAS_PUBLICAS_LIMITADAS.contains(rota)) {
            return porIp.registrar(rota + "|" + ipDoCliente(req), relogio.getAsLong());
        }
        return null;
    }

    private static Long usuarioAutenticado() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return auth != null && auth.getPrincipal() instanceof UsuarioAutenticado u ? u.id() : null;
    }

    /**
     * O outro cabeçalho em que o proxy do Railway entrega o IP do cliente —
     * e o único que a documentação dele cita para isso. Entra como reserva
     * quando o cabeçalho configurado não vem: cair direto no endereço da
     * conexão, atrás do proxy, voltaria ao limite global.
     */
    static final String CABECALHO_RESERVA = "X-Real-IP";

    /**
     * O IP de quem chamou. Com um cabeçalho de proxy configurado: a última
     * entrada dele; na falta, a do {@value #CABECALHO_RESERVA}. Sem cabeçalho
     * configurado (dev), ou sem nenhum dos dois, o endereço da conexão.
     */
    String ipDoCliente(HttpServletRequest req) {
        if (!cabecalhoDoIp.isEmpty()) {
            String ip = ultimaEntrada(req.getHeader(cabecalhoDoIp));
            if (ip == null) ip = ultimaEntrada(req.getHeader(CABECALHO_RESERVA));
            if (ip != null) return ip;
        }
        return req.getRemoteAddr();
    }

    /** "a, b, c" → "c". Nulo quando o cabeçalho não veio ou veio vazio. */
    private static String ultimaEntrada(String valor) {
        if (valor == null) return null;
        String[] partes = valor.split(",");
        for (int i = partes.length - 1; i >= 0; i--) {
            String ip = partes[i].trim();
            if (!ip.isEmpty()) return ip;
        }
        return null;
    }
}
