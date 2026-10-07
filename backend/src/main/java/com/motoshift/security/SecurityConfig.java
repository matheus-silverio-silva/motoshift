package com.motoshift.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.HeadersConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * A regra da API em um arquivo só: tudo é privado, menos o que está listado aqui.
 *
 * Antes disto, as 45 rotas eram públicas e dois controllers (Relatorio e Score)
 * repetiam a validação do Bearer na mão. Um {@code curl} lia a carteira alheia
 * e finalizava turno dos outros — o AuthGuard do Flutter protege a navegação
 * do app, não a API.
 *
 * A ordem importa: {@link JwtAuthFilter} roda antes do filtro de usuário/senha
 * para que o SecurityContext já esteja preenchido quando a autorização decidir.
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    /**
     * Rotas abertas: cadastro, login e recuperação de senha, o status, o health
     * e o console H2 do dev. A documentação (Swagger) entra à parte — ver
     * {@link #rotasPublicas()}.
     *
     * <p>As de {@code /api/auth} são listadas uma a uma, e não mais como
     * {@code /api/auth/**}: {@code /api/auth/trocar-senha} mora no mesmo
     * prefixo e exige token. Com o curinga ela nasceria pública — e a próxima
     * rota criada ali também, sem ninguém decidir isso.
     *
     * <p>{@code /api/status} é o "o servidor acordou?" que o app chama antes
     * de haver sessão, e que o monitor chama para o servidor não dormir
     * (SCRUM-48). Só essa rota, sem curinga.
     */
    private static final String[] PUBLICAS = {
            "/api/auth/registro",
            "/api/auth/login",
            "/api/auth/esqueci-senha",
            "/api/auth/redefinir-senha",
            "/api/status",
            "/actuator/health",
            "/actuator/health/**",
            "/h2-console/**",
            "/error"
    };

    private final JwtAuthFilter jwtFilter;
    private final LimiteDeRequisicoesFilter limiteFilter;
    private final RespostaDeErro erros;

    /**
     * Origens permitidas no CORS. Em dev o curinga é conveniente; em produção
     * MOTOSHIFT_CORS_ORIGINS é obrigatória (ver application-prod.properties).
     * Sem default aqui também: um "*" escondido na anotação desfaria a trava
     * do arquivo de propriedades.
     */
    @Value("${motoshift.cors.origins}")
    private String origens;

    /**
     * A documentação da API está ligada? As mesmas duas propriedades do
     * springdoc, com o mesmo padrão dele (ligado). Em produção as duas vêm
     * {@code false} do application-prod.properties.
     */
    @Value("${springdoc.api-docs.enabled:true}")
    private boolean apiDocsLigado;

    @Value("${springdoc.swagger-ui.enabled:true}")
    private boolean swaggerUiLigado;

    public SecurityConfig(JwtAuthFilter jwtFilter,
                          LimiteDeRequisicoesFilter limiteFilter,
                          RespostaDeErro erros) {
        this.jwtFilter = jwtFilter;
        this.limiteFilter = limiteFilter;
        this.erros = erros;
    }

    /**
     * As rotas abertas desta instância.
     *
     * <p>As do Swagger só são públicas enquanto o Swagger existe. Desligado
     * (produção), elas saem daqui e caem na regra geral: sem token, 401 —
     * como qualquer rota que não é de ninguém. Deixá-las liberadas seria
     * manter uma exceção de segurança para algo que não está mais lá, à
     * espera de alguém religar a propriedade sem lembrar que a porta já
     * estava aberta.
     */
    String[] rotasPublicas() {
        List<String> rotas = new ArrayList<>(Arrays.asList(PUBLICAS));
        if (apiDocsLigado) {
            rotas.add("/v3/api-docs/**");
        }
        // A interface só serve para ler o /v3/api-docs: sem ele, não há o
        // que mostrar.
        if (apiDocsLigado && swaggerUiLigado) {
            rotas.add("/swagger-ui/**");
            rotas.add("/swagger-ui.html");
        }
        return rotas.toArray(String[]::new);
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // API sem cookie de sessão: não há CSRF a proteger, e o token vai
            // no header a cada requisição.
            .csrf(csrf -> csrf.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            // O console H2 desenha dentro de <frame>; DENY (padrão) o deixa em branco.
            .headers(h -> h.frameOptions(HeadersConfigurer.FrameOptionsConfig::sameOrigin))
            .authorizeHttpRequests(auth -> auth
                    // O preflight não carrega o Authorization — barrá-lo quebra o app web.
                    .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                    .requestMatchers(rotasPublicas()).permitAll()
                    .anyRequest().authenticated())
            .exceptionHandling(e -> e
                    .authenticationEntryPoint((req, resp, ex) -> erros.escrever(resp, 401,
                            "nao_autenticado",
                            "Autenticação necessária. Faça login para continuar."))
                    .accessDeniedHandler((req, resp, ex) -> erros.escrever(resp, 403,
                            "acesso_negado", "Acesso negado.")))
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            // Depois do JWT: o limite por usuário precisa saber quem é o usuário.
            .addFilterAfter(limiteFilter, JwtAuthFilter.class);

        return http.build();
    }

    /**
     * CORS centralizado. Antes existia aqui e, de novo, em um
     * {@code @CrossOrigin(origins = "*")} repetido em todos os controllers —
     * duas configurações que divergiam sem ninguém perceber.
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        List<String> lista = Arrays.stream(origens.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();

        CorsConfiguration cfg = new CorsConfiguration();
        cfg.setAllowedOriginPatterns(lista);
        cfg.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        cfg.setAllowedHeaders(List.of("*"));
        // O navegador esconde do JavaScript qualquer header de resposta que não
        // esteja aqui — sem isto o app web não leria o total das listagens
        // paginadas, nem o Retry-After do 429 (limite de requisições).
        cfg.setExposedHeaders(List.of("X-Total-Count", "Retry-After"));
        cfg.setAllowCredentials(false);
        cfg.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", cfg);
        return source;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * Vazio de propósito: não há usuário local nenhum, a identidade vem do JWT.
     * Sem este bean o Spring Boot cria um usuário "user" com senha aleatória e
     * a imprime no log a cada boot.
     */
    @Bean
    public UserDetailsService userDetailsService() {
        return new InMemoryUserDetailsManager();
    }
}
