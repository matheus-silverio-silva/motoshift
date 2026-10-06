package com.motoshift.controller;

import com.motoshift.repository.UsuarioRepository;
import com.motoshift.security.JwtService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpHeaders;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A conferência do ledger existe onde o desenvolvedor roda o projeto: SEM
 * perfil nenhum (SCRUM-30).
 *
 * <p>O controller era {@code @Profile("dev")}, e nada ativa um perfil "dev" —
 * o {@code RODAR.bat} e o {@code mvnw spring-boot:run} sobem só com o
 * application.properties. A rota respondia 404 justamente onde devia existir,
 * e nenhum teste via isso: todos sobem com o perfil "test".
 *
 * <p><b>Sem {@code @ActiveProfiles}, de propósito.</b> É o boot de
 * desenvolvimento. As propriedades abaixo não são perfil: só dão a este
 * contexto um banco próprio (o do application.properties tem nome fixo e é
 * compartilhado pela JVM) e calam o log de SQL que o dev liga.
 */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:consistencia-sem-perfil;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
        "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.format_sql=false",
        "spring.h2.console.enabled=false",
        "logging.level.org.springframework.web=WARN",
        "logging.level.org.springframework.web.cors=WARN",
        "logging.level.com.motoshift=WARN",
        // Os jobs não são o assunto: um intervalo enorme os tira do caminho.
        "motoshift.expiracao.intervalo-ms=86400000"
})
@AutoConfigureMockMvc
class ConsistenciaSemPerfilTest {

    @Autowired private MockMvc mvc;
    @Autowired private Environment ambiente;
    @Autowired private JwtService jwt;
    @Autowired private UsuarioRepository usuarioRepo;

    @Test
    @DisplayName("sem perfil ativo, a rota existe: autenticado responde 200 com o ledger da massa fechando")
    void semPerfil_autenticado_200() throws Exception {
        assertThat(ambiente.getActiveProfiles()).as("este teste é o boot sem perfil").isEmpty();

        // Uma conta da massa, que o boot de desenvolvimento acabou de semear.
        var claudia = usuarioRepo.findByEmail("claudia@teste.com").orElseThrow();
        String token = jwt.gerar(claudia.getId(), claudia.getEmail(), claudia.getTipo());

        mvc.perform(get("/api/dev/ledger/consistencia")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.consistente").value(true))
                .andExpect(jsonPath("$.problemas").isEmpty())
                .andExpect(jsonPath("$.totais").isNotEmpty());
    }

    @Test
    @DisplayName("continua fechada para quem não entrou: sem token, 401")
    void semToken_401() throws Exception {
        mvc.perform(get("/api/dev/ledger/consistencia"))
                .andExpect(status().isUnauthorized());
    }
}
