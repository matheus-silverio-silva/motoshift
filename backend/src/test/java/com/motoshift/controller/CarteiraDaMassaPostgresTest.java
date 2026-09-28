package com.motoshift.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.config.MassaDemonstracao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.security.JwtService;
import com.motoshift.support.PostgresDeTeste;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.Year;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A carteira, os relatórios e o informe fiscal pelo HTTP, sobre a massa de
 * demonstração e num PostgreSQL de verdade.
 *
 * <p><b>Por que a massa, e não um cenário próprio.</b> As outras suítes montam
 * dados sob medida e passavam enquanto o app, sobre a massa, quebrava. Aqui as
 * contas são as do README, com os cinco meses de história que a massa conta.
 *
 * <p><b>Por que PostgreSQL, e não o H2 dos outros testes.</b> Os dois 500 que
 * este teste prende só existem nele: o H2 ignora transação somente leitura (o
 * /resumo gravava uma carteira dentro de uma) e o schema do Hibernate não tem
 * as chaves estrangeiras da V11 (a carteira de uma conta que não existe mais —
 * sessão aberta antes de um reset da massa — passava). No H2 os dois
 * respondiam 200.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class CarteiraDaMassaPostgresTest {

    @DynamicPropertySource
    static void postgres(DynamicPropertyRegistry props) {
        String url = PostgresDeTeste.bancoNovo("carteira_massa");
        props.add("spring.datasource.url", () -> url);
        props.add("spring.datasource.username", () -> "postgres");
        props.add("spring.datasource.password", () -> "");
        props.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        props.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.PostgreSQLDialect");
        props.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        props.add("spring.flyway.enabled", () -> "true");
        props.add("spring.flyway.locations", () -> "classpath:db/migration");
    }

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private MassaDemonstracao massa;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private JwtService jwt;

    /**
     * A massa inteira, pelo mesmo {@code popular()} do boot de dev. O gatilho
     * de dev ({@code DataInitializer}) já a grava quando o contexto sobe; esta
     * chamada garante o cenário mesmo que ele mude.
     */
    @BeforeEach
    void massa() {
        Integer contas = jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE email LIKE '%@teste.com'", Integer.class);
        if (contas == 0) massa.popular();
    }

    @Test
    @DisplayName("entregador da massa: carteira, resumo, extrato, fluxo e informe respondem 200 e batem com o banco")
    void entregador() throws Exception {
        Sessao ricardo = entrar("ricardo@teste.com");
        conferirLeituras(ricardo, "prestador", "pagamento_recebido");
    }

    @Test
    @DisplayName("lojista da massa: carteira, resumo, extrato, fluxo e informe respondem 200 e batem com o banco")
    void lojista() throws Exception {
        Sessao claudia = entrar("claudia@teste.com");
        conferirLeituras(claudia, "tomador", "pagamento_enviado");
    }

    @Test
    @DisplayName("saque do entregador e recarga do lojista (criar e confirmar) passam")
    void saqueERecarga() throws Exception {
        Sessao ricardo = entrar("ricardo@teste.com");
        BigDecimal antes = saldo(ricardo.id());
        mvc.perform(com(ricardo, post("/api/carteira/saques")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"valor\": 20.00}")))
                .andExpect(status().isCreated());
        assertThat(saldo(ricardo.id())).isEqualByComparingTo(antes.subtract(new BigDecimal("20.00")));

        Sessao claudia = entrar("claudia@teste.com");
        BigDecimal antesDaRecarga = saldo(claudia.id());
        MvcResult criada = mvc.perform(com(claudia, post("/api/carteira/recargas")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"valor\": 50.00}")))
                .andExpect(status().isCreated())
                .andReturn();
        long cobranca = corpo(criada).get("id").asLong();
        mvc.perform(com(claudia, post("/api/carteira/recargas/" + cobranca + "/confirmar")))
                .andExpect(status().isOk());
        assertThat(saldo(claudia.id())).isEqualByComparingTo(antesDaRecarga.add(new BigDecimal("50.00")));
    }

    @Test
    @DisplayName("a massa tem lançamentos em mais de um mês — a data do passado chega ao banco")
    void lancamentosEmVariosMeses() {
        Long ricardo = idDe("ricardo@teste.com");
        Integer meses = jdbc.queryForObject(
                "SELECT count(DISTINCT to_char(criado_em, 'YYYY-MM')) FROM transacoes WHERE usuario_id = ?",
                Integer.class, ricardo);
        assertThat(meses).isGreaterThan(1);
    }

    @Test
    @DisplayName("o resumo de quem ainda não tem carteira é zero, e não um INSERT numa transação só de leitura")
    void resumoSemCarteira() throws Exception {
        Usuario semCarteira = new Usuario();
        semCarteira.setNome("Conta antiga, sem carteira");
        semCarteira.setEmail("sem-carteira@exemplo.com");
        semCarteira.setTelefone("41999990000");
        semCarteira.setTipo("motoboy");
        semCarteira.setSenha("x");
        semCarteira = usuarioRepo.save(semCarteira);
        Sessao sessao = new Sessao(semCarteira.getId(),
                jwt.gerar(semCarteira.getId(), semCarteira.getEmail(), "motoboy"));

        JsonNode resumo = corpo(mvc.perform(com(sessao, get("/api/carteira/resumo")))
                .andExpect(status().isOk())
                .andReturn());
        assertThat(resumo.get("disponivel").decimalValue()).isEqualByComparingTo("0");
    }

    @Test
    @DisplayName("depois do reset da massa, a sessão antiga leva 401 em toda rota da carteira — e não 500")
    void sessaoDeContaQueNaoExisteMais() throws Exception {
        Sessao antiga = entrar("ricardo@teste.com");

        // O reset recria as contas da massa com ids novos. O token de antes
        // continua assinado e dentro da validade, mas aponta para um id que
        // não existe mais.
        massa.resetar();
        assertThat(usuarioRepo.findById(antiga.id())).isEmpty();

        for (MockHttpServletRequestBuilder req : new MockHttpServletRequestBuilder[]{
                get("/api/carteira/" + antiga.id()),
                get("/api/carteira/resumo"),
                get("/api/carteira/extrato").param("pagina", "0").param("tamanho", "20"),
                get("/api/carteira/fluxo"),
                get("/api/notas-fiscais/resumo").param("ano", String.valueOf(Year.now().getValue())),
                post("/api/carteira/saques").contentType(MediaType.APPLICATION_JSON).content("{\"valor\": 20.00}"),
                post("/api/carteira/recargas").contentType(MediaType.APPLICATION_JSON).content("{\"valor\": 50.00}")}) {
            mvc.perform(com(antiga, req)).andExpect(status().isUnauthorized());
        }

        // Entrar de novo resolve: o login devolve o id atual.
        Sessao nova = entrar("ricardo@teste.com");
        assertThat(nova.id()).isNotEqualTo(antiga.id());
        mvc.perform(com(nova, get("/api/carteira/" + nova.id()))).andExpect(status().isOk());
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    /** As cinco leituras que o app faz ao abrir carteira, relatórios e notas. */
    private void conferirLeituras(Sessao s, String papel, String tipoDoPagamento) throws Exception {
        BigDecimal saldo = saldo(s.id());

        JsonNode carteira = corpo(mvc.perform(com(s, get("/api/carteira/" + s.id())))
                .andExpect(status().isOk()).andReturn());
        assertThat(carteira.get("saldoDisponivel").decimalValue()).isEqualByComparingTo(saldo);

        JsonNode resumo = corpo(mvc.perform(com(s, get("/api/carteira/resumo")))
                .andExpect(status().isOk()).andReturn());
        assertThat(resumo.get("papel").asText()).isEqualTo(papel);
        assertThat(resumo.get("disponivel").decimalValue()).isEqualByComparingTo(saldo);

        LocalDate hoje = LocalDate.now();
        mvc.perform(com(s, get("/api/carteira/resumo")
                        .param("dataInicio", hoje.minusDays(29).toString())
                        .param("dataFim", hoje.toString())))
                .andExpect(status().isOk());

        JsonNode extrato = corpo(mvc.perform(com(s, get("/api/carteira/extrato")
                        .param("pagina", "0").param("tamanho", "20")))
                .andExpect(status().isOk()).andReturn());
        assertThat(extrato.isArray()).isTrue();
        assertThat(extrato.size()).isPositive();

        mvc.perform(com(s, get("/api/carteira/fluxo"))).andExpect(status().isOk());

        int ano = Year.now().getValue();
        BigDecimal totalDoAno = jdbc.queryForObject(
                "SELECT coalesce(sum(valor), 0) FROM transacoes WHERE usuario_id = ? AND tipo = ? "
                        + "AND status = 'concluido' AND extract(year FROM criado_em) = ?",
                BigDecimal.class, s.id(), tipoDoPagamento, ano);
        JsonNode informe = corpo(mvc.perform(com(s, get("/api/notas-fiscais/resumo")
                        .param("ano", String.valueOf(ano))))
                .andExpect(status().isOk()).andReturn());
        assertThat(informe.get("papel").asText()).isEqualTo(papel);
        assertThat(informe.get("total").decimalValue()).isEqualByComparingTo(totalDoAno);
        assertThat(totalDoAno).isPositive();
    }

    private Sessao entrar(String email) throws Exception {
        JsonNode r = corpo(mvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\",\"senha\":\"senha123\"}"))
                .andExpect(status().isOk())
                .andReturn());
        return new Sessao(r.get("usuario").get("id").asLong(), r.get("token").asText());
    }

    private static MockHttpServletRequestBuilder com(Sessao s, MockHttpServletRequestBuilder req) {
        return req.header(HttpHeaders.AUTHORIZATION, "Bearer " + s.token());
    }

    private JsonNode corpo(MvcResult r) throws Exception {
        return json.readTree(r.getResponse().getContentAsString());
    }

    private BigDecimal saldo(Long usuarioId) {
        return jdbc.queryForObject("SELECT saldo_atual FROM carteiras WHERE usuario_id = ?",
                BigDecimal.class, usuarioId);
    }

    private Long idDe(String email) {
        return jdbc.queryForObject("SELECT id FROM usuarios WHERE email = ?", Long.class, email);
    }

    private record Sessao(Long id, String token) {}
}
