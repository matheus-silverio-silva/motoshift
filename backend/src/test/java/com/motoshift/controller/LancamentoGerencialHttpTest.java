package com.motoshift.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.security.JwtService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code /api/financeiro/**} pelo HTTP: quem pode o quê nos lançamentos
 * gerenciais e na DRE (RF13 / SCRUM-47).
 *
 * <p>A conta da DRE está no {@code DreServiceTest}. Aqui a pergunta é de
 * fronteira: sem token não entra, o lançamento de outra pessoa não existe, a
 * categoria de outro papel é recusada e o turno informado tem de ser um de
 * que o usuário participou.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(CenarioFinanceiro.class)
class LancamentoGerencialHttpTest {

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper json;
    @Autowired private JwtService jwt;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private CenarioFinanceiro cenario;

    private final LocalDate hoje = LocalDate.now();

    private Usuario entregador;
    private Usuario lojista;

    @BeforeEach
    void contas() {
        entregador = cenario.conta("motoboy", "Entregador dos lançamentos", "12345678900");
        lojista = cenario.conta("lojista", "Loja dos lançamentos", "12345678000190");
    }

    // ── Sem token ─────────────────────────────────────────────────────────

    @Test
    @DisplayName("sem token, nenhuma rota de /api/financeiro responde: 401")
    void semToken_401() throws Exception {
        String corpo = json.writeValueAsString(lancamento("combustivel", "10.00"));
        for (MockHttpServletRequestBuilder rota : new MockHttpServletRequestBuilder[] {
                get("/api/financeiro/dre"),
                get("/api/financeiro/dre/mensal"),
                get("/api/financeiro/categorias"),
                get("/api/financeiro/lancamentos"),
                post("/api/financeiro/lancamentos").contentType(MediaType.APPLICATION_JSON).content(corpo),
                put("/api/financeiro/lancamentos/1").contentType(MediaType.APPLICATION_JSON).content(corpo),
                delete("/api/financeiro/lancamentos/1")}) {
            mvc.perform(rota)
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.codigo").value("nao_autenticado"));
        }
    }

    // ── Categorias ────────────────────────────────────────────────────────

    @Test
    @DisplayName("categorias: cada papel recebe só as suas, com rótulo e grupo")
    void categoriasDoPapel() throws Exception {
        mvc.perform(como(entregador, get("/api/financeiro/categorias")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].valor").value(contains(
                        "combustivel", "manutencao", "das_mei", "celular_internet", "seguro",
                        "parcela_ou_aluguel_veiculo", "outra_despesa_entregador")))
                .andExpect(jsonPath("$[0].rotulo").value("Combustível"))
                .andExpect(jsonPath("$[0].grupo").value("custo_variavel"))
                .andExpect(jsonPath("$[0].rotuloDoGrupo").value("Custos variáveis"))
                .andExpect(jsonPath("$[0].soma").value(false))
                .andExpect(jsonPath("$[2].grupo").value("deducao"));

        mvc.perform(como(lojista, get("/api/financeiro/categorias")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].valor").value(contains(
                        "taxa_de_entrega_cobrada", "entrega_fora_do_app", "outra_despesa_entrega")))
                .andExpect(jsonPath("$[0].grupo").value("receita"))
                .andExpect(jsonPath("$[0].soma").value(true));
    }

    // ── CRUD ──────────────────────────────────────────────────────────────

    @Test
    @DisplayName("cria, lista, edita e exclui — e a DRE acompanha cada passo")
    void crud() throws Exception {
        Map<String, Object> novo = lancamento("combustivel", "38.50");
        novo.put("km", "120.5");
        novo.put("descricao", "  Posto da esquina  ");

        JsonNode criado = corpo(mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), novo))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNumber())
                .andExpect(jsonPath("$.categoria").value("combustivel"))
                .andExpect(jsonPath("$.rotuloDaCategoria").value("Combustível"))
                .andExpect(jsonPath("$.grupo").value("custo_variavel"))
                .andExpect(jsonPath("$.soma").value(false))
                .andExpect(jsonPath("$.valor").value(38.50))
                .andExpect(jsonPath("$.km").value(120.5))
                .andExpect(jsonPath("$.descricao").value("Posto da esquina"))
                .andExpect(jsonPath("$.recorrente").value(false)));
        long id = criado.get("id").asLong();

        mvc.perform(como(entregador, get("/api/financeiro/lancamentos")
                        .param("dataInicio", hoje.toString()).param("dataFim", hoje.toString())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id").value(id))
                .andExpect(jsonPath("$[0].ocorrenciasNoPeriodo").value(1))
                .andExpect(jsonPath("$[0].valorNoPeriodo").value(38.50));
        dreDeHoje(entregador).andExpect(jsonPath("$.resultado").value(-38.50))
                .andExpect(jsonPath("$.situacao").value("prejuizo"))
                .andExpect(jsonPath("$.papel").value("motoboy"))
                .andExpect(jsonPath("$.lancamentosManuais").value(1));

        Map<String, Object> editado = lancamento("manutencao", "90.00");
        mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + id), editado))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(id))
                .andExpect(jsonPath("$.categoria").value("manutencao"))
                .andExpect(jsonPath("$.valor").value(90.00))
                // O PUT substitui: o km e a descricao de antes sairam.
                .andExpect(jsonPath("$.km").doesNotExist())
                .andExpect(jsonPath("$.descricao").doesNotExist());
        dreDeHoje(entregador).andExpect(jsonPath("$.resultado").value(-90.00));

        mvc.perform(como(entregador, delete("/api/financeiro/lancamentos/" + id)))
                .andExpect(status().isNoContent());
        mvc.perform(como(entregador, delete("/api/financeiro/lancamentos/" + id)))
                .andExpect(status().isNotFound());
        dreDeHoje(entregador).andExpect(jsonPath("$.resultado").value(0.00))
                .andExpect(jsonPath("$.situacao").value("equilibrio"));
    }

    @Test
    @DisplayName("lista: recorrente aparece com as ocorrências do período, e a página leva o total no cabeçalho")
    void listaComRecorrenciaEPagina() throws Exception {
        Map<String, Object> parcela = lancamento("parcela_ou_aluguel_veiculo", "200.00");
        parcela.put("data", hoje.minusDays(70).toString());
        parcela.put("recorrente", true);
        criar(entregador, parcela);
        for (int i = 0; i < 3; i++) {
            Map<String, Object> avulso = lancamento("combustivel", "10.00");
            avulso.put("data", hoje.minusDays(i).toString());
            criar(entregador, avulso);
        }

        // 70 dias: três vencimentos da parcela.
        mvc.perform(como(entregador, get("/api/financeiro/lancamentos")
                        .param("dataInicio", hoje.minusDays(70).toString())
                        .param("dataFim", hoje.toString())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(4)))
                .andExpect(jsonPath("$[3].categoria").value("parcela_ou_aluguel_veiculo"))
                .andExpect(jsonPath("$[3].ocorrenciasNoPeriodo").value(3))
                .andExpect(jsonPath("$[3].valorNoPeriodo").value(600.00));

        mvc.perform(como(entregador, get("/api/financeiro/lancamentos")
                        .param("dataInicio", hoje.minusDays(70).toString())
                        .param("dataFim", hoje.toString())
                        .param("pagina", "0").param("tamanho", "2")))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Total-Count", "4"))
                .andExpect(jsonPath("$", hasSize(2)));
    }

    // ── De quem é ─────────────────────────────────────────────────────────

    @Test
    @DisplayName("lançamento de outro usuário é 404 para ler, editar e excluir — e continua intacto")
    void deOutroUsuario_404() throws Exception {
        Usuario vizinho = cenario.conta("motoboy", "Vizinho", "98765432100");
        long doVizinho = criar(vizinho, lancamento("seguro", "70.00"));

        mvc.perform(como(entregador, get("/api/financeiro/lancamentos")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
        mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + doVizinho),
                        lancamento("seguro", "1.00")))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.codigo").value("nao_encontrado"))
                .andExpect(jsonPath("$.mensagem").value("Lançamento não encontrado."));
        mvc.perform(como(entregador, delete("/api/financeiro/lancamentos/" + doVizinho)))
                .andExpect(status().isNotFound());
        // O mesmo 404 de um id que nao existe: nao da para saber que e de alguem.
        mvc.perform(como(entregador, delete("/api/financeiro/lancamentos/999999999")))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.mensagem").value("Lançamento não encontrado."));

        assertThat(jdbc.queryForObject(
                "SELECT valor FROM lancamentos_gerenciais WHERE id = ?", String.class, doVizinho))
                .startsWith("70.00");
        // E a DRE de um nao enxerga o do outro.
        dreDeHoje(entregador).andExpect(jsonPath("$.lancamentosManuais").value(0));
    }

    // ── Validação ─────────────────────────────────────────────────────────

    @Test
    @DisplayName("categoria do outro papel é recusada com 400, nos dois sentidos")
    void categoriaDoPapelErrado_400() throws Exception {
        mvc.perform(como(lojista, post("/api/financeiro/lancamentos"), lancamento("combustivel", "50.00")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("requisicao_invalida"))
                .andExpect(jsonPath("$.mensagem").value(
                        "A categoria \"Combustível\" não vale para o perfil lojista."));
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"),
                        lancamento("taxa_de_entrega_cobrada", "50.00")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("requisicao_invalida"));
        // Nem pelo editar: um lancamento valido nao vira o de outro papel.
        long id = criar(entregador, lancamento("combustivel", "50.00"));
        mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + id),
                        lancamento("entrega_fora_do_app", "50.00")))
                .andExpect(status().isBadRequest());

        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), lancamento("pedagio", "5.00")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.mensagem").value("Categoria desconhecida."));
    }

    @Test
    @DisplayName("valor, data, km e recorrência malformados são 400, com o campo quando é do formulário")
    void dadosInvalidos_400() throws Exception {
        Map<String, Object> semValor = lancamento("combustivel", "0");
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), semValor))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.campo").value("valor"))
                .andExpect(jsonPath("$.mensagem").value("O valor deve ser maior que zero"));

        Map<String, Object> semData = lancamento("combustivel", "10.00");
        semData.remove("data");
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), semData))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.campo").value("data"));

        Map<String, Object> kmZero = lancamento("combustivel", "10.00");
        kmZero.put("km", "0");
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), kmZero))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.campo").value("km"));

        // "Ate quando" sem ser recorrente, e recorrencia que termina antes de comecar.
        Map<String, Object> ateSemRecorrencia = lancamento("seguro", "70.00");
        ateSemRecorrencia.put("recorrenteAte", hoje.plusMonths(3).toString());
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), ateSemRecorrencia))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("requisicao_invalida"));

        Map<String, Object> terminaAntes = lancamento("seguro", "70.00");
        terminaAntes.put("recorrente", true);
        terminaAntes.put("recorrenteAte", hoje.minusDays(1).toString());
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), terminaAntes))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.mensagem").value("A recorrência não pode terminar antes de começar."));

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM lancamentos_gerenciais WHERE usuario_id = ?",
                Integer.class, entregador.getId())).isZero();
    }

    @Test
    @DisplayName("data de pagamento depois de hoje: 400 com a mensagem do regime de caixa, no POST e no PUT; o \"até quando\" pode ser futuro")
    void dataFutura_400() throws Exception {
        String mensagem = "No regime de caixa, o lançamento entra no dia em que foi pago. "
                + "Informe uma data até hoje.";
        Map<String, Object> amanha = lancamento("seguro", "70.00");
        amanha.put("data", hoje.plusDays(1).toString());

        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), amanha))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("requisicao_invalida"))
                .andExpect(jsonPath("$.mensagem").value(mensagem));

        long id = criar(entregador, lancamento("seguro", "70.00"));
        mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + id), amanha))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.mensagem").value(mensagem));
        // Só o de hoje existe, com a data de hoje.
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM lancamentos_gerenciais WHERE usuario_id = ? AND data > ?",
                Integer.class, entregador.getId(), java.sql.Date.valueOf(hoje))).isZero();

        Map<String, Object> comFim = lancamento("celular_internet", "35.00");
        comFim.put("recorrente", true);
        comFim.put("recorrenteAte", hoje.plusYears(1).toString());
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), comFim))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.recorrenteAte").value(hoje.plusYears(1).toString()));
    }

    @Test
    @DisplayName("PUT com aplicarAPartirDe num recorrente: responde o lançamento novo, encerra o antigo na véspera e a DRE que atravessa a troca soma os dois valores")
    void editarRecorrenteAPartirDeUmaData() throws Exception {
        LocalDate primeira = hoje.minusMonths(3);
        LocalDate esteMes = hoje.withDayOfMonth(1);
        Map<String, Object> seguro = lancamento("seguro", "70.00");
        seguro.put("data", primeira.toString());
        seguro.put("recorrente", true);
        long antigo = criar(entregador, seguro);

        Map<String, Object> reajuste = new LinkedHashMap<>(seguro);
        reajuste.put("valor", "100.00");
        reajuste.put("aplicarAPartirDe", esteMes.toString());
        JsonNode novo = corpo(mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + antigo), reajuste))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.valor").value(100.00))
                .andExpect(jsonPath("$.recorrente").value(true))
                .andExpect(jsonPath("$.recorrenteAte").doesNotExist()));
        long novoId = novo.get("id").asLong();
        assertThat(novoId).isNotEqualTo(antigo);
        assertThat(LocalDate.parse(novo.get("data").asText())).isBetween(esteMes, hoje);

        assertThat(jdbc.queryForObject(
                "SELECT recorrente_ate FROM lancamentos_gerenciais WHERE id = ?",
                java.sql.Date.class, antigo).toLocalDate()).isEqualTo(esteMes.minusDays(1));
        assertThat(jdbc.queryForObject(
                "SELECT valor FROM lancamentos_gerenciais WHERE id = ?", String.class, antigo))
                .startsWith("70.00");

        // O período inteiro: o novo, uma vez; o antigo, nos três meses de antes.
        mvc.perform(como(entregador, get("/api/financeiro/lancamentos")
                        .param("dataInicio", primeira.toString()).param("dataFim", hoje.toString())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].id").value(novoId))
                .andExpect(jsonPath("$[0].ocorrenciasNoPeriodo").value(1))
                .andExpect(jsonPath("$[0].valorNoPeriodo").value(100.00))
                .andExpect(jsonPath("$[1].id").value(antigo))
                .andExpect(jsonPath("$[1].ocorrenciasNoPeriodo").value(3))
                .andExpect(jsonPath("$[1].valorNoPeriodo").value(210.00));

        dre(entregador, primeira, hoje).andExpect(jsonPath("$.resultado").value(-310.00));
        dre(entregador, primeira, esteMes.minusDays(1)).andExpect(jsonPath("$.resultado").value(-210.00));
        dre(entregador, esteMes, hoje).andExpect(jsonPath("$.resultado").value(-100.00));
    }

    @Test
    @DisplayName("aplicarAPartirDe fora do lugar: 400 num lançamento que não se repete e com data futura; no POST é ignorado")
    void aplicarAPartirDe_foraDoLugar() throws Exception {
        long avulso = criar(entregador, lancamento("combustivel", "30.00"));
        Map<String, Object> noAvulso = lancamento("combustivel", "40.00");
        noAvulso.put("aplicarAPartirDe", hoje.toString());
        mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + avulso), noAvulso))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("requisicao_invalida"));

        Map<String, Object> seguro = lancamento("seguro", "70.00");
        seguro.put("data", hoje.minusMonths(3).toString());
        seguro.put("recorrente", true);
        // No POST o campo não quer dizer nada: cria um lançamento só.
        seguro.put("aplicarAPartirDe", hoje.toString());
        long id = criar(entregador, seguro);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM lancamentos_gerenciais WHERE usuario_id = ? AND recorrente = true",
                Integer.class, entregador.getId())).isEqualTo(1);

        seguro.put("aplicarAPartirDe", hoje.plusDays(1).toString());
        mvc.perform(como(entregador, put("/api/financeiro/lancamentos/" + id), seguro))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.mensagem").value("Informe uma data até hoje para aplicar a mudança."));
    }

    @Test
    @DisplayName("turnoId: vale o turno em que o entregador fez check-in e o que o lojista publicou; o alheio é 400")
    void turnoInformado() throws Exception {
        Turno meu = cenario.turnoPago(lojista.getId(), "120.00", entregador.getId());

        Usuario outraLoja = cenario.conta("lojista", "Outra loja", "98765432000110");
        Usuario outroEntregador = cenario.conta("motoboy", "Outro entregador", "55566677788");
        Turno alheio = cenario.turnoPago(outraLoja.getId(), "100.00", outroEntregador.getId());

        Map<String, Object> gasolina = lancamento("combustivel", "12.00");
        gasolina.put("turnoId", meu.getId());
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), gasolina))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.turnoId").value(meu.getId()));

        Map<String, Object> taxa = lancamento("taxa_de_entrega_cobrada", "208.00");
        taxa.put("turnoId", meu.getId());
        mvc.perform(como(lojista, post("/api/financeiro/lancamentos"), taxa))
                .andExpect(status().isCreated());

        // Turno de que nao participou, e turno que nao existe: a mesma resposta.
        for (long turnoId : new long[] {alheio.getId(), 999_999_999L}) {
            gasolina.put("turnoId", turnoId);
            mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), gasolina))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.mensagem").value("Informe um turno de que você participou."));
            taxa.put("turnoId", turnoId);
            mvc.perform(como(lojista, post("/api/financeiro/lancamentos"), taxa))
                    .andExpect(status().isBadRequest());
        }

        // Inscrito sem check-in tambem nao participou: aceitou e nao foi.
        cenario.recarregar(outraLoja.getId(), "100.00");
        Turno semCheckin = cenario.publicar(outraLoja.getId(), "100.00", 1);
        cenario.inscrever(semCheckin, entregador.getId());
        gasolina.put("turnoId", semCheckin.getId());
        mvc.perform(como(entregador, post("/api/financeiro/lancamentos"), gasolina))
                .andExpect(status().isBadRequest());
    }

    // ── DRE pelo HTTP ─────────────────────────────────────────────────────

    @Test
    @DisplayName("a DRE sai do papel do token: o lojista recebe a da operação de entrega, com os doze meses")
    void dreDoLojista() throws Exception {
        criar(lojista, lancamento("taxa_de_entrega_cobrada", "500.00"));
        criar(lojista, lancamento("outra_despesa_entrega", "120.00"));

        dreDeHoje(lojista)
                .andExpect(jsonPath("$.papel").value("lojista"))
                .andExpect(jsonPath("$.linhas[0].chave").value("receita_de_entregas"))
                .andExpect(jsonPath("$.linhas[0].origem").value("manual"))
                .andExpect(jsonPath("$.linhas[-1:].chave").value(contains("resultado")))
                .andExpect(jsonPath("$.linhas[-1:].tipo").value(contains("resultado")))
                .andExpect(jsonPath("$.resultado").value(380.00))
                .andExpect(jsonPath("$.situacao").value("lucro"))
                .andExpect(jsonPath("$.anterior.situacao").value("equilibrio"))
                .andExpect(jsonPath("$.variacaoResultado").value(380.00))
                .andExpect(jsonPath("$.indicadores.custoSobreReceita").value(0.00));

        mvc.perform(como(lojista, get("/api/financeiro/dre/mensal")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(12)))
                .andExpect(jsonPath("$[" + (hoje.getMonthValue() - 1) + "].receita").value(500.00))
                .andExpect(jsonPath("$[" + (hoje.getMonthValue() - 1) + "].custos").value(120.00))
                .andExpect(jsonPath("$[" + (hoje.getMonthValue() - 1) + "].resultado").value(380.00));

        mvc.perform(como(lojista, get("/api/financeiro/dre")
                        .param("dataInicio", hoje.toString())
                        .param("dataFim", hoje.minusDays(1).toString())))
                .andExpect(status().isBadRequest());
        mvc.perform(como(lojista, get("/api/financeiro/dre/mensal").param("ano", "1800")))
                .andExpect(status().isBadRequest());
    }

    // ── Apoio ─────────────────────────────────────────────────────────────

    private Map<String, Object> lancamento(String categoria, String valor) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("categoria", categoria);
        m.put("valor", valor);
        m.put("data", hoje.toString());
        return m;
    }

    private MockHttpServletRequestBuilder como(Usuario u, MockHttpServletRequestBuilder rota) {
        return rota.header(HttpHeaders.AUTHORIZATION,
                "Bearer " + jwt.gerar(u.getId(), u.getEmail(), u.getTipo()));
    }

    private MockHttpServletRequestBuilder como(Usuario u, MockHttpServletRequestBuilder rota,
                                               Map<String, Object> corpo) throws Exception {
        return como(u, rota).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(corpo));
    }

    private long criar(Usuario u, Map<String, Object> corpo) throws Exception {
        return corpo(mvc.perform(como(u, post("/api/financeiro/lancamentos"), corpo))
                .andExpect(status().isCreated())).get("id").asLong();
    }

    private ResultActions dreDeHoje(Usuario u) throws Exception {
        return dre(u, hoje, hoje);
    }

    private ResultActions dre(Usuario u, LocalDate de, LocalDate ate) throws Exception {
        return mvc.perform(como(u, get("/api/financeiro/dre")
                        .param("dataInicio", de.toString()).param("dataFim", ate.toString())))
                .andExpect(status().isOk());
    }

    private JsonNode corpo(ResultActions resposta) throws Exception {
        return json.readTree(resposta.andReturn().getResponse().getContentAsString());
    }
}
