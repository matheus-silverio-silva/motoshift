package com.motoshift.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
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
 * RF01 (5 tentativas, 15 minutos), que mora no banco. O {@code /api/status}
 * também não: é a rota que o monitor chama a cada 10 minutos para manter o
 * servidor acordado, e não escreve nada.
 *
 * <p><b>De onde vem o IP (SCRUM-48).</b> Atrás de um proxy, o
 * {@code getRemoteAddr()} é o endereço do PROXY — o mesmo para todo mundo. Um
 * limite por esse endereço seria um limite global: vinte cadastros a cada dez
 * minutos para o aplicativo inteiro, e uma pessoa só trancaria a porta para
 * todas. O IP de quem chamou vem no cabeçalho que o proxy preenche, e o nome
 * dele é a propriedade {@code motoshift.limite.cabecalho-do-ip}:
 * {@code X-Forwarded-For} em produção, vazio em desenvolvimento.
 *
 * <p>Vazio em dev porque, sem proxy na frente, quem escreve esse cabeçalho é o
 * próprio cliente: confiar nele seria deixar cada requisição escolher a chave
 * do próprio limite.
 *
 * <p><b>Qual entrada do {@code X-Forwarded-For}.</b> Cada proxy acrescenta ao
 * FIM da lista o endereço de quem falou com ele; o que vem antes é o que o
 * cliente quis mandar. Vale, então, a entrada N contando da direita, com
 * {@code N = 1 + proxies confiáveis}
 * ({@code motoshift.limite.proxies-confiaveis}) — quantas entradas do fim da
 * lista são dos proxies da própria hospedagem:
 * <ul>
 *   <li><b>1 no Render</b> (padrão do perfil {@code prod}): o proxy de lá põe
 *       também o próprio IP no fim, então a última entrada é o proxy e a
 *       penúltima é o cliente. Lendo a última, como a Fase 12 fazia para o
 *       Railway, o limite contava todos os usuários juntos.
 *   <li><b>0</b> quando a última entrada já é o cliente (era o caso do
 *       Railway).
 * </ul>
 * Lista mais curta do que o pedido: vale a primeira entrada — o mais longe do
 * proxy que a lista vai —, nunca a do proxy. O número tem de bater com a
 * hospedagem: contado a mais, cai numa entrada que o cliente escreveu, e ele
 * escolhe a chave do próprio limite; contado a menos, junta todo mundo no IP
 * do proxy. Por isso se confere em produção, com o log abaixo.
 *
 * <p>Outro cabeçalho configurado (um {@code True-Client-IP}, um
 * {@code X-Real-IP}) não é lista: vale o valor inteiro.
 *
 * <p><b>Para conferir em produção</b>, ligue o DEBUG deste filtro
 * ({@code LOGGING_LEVEL_COM_MOTOSHIFT_SECURITY_LIMITEDEREQUISICOESFILTER=DEBUG})
 * e faça um cadastro ou um "esqueci minha senha": o log traz o cabeçalho cru e
 * o IP escolhido, que tem de ser o seu.
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

    /**
     * O nome do logger, em minúsculas de propósito. O Spring Boot passa a
     * variável de ambiente {@code LOGGING_LEVEL_...} para minúsculas, e nome de
     * logger diferencia maiúsculas: com o nome da classe
     * ({@code ...LimiteDeRequisicoesFilter}) a variável nunca o alcançaria, e
     * ligar o DEBUG no painel da hospedagem não teria efeito nenhum.
     */
    static final String NOME_DO_LOG = "com.motoshift.security.limitederequisicoesfilter";

    private static final Logger log = LoggerFactory.getLogger(NOME_DO_LOG);

    public static final int SUGESTOES_POR_HORA = 10;
    public static final int PUBLICAS_POR_JANELA = 20;
    public static final Duration JANELA_DAS_PUBLICAS = Duration.ofMinutes(10);

    private static final String PREFIXO_SUGESTOES = "/api/sugestoes";
    private static final Set<String> ROTAS_PUBLICAS_LIMITADAS =
            Set.of("/api/auth/registro", "/api/auth/esqueci-senha");

    /** O único cabeçalho tratado como lista de saltos. */
    private static final String X_FORWARDED_FOR = "X-Forwarded-For";

    private final JanelaDeslizante porUsuario =
            new JanelaDeslizante(SUGESTOES_POR_HORA, Duration.ofHours(1));
    private final JanelaDeslizante porIp =
            new JanelaDeslizante(PUBLICAS_POR_JANELA, JANELA_DAS_PUBLICAS);

    private final RespostaDeErro erros;
    private final boolean habilitado;
    private final String cabecalhoDoIp;
    private final int proxiesConfiaveis;
    private LongSupplier relogio = System::currentTimeMillis;

    public LimiteDeRequisicoesFilter(
            RespostaDeErro erros,
            @Value("${motoshift.limite.habilitado:true}") boolean habilitado,
            @Value("${motoshift.limite.cabecalho-do-ip:}") String cabecalhoDoIp,
            @Value("${motoshift.limite.proxies-confiaveis:0}") int proxiesConfiaveis) {
        this.erros = erros;
        this.habilitado = habilitado;
        this.cabecalhoDoIp = cabecalhoDoIp == null ? "" : cabecalhoDoIp.trim();
        // Negativo não quer dizer nada; vale como "nenhum".
        this.proxiesConfiaveis = Math.max(0, proxiesConfiaveis);
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
     * A reserva quando o cabeçalho configurado não vem: alguns proxies entregam
     * o IP do cliente só neste. Cair direto no endereço da conexão, atrás de um
     * proxy, voltaria ao limite global.
     */
    static final String CABECALHO_RESERVA = "X-Real-IP";

    /**
     * O IP de quem chamou. Com um cabeçalho de proxy configurado: a entrada
     * dele que a regra da classe escolhe; na falta, o
     * {@value #CABECALHO_RESERVA}. Sem cabeçalho configurado (dev), ou sem
     * nenhum dos dois, o endereço da conexão.
     */
    String ipDoCliente(HttpServletRequest req) {
        String ip = null;
        String cru = null;
        if (!cabecalhoDoIp.isEmpty()) {
            cru = req.getHeader(cabecalhoDoIp);
            ip = X_FORWARDED_FOR.equalsIgnoreCase(cabecalhoDoIp)
                    ? entradaDoCliente(cru, proxiesConfiaveis)
                    : inteiro(cru);
            if (ip == null) ip = inteiro(req.getHeader(CABECALHO_RESERVA));
        }
        if (ip == null) ip = req.getRemoteAddr();

        if (log.isDebugEnabled()) {
            log.debug("limite: cabecalho {}=[{}], proxies confiaveis={}, conexao={} -> ip escolhido={}",
                    cabecalhoDoIp.isEmpty() ? "(nenhum)" : cabecalhoDoIp,
                    cru == null ? "" : cru, proxiesConfiaveis, req.getRemoteAddr(), ip);
        }
        return ip;
    }

    /**
     * A entrada do cliente numa lista de saltos: a de número
     * {@code 1 + proxiesConfiaveis} contando da direita.
     *
     * <pre>
     *   "cliente, proxy"          com 1 proxy  → "cliente"
     *   "forjado, cliente, proxy" com 1 proxy  → "cliente"
     *   "forjado, cliente"        com 0        → "cliente"
     *   "cliente"                 com 1 proxy  → "cliente" (lista curta: a primeira)
     * </pre>
     *
     * Entradas vazias ("a, , b") não contam. Nulo quando o cabeçalho não veio
     * ou veio sem nenhuma entrada.
     */
    static String entradaDoCliente(String valor, int proxiesConfiaveis) {
        if (valor == null) return null;
        List<String> entradas = new ArrayList<>();
        for (String parte : valor.split(",")) {
            String ip = parte.trim();
            if (!ip.isEmpty()) entradas.add(ip);
        }
        if (entradas.isEmpty()) return null;
        int indice = entradas.size() - 1 - Math.max(0, proxiesConfiaveis);
        return entradas.get(Math.max(0, indice));
    }

    /** O valor de um cabeçalho que traz um IP só. Nulo quando ausente ou vazio. */
    private static String inteiro(String valor) {
        if (valor == null) return null;
        String ip = valor.trim();
        return ip.isEmpty() ? null : ip;
    }
}
