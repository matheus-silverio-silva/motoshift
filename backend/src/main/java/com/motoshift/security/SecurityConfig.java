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

    /** Rotas abertas: login/cadastro, documentação, health e o console H2 do dev. */
    private static final String[] PUBLICAS = {
            "/api/auth/**",
            "/actuator/health",
            "/actuator/health/**",
            "/v3/api-docs/**",
            "/swagger-ui/**",
            "/swagger-ui.html",
            "/h2-console/**",
            "/error"
    };

    private final JwtAuthFilter jwtFilter;
    private final RespostaDeErro erros;

    /**
     * Origens permitidas no CORS. Em dev o curinga é conveniente; em produção
     * defina MOTOSHIFT_CORS_ORIGINS com a URL do front no Railway.
     */
    @Value("${motoshift.cors.origins:*}")
    private String origens;

    public SecurityConfig(JwtAuthFilter jwtFilter, RespostaDeErro erros) {
        this.jwtFilter = jwtFilter;
        this.erros = erros;
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
                    .requestMatchers(PUBLICAS).permitAll()
                    .anyRequest().authenticated())
            .exceptionHandling(e -> e
                    .authenticationEntryPoint((req, resp, ex) -> erros.escrever(resp, 401,
                            "nao_autenticado",
                            "Autenticação necessária. Faça login para continuar."))
                    .accessDeniedHandler((req, resp, ex) -> erros.escrever(resp, 403,
                            "acesso_negado", "Acesso negado.")))
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);

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
