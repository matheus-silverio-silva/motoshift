package com.motoshift.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

@Configuration
public class OpenApiConfig {

    /** Nome do esquema, usado so para ligar a definicao ao requisito abaixo. */
    private static final String BEARER = "bearerAuth";

    @Bean
    public OpenAPI motoShiftOpenAPI() {
        return new OpenAPI()
                // Sem isto o Swagger virou vitrine: com a API fechada, toda
                // rota respondia 401 e nao havia onde colar o token.
                .components(new Components().addSecuritySchemes(BEARER,
                        new SecurityScheme()
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")
                                .description("Token devolvido por POST /api/auth/login")))
                .addSecurityItem(new SecurityRequirement().addList(BEARER))
                .info(new Info()
                        .title("MotoShift API")
                        .description("Plataforma de logística urbana agendada — conecta Lojistas e Motoboys.")
                        .version("1.0.0")
                        .contact(new Contact()
                                .name("MotoShift")
                                .email("contato@motoshift.com.br"))
                        .license(new License()
                                .name("MIT")
                                .url("https://opensource.org/licenses/MIT")))
                .servers(List.of(
                        new Server().url("http://localhost:8080").description("Desenvolvimento local")));
    }
}
