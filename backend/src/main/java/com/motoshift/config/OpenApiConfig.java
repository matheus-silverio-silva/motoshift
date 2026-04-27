package com.motoshift.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI motoShiftOpenAPI() {
        return new OpenAPI()
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
