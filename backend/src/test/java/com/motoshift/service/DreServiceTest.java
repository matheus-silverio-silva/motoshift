package com.motoshift.service;

import com.motoshift.dto.DreResponse;
import com.motoshift.dto.DreResponse.Linha;
import com.motoshift.dto.LancamentoGerencialRequest;
import com.motoshift.dto.LancamentoGerencialResponse;
import com.motoshift.entity.CategoriaLancamento;
import com.motoshift.entity.LancamentoGerencial;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.LancamentoGerencialRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.Year;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * A DRE dos dois papéis: o que entra, o que não entra e a última linha
 * (RF13 / SCRUM-47).
 *
 * <p>Os lançamentos do extrato são gravados direto, com a data que o teste
 * escolhe: o que se confere aqui é a CONTA da DRE, e não o caminho do
 * dinheiro, que tem os testes dele. Os custos informados passam pelo
 * {@link LancamentoGerencialService}, como no app.
 *
 * <p>O período de todos os testes é uma janela de dez dias no passado
 * ({@link #inicio} a {@link #fim}), e não "o mês corrente": no dia 1º o mês
 * corrente tem um dia só, e um teste de conta não pode depender do calendário.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class DreServiceTest {

    @Autowired private DreService dre;
    @Autowired private LancamentoGerencialService gerenciais;
    @Autowired private LancamentoGerencialRepository gerencialRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    /** O período dos testes: dez dias, todos no passado. */
    private final LocalDate inicio = LocalDate.now().minusDays(20);
    private final LocalDate fim = LocalDate.now().minusDays(11);
    /** Um dia no meio do período, e um no período anterior de mesmo tamanho. */
    private final LocalDate noPeriodo = LocalDate.now().minusDays(15);
    private final LocalDate noAnterior = LocalDate.now().minusDays(25);

    private Usuario entregador;
    private Usuario lojista;

    @BeforeEach
    void contas() {
        entregador = conta("motoboy", "Entregador da DRE");
        lojista = conta("lojista", "Loja da DRE");
    }

    // ── Entregador ────────────────────────────────────────────────────────

    @Test
    @DisplayName("entregador com lucro: cada linha no lugar, e os indicadores saem dela")
    void entregador_lucro() {
        Turno a = turno(noPeriodo, 4);
        Turno b = turno(noPeriodo.plusDays(1), 4);
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "120.00", noPeriodo, a);
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "120.00", noPeriodo.plusDays(1), b);
        extrato(entregador, TipoTransacao.BONUS, "10.00", noPeriodo, a);
        extrato(entregador, TipoTransacao.RETENCAO_ISS, "6.00", noPeriodo, a);
        extrato(entregador, TipoTransacao.RETENCAO_IRRF, "1.80", noPeriodo, a);
        informar(entregador, "das_mei", "80.00", noPeriodo, null);
        informar(entregador, "combustivel", "30.00", noPeriodo, "100.0");
        informar(entregador, "manutencao", "20.00", noPeriodo, null);
        informar(entregador, "celular_internet", "40.00", noPeriodo, null);

        DreResponse r = dre.dre(entregador.getId(), "motoboy", inicio, fim);

        assertThat(r.papel()).isEqualTo("motoboy");
        assertThat(r.dataInicio()).isEqualTo(inicio);
        assertThat(r.dataFim()).isEqualTo(fim);

        assertThat(r.linhas()).extracting(Linha::chave).containsExactly(
                "pagamentos_recebidos", "gorjetas_recebidas", "receita_bruta",
                "retencoes_na_fonte", "das_mei", "receita_liquida",
                "combustivel", "manutencao", "margem_de_contribuicao",
                "celular_internet", "seguro", "parcela_ou_aluguel_veiculo",
                "outra_despesa_entregador", "resultado");

        assertThat(valor(r, "pagamentos_recebidos")).isEqualByComparingTo("240.00");
        assertThat(valor(r, "gorjetas_recebidas")).isEqualByComparingTo("10.00");
        assertThat(valor(r, "receita_bruta")).isEqualByComparingTo("250.00");
        assertThat(valor(r, "retencoes_na_fonte")).isEqualByComparingTo("7.80");
        assertThat(valor(r, "das_mei")).isEqualByComparingTo("80.00");
        assertThat(valor(r, "receita_liquida")).isEqualByComparingTo("162.20");
        assertThat(valor(r, "combustivel")).isEqualByComparingTo("30.00");
        assertThat(valor(r, "manutencao")).isEqualByComparingTo("20.00");
        assertThat(valor(r, "margem_de_contribuicao")).isEqualByComparingTo("112.20");
        assertThat(valor(r, "celular_internet")).isEqualByComparingTo("40.00");
        assertThat(valor(r, "seguro")).isEqualByComparingTo("0.00");
        assertThat(valor(r, "resultado")).isEqualByComparingTo("72.20");

        assertThat(r.resultado()).isEqualByComparingTo("72.20");
        assertThat(r.situacao()).isEqualTo("lucro");
        assertThat(r.lancamentosManuais()).isEqualTo(4);

        // De onde veio cada linha, e quais se subtraem.
        assertThat(linha(r, "pagamentos_recebidos").origem()).isEqualTo("extrato");
        assertThat(linha(r, "combustivel").origem()).isEqualTo("manual");
        assertThat(linha(r, "receita_bruta").origem()).isEqualTo("calculado");
        assertThat(linha(r, "receita_bruta").tipo()).isEqualTo("subtotal");
        assertThat(linha(r, "resultado").tipo()).isEqualTo("resultado");
        assertThat(linha(r, "combustivel").subtrai()).isTrue();
        assertThat(linha(r, "retencoes_na_fonte").subtrai()).isTrue();
        assertThat(linha(r, "gorjetas_recebidas").subtrai()).isFalse();
        assertThat(linha(r, "receita_liquida").subtrai()).isFalse();

        Map<String, Object> ind = r.indicadores();
        assertThat((BigDecimal) ind.get("margemLiquida")).isEqualByComparingTo("28.88");
        assertThat(ind.get("turnosPagos")).isEqualTo(2);
        assertThat(ind.get("horasTrabalhadas")).isEqualTo(8.0);
        assertThat((BigDecimal) ind.get("lucroPorHora")).isEqualByComparingTo("9.03");
        assertThat((BigDecimal) ind.get("lucroPorTurno")).isEqualByComparingTo("36.10");
        assertThat((BigDecimal) ind.get("kmInformados")).isEqualByComparingTo("100.0");
        // Custos variáveis (30 + 20) sobre os 100 km informados.
        assertThat((BigDecimal) ind.get("custoPorKm")).isEqualByComparingTo("0.50");
        // Despesas fixas 40 ÷ margem por turno 56,10 = 0,71 → 1 turno.
        assertThat((BigDecimal) ind.get("margemDeContribuicaoPorTurno")).isEqualByComparingTo("56.10");
        assertThat(ind.get("pontoDeEquilibrioTurnos")).isEqualTo(1);
        assertThat(ind.get("pontoDeEquilibrioMotivo")).isNull();
    }

    @Test
    @DisplayName("entregador com prejuízo: a manutenção custou mais do que o período rendeu")
    void entregador_prejuizo() {
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "120.00", noPeriodo, turno(noPeriodo, 4));
        informar(entregador, "manutencao", "300.00", noPeriodo, null);

        DreResponse r = dre.dre(entregador.getId(), "motoboy", inicio, fim);

        assertThat(r.resultado()).isEqualByComparingTo("-180.00");
        assertThat(r.situacao()).isEqualTo("prejuizo");
        assertThat(valor(r, "margem_de_contribuicao")).isEqualByComparingTo("-180.00");
        // A linha do custo continua positiva: é o "(−)" que diz o sinal.
        assertThat(valor(r, "manutencao")).isEqualByComparingTo("300.00");
        assertThat((BigDecimal) r.indicadores().get("margemLiquida")).isEqualByComparingTo("-150.00");
    }

    @Test
    @DisplayName("equilíbrio é o zero exato — um centavo para cima já é lucro")
    void equilibrio() {
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "100.00", noPeriodo, turno(noPeriodo, 4));
        Long custo = informar(entregador, "combustivel", "100.00", noPeriodo, null);

        DreResponse zerado = dre.dre(entregador.getId(), "motoboy", inicio, fim);
        assertThat(zerado.resultado()).isEqualByComparingTo("0.00");
        assertThat(zerado.situacao()).isEqualTo("equilibrio");

        LancamentoGerencialRequest menor = pedido("combustivel", "99.99", noPeriodo, null);
        gerenciais.atualizar(custo, entregador.getId(), "motoboy", menor);
        DreResponse umCentavo = dre.dre(entregador.getId(), "motoboy", inicio, fim);
        assertThat(umCentavo.resultado()).isEqualByComparingTo("0.01");
        assertThat(umCentavo.situacao()).isEqualTo("lucro");
    }

    @Test
    @DisplayName("período vazio: tudo zero, equilíbrio, e os indicadores sem base vêm nulos")
    void periodoVazio() {
        for (Usuario u : List.of(entregador, lojista)) {
            DreResponse r = dre.dre(u.getId(), u.getTipo(), inicio, fim);

            assertThat(r.resultado()).isEqualByComparingTo("0.00");
            assertThat(r.situacao()).isEqualTo("equilibrio");
            assertThat(r.lancamentosManuais()).isZero();
            assertThat(r.linhas()).allSatisfy(l -> assertThat(l.valor()).isEqualByComparingTo("0.00"));
            assertThat(r.anterior().resultado()).isEqualByComparingTo("0.00");
            assertThat(r.anterior().situacao()).isEqualTo("equilibrio");
            assertThat(r.variacaoResultado()).isEqualByComparingTo("0.00");
        }

        Map<String, Object> ind = dre.dre(entregador.getId(), "motoboy", inicio, fim).indicadores();
        assertThat(ind.get("margemLiquida")).isNull();
        assertThat(ind.get("turnosPagos")).isEqualTo(0);
        assertThat(ind.get("lucroPorHora")).isNull();
        assertThat(ind.get("lucroPorTurno")).isNull();
        assertThat(ind.get("custoPorKm")).isNull();
        assertThat(ind.get("pontoDeEquilibrioTurnos")).isNull();
        assertThat(ind.get("pontoDeEquilibrioMotivo")).isEqualTo("sem turnos pagos no período");

        Map<String, Object> daLoja = dre.dre(lojista.getId(), "lojista", inicio, fim).indicadores();
        assertThat(daLoja.get("custoSobreReceita")).isNull();
        assertThat(daLoja.get("turnosFinalizados")).isEqualTo(0);
        assertThat(daLoja.get("custoMedioPorTurno")).isNull();
        assertThat(daLoja.get("resultadoPorTurno")).isNull();
    }

    @Test
    @DisplayName("ponto de equilíbrio vem nulo, com o motivo, quando a margem por turno não é positiva")
    void pontoDeEquilibrio_nuloComMargemNegativa() {
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "100.00", noPeriodo, turno(noPeriodo, 4));
        informar(entregador, "combustivel", "150.00", noPeriodo, null);
        informar(entregador, "seguro", "60.00", noPeriodo, null);

        Map<String, Object> ind = dre.dre(entregador.getId(), "motoboy", inicio, fim).indicadores();

        assertThat((BigDecimal) ind.get("margemDeContribuicaoPorTurno")).isEqualByComparingTo("-50.00");
        assertThat(ind.get("pontoDeEquilibrioTurnos")).isNull();
        assertThat(ind.get("pontoDeEquilibrioMotivo"))
                .isEqualTo("a margem por turno não cobre os custos variáveis");
    }

    @Test
    @DisplayName("ponto de equilíbrio arredonda para cima: meio turno não existe")
    void pontoDeEquilibrio_arredondaParaCima() {
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "100.00", noPeriodo, turno(noPeriodo, 4));
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "100.00", noPeriodo.plusDays(1),
                turno(noPeriodo.plusDays(1), 4));
        informar(entregador, "combustivel", "20.00", noPeriodo, null);
        // Margem por turno: (200 − 20) ÷ 2 = 90. Fixas de 181 ÷ 90 = 2,01 → 3.
        informar(entregador, "parcela_ou_aluguel_veiculo", "181.00", noPeriodo, null);

        assertThat(dre.dre(entregador.getId(), "motoboy", inicio, fim)
                .indicadores().get("pontoDeEquilibrioTurnos")).isEqualTo(3);
    }

    @Test
    @DisplayName("só o que foi concluído entra: pagamento pendente não é receita")
    void pendenteNaoConta() {
        Turno t = turno(noPeriodo, 4);
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "120.00", noPeriodo, t);
        Transacao pendente = extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "500.00", noPeriodo, t);
        pendente.setStatus(StatusTransacao.PENDENTE);
        transacaoRepo.save(pendente);

        assertThat(valor(dre.dre(entregador.getId(), "motoboy", inicio, fim), "receita_bruta"))
                .isEqualByComparingTo("120.00");
    }

    // ── Lojista ───────────────────────────────────────────────────────────

    @Test
    @DisplayName("lojista: taxas cobradas menos o custo das entregas — e reserva e liberação ficam de fora")
    void lojista_reservaELiberacaoNaoEntram() {
        Turno t = turno(noPeriodo, 4);
        // O dinheiro mudando de bolso: publicou (reserva 240), pagou um
        // entregador (120) e a vaga vazia voltou (liberação 120).
        extrato(lojista, TipoTransacao.RESERVA, "240.00", noPeriodo.minusDays(1), t);
        extrato(lojista, TipoTransacao.LIBERACAO_RESERVA, "120.00", noPeriodo, t);
        extrato(lojista, TipoTransacao.PAGAMENTO_ENVIADO, "120.00", noPeriodo, t);
        extrato(lojista, TipoTransacao.BONUS_ENVIADO, "10.00", noPeriodo, t);
        extrato(lojista, TipoTransacao.RECARGA, "900.00", noPeriodo.minusDays(2), null);
        informar(lojista, "taxa_de_entrega_cobrada", "500.00", noPeriodo, null);
        informar(lojista, "entrega_fora_do_app", "50.00", noPeriodo, null);
        informar(lojista, "outra_despesa_entrega", "30.00", noPeriodo, null);

        DreResponse r = dre.dre(lojista.getId(), "lojista", inicio, fim);

        assertThat(r.papel()).isEqualTo("lojista");
        assertThat(r.linhas()).extracting(Linha::chave).containsExactly(
                "receita_de_entregas", "custo_dos_entregadores", "entrega_fora_do_app",
                "margem_da_operacao", "outra_despesa_entrega", "resultado");

        assertThat(valor(r, "receita_de_entregas")).isEqualByComparingTo("500.00");
        // 120 de pagamento + 10 de gorjeta. Nem os 240 da reserva, nem os 120
        // da liberação, nem os 900 da recarga.
        assertThat(valor(r, "custo_dos_entregadores")).isEqualByComparingTo("130.00");
        assertThat(valor(r, "entrega_fora_do_app")).isEqualByComparingTo("50.00");
        assertThat(valor(r, "margem_da_operacao")).isEqualByComparingTo("320.00");
        assertThat(valor(r, "outra_despesa_entrega")).isEqualByComparingTo("30.00");
        assertThat(r.resultado()).isEqualByComparingTo("290.00");
        assertThat(r.situacao()).isEqualTo("lucro");

        Map<String, Object> ind = r.indicadores();
        // (130 + 50) ÷ 500.
        assertThat((BigDecimal) ind.get("custoSobreReceita")).isEqualByComparingTo("36.00");
        assertThat(ind.get("turnosFinalizados")).isEqualTo(1);
        assertThat((BigDecimal) ind.get("custoMedioPorTurno")).isEqualByComparingTo("130.00");
        assertThat((BigDecimal) ind.get("resultadoPorTurno")).isEqualByComparingTo("290.00");
        assertThat((BigDecimal) ind.get("gorjetasDadas")).isEqualByComparingTo("10.00");
    }

    @Test
    @DisplayName("lojista com prejuízo: as taxas cobradas não cobrem o custo dos entregadores")
    void lojista_prejuizo() {
        extrato(lojista, TipoTransacao.PAGAMENTO_ENVIADO, "130.00", noPeriodo, turno(noPeriodo, 4));
        informar(lojista, "taxa_de_entrega_cobrada", "48.00", noPeriodo, null);

        DreResponse r = dre.dre(lojista.getId(), "lojista", inicio, fim);

        assertThat(r.resultado()).isEqualByComparingTo("-82.00");
        assertThat(r.situacao()).isEqualTo("prejuizo");
        assertThat((BigDecimal) r.indicadores().get("custoSobreReceita")).isEqualByComparingTo("270.83");
    }

    @Test
    @DisplayName("a gorjeta é receita de quem recebe e custo de quem dá")
    void gorjeta_nosDoisLados() {
        Turno t = turno(noPeriodo, 4);
        extrato(entregador, TipoTransacao.BONUS, "15.00", noPeriodo, t);
        extrato(lojista, TipoTransacao.BONUS_ENVIADO, "15.00", noPeriodo, t);

        DreResponse doEntregador = dre.dre(entregador.getId(), "motoboy", inicio, fim);
        assertThat(valor(doEntregador, "gorjetas_recebidas")).isEqualByComparingTo("15.00");
        assertThat(valor(doEntregador, "receita_bruta")).isEqualByComparingTo("15.00");
        assertThat(doEntregador.resultado()).isEqualByComparingTo("15.00");

        DreResponse daLoja = dre.dre(lojista.getId(), "lojista", inicio, fim);
        assertThat(valor(daLoja, "custo_dos_entregadores")).isEqualByComparingTo("15.00");
        assertThat(daLoja.resultado()).isEqualByComparingTo("-15.00");
        assertThat((BigDecimal) daLoja.indicadores().get("gorjetasDadas")).isEqualByComparingTo("15.00");
    }

    // ── Período, caixa e recorrência ──────────────────────────────────────

    @Test
    @DisplayName("compara com o período anterior de MESMO tamanho, e a variação é em reais")
    void periodoAnterior() {
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "100.00", noAnterior, turno(noAnterior, 4));
        informar(entregador, "manutencao", "250.00", noAnterior, null);
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "130.00", noPeriodo, turno(noPeriodo, 4));

        DreResponse r = dre.dre(entregador.getId(), "motoboy", inicio, fim);

        // Dez dias; os dez de antes.
        assertThat(r.anterior().dataInicio()).isEqualTo(inicio.minusDays(10));
        assertThat(r.anterior().dataFim()).isEqualTo(inicio.minusDays(1));
        assertThat(r.anterior().resultado()).isEqualByComparingTo("-150.00");
        assertThat(r.anterior().situacao()).isEqualTo("prejuizo");
        assertThat(r.resultado()).isEqualByComparingTo("130.00");
        // De −150 para +130: melhorou R$ 280. Um percentual aqui não diria nada.
        assertThat(r.variacaoResultado()).isEqualByComparingTo("280.00");
    }

    @Test
    @DisplayName("regime de caixa: lançamento fora do período não entra, e nada entra antes de acontecer")
    void caixa() {
        informar(entregador, "combustivel", "10.00", inicio, null);
        informar(entregador, "combustivel", "20.00", fim, null);
        informar(entregador, "combustivel", "999.00", inicio.minusDays(1), null);
        informar(entregador, "combustivel", "999.00", fim.plusDays(1), null);

        // Os dois extremos são inclusivos.
        assertThat(valor(dre.dre(entregador.getId(), "motoboy", inicio, fim), "combustivel"))
                .isEqualByComparingTo("30.00");

        // Uma conta de amanhã não foi paga: um período que vai até a semana
        // que vem a ignora. Não dá mais para criá-la pelo serviço (SCRUM-49);
        // esta é a linha que já estava no banco antes de a data futura ser
        // recusada.
        gravarDireto(entregador, "seguro", "70.00", LocalDate.now().plusDays(1), false);
        informar(entregador, "seguro", "5.00", LocalDate.now(), null);
        DreResponse futuro = dre.dre(entregador.getId(), "motoboy",
                LocalDate.now().minusDays(1), LocalDate.now().plusDays(7));
        assertThat(valor(futuro, "seguro")).isEqualByComparingTo("5.00");
    }

    @Test
    @DisplayName("data de pagamento depois de hoje é recusada ao criar e ao editar; o \"até quando\" do recorrente pode ser futuro")
    void dataFutura_recusada() {
        LocalDate amanha = LocalDate.now().plusDays(1);

        assertThatThrownBy(() -> informar(entregador, "seguro", "70.00", amanha, null))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("No regime de caixa, o lançamento entra no dia em que foi pago. "
                        + "Informe uma data até hoje.");

        Long id = informar(entregador, "seguro", "70.00", LocalDate.now(), null);
        assertThatThrownBy(() -> gerenciais.atualizar(id, entregador.getId(), "motoboy",
                pedido("seguro", "70.00", amanha, null)))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("Informe uma data até hoje.");
        assertThat(gerencialRepo.findById(id).orElseThrow().getData()).isEqualTo(LocalDate.now());

        LancamentoGerencialRequest comFim = pedido("celular_internet", "35.00", LocalDate.now(), null);
        comFim.setRecorrente(true);
        comFim.setRecorrenteAte(LocalDate.now().plusYears(1));
        assertThat(gerenciais.criar(entregador.getId(), "motoboy", comFim).recorrenteAte())
                .isEqualTo(LocalDate.now().plusYears(1));
    }

    @Test
    @DisplayName("editar um recorrente a partir de uma data não reescreve o passado: os meses anteriores ficam com o valor antigo e os seguintes com o novo")
    void recorrenteEditadoAPartirDeUmaData() {
        // Seguro de R$ 70 há três meses, no dia do mês de hoje: três
        // vencimentos em meses anteriores e o deste mês, que é hoje.
        LocalDate hoje = LocalDate.now();
        LocalDate primeira = hoje.minusMonths(3);
        LocalDate esteMes = hoje.withDayOfMonth(1);
        LancamentoGerencialRequest seguro = pedido("seguro", "70.00", primeira, null);
        seguro.setRecorrente(true);
        Long antigoId = gerenciais.criar(entregador.getId(), "motoboy", seguro).id();
        assertThat(valor(dre.dre(entregador.getId(), "motoboy", primeira, hoje), "seguro"))
                .isEqualByComparingTo("280.00");

        // O seguro subiu para R$ 100 — a partir deste mês.
        LancamentoGerencialRequest reajuste = pedido("seguro", "100.00", primeira, null);
        reajuste.setRecorrente(true);
        reajuste.setDescricao("Reajuste anual");
        reajuste.setAplicarAPartirDe(esteMes);
        LancamentoGerencialResponse novo =
                gerenciais.atualizar(antigoId, entregador.getId(), "motoboy", reajuste);

        // Responde o novo: outra linha, com os dados novos, começando no
        // vencimento deste mês.
        assertThat(novo.id()).isNotEqualTo(antigoId);
        assertThat(novo.valor()).isEqualByComparingTo("100.00");
        assertThat(novo.recorrente()).isTrue();
        assertThat(novo.recorrenteAte()).isNull();
        assertThat(novo.descricao()).isEqualTo("Reajuste anual");
        assertThat(novo.data()).isEqualTo(Recorrencia.primeiraAPartirDe(primeira.getDayOfMonth(), esteMes));
        assertThat(novo.data()).isBetween(esteMes, hoje);

        // O antigo ficou como era, encerrado na véspera.
        LancamentoGerencial antigo = gerencialRepo.findById(antigoId).orElseThrow();
        assertThat(antigo.getValor()).isEqualByComparingTo("70.00");
        assertThat(antigo.getData()).isEqualTo(primeira);
        assertThat(antigo.getRecorrenteAte()).isEqualTo(esteMes.minusDays(1));

        // Os meses anteriores continuam valendo R$ 70 cada...
        DreResponse antes = dre.dre(entregador.getId(), "motoboy", primeira, esteMes.minusDays(1));
        assertThat(valor(antes, "seguro")).isEqualByComparingTo("210.00");
        // ...este mês vale R$ 100...
        DreResponse agora = dre.dre(entregador.getId(), "motoboy", esteMes, hoje);
        assertThat(valor(agora, "seguro")).isEqualByComparingTo("100.00");
        // ...e a DRE de um período que atravessa a troca soma os dois.
        DreResponse atravessa = dre.dre(entregador.getId(), "motoboy", primeira, hoje);
        assertThat(valor(atravessa, "seguro")).isEqualByComparingTo("310.00");
        assertThat(atravessa.lancamentosManuais()).isEqualTo(2);
    }

    @Test
    @DisplayName("sem \"aplicar a partir de\", editar um recorrente corrige o histórico inteiro, como antes")
    void recorrenteEditadoSemData_corrigeTudo() {
        LocalDate hoje = LocalDate.now();
        LocalDate primeira = hoje.minusMonths(3);
        LancamentoGerencialRequest seguro = pedido("seguro", "70.00", primeira, null);
        seguro.setRecorrente(true);
        Long id = gerenciais.criar(entregador.getId(), "motoboy", seguro).id();

        LancamentoGerencialRequest correcao = pedido("seguro", "100.00", primeira, null);
        correcao.setRecorrente(true);
        LancamentoGerencialResponse editado =
                gerenciais.atualizar(id, entregador.getId(), "motoboy", correcao);

        assertThat(editado.id()).isEqualTo(id);
        assertThat(valor(dre.dre(entregador.getId(), "motoboy", primeira, hoje), "seguro"))
                .isEqualByComparingTo("400.00");
        assertThat(gerencialRepo.findById(id).orElseThrow().getRecorrenteAte()).isNull();
    }

    @Test
    @DisplayName("\"aplicar a partir de\": só em recorrente, só até hoje; sem passado antes da data é a edição comum; e nunca estende o que já tinha acabado")
    void aplicarAPartirDe_cantos() {
        LocalDate hoje = LocalDate.now();
        LocalDate primeira = hoje.minusMonths(3);

        // Num avulso não quer dizer nada.
        Long avulso = informar(entregador, "combustivel", "30.00", hoje, null);
        LancamentoGerencialRequest noAvulso = pedido("combustivel", "40.00", hoje, null);
        noAvulso.setAplicarAPartirDe(hoje);
        assertThatThrownBy(() -> gerenciais.atualizar(avulso, entregador.getId(), "motoboy", noAvulso))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("só vale para lançamento que se repete todo mês");

        LancamentoGerencialRequest seguro = pedido("seguro", "70.00", primeira, null);
        seguro.setRecorrente(true);
        Long id = gerenciais.criar(entregador.getId(), "motoboy", seguro).id();

        // Desmarcar "repete todo mês" junto: encerrar é pelo "até quando".
        LancamentoGerencialRequest virandoAvulso = pedido("seguro", "100.00", primeira, null);
        virandoAvulso.setAplicarAPartirDe(hoje.withDayOfMonth(1));
        assertThatThrownBy(() -> gerenciais.atualizar(id, entregador.getId(), "motoboy", virandoAvulso))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("informe até quando ela vale");

        // Data futura.
        LancamentoGerencialRequest noFuturo = pedido("seguro", "100.00", primeira, null);
        noFuturo.setRecorrente(true);
        noFuturo.setAplicarAPartirDe(hoje.plusDays(1));
        assertThatThrownBy(() -> gerenciais.atualizar(id, entregador.getId(), "motoboy", noFuturo))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("Informe uma data até hoje para aplicar a mudança.");

        // A recorrência nova acabaria antes de começar.
        LancamentoGerencialRequest jaAcabou = pedido("seguro", "100.00", primeira, null);
        jaAcabou.setRecorrente(true);
        jaAcabou.setRecorrenteAte(hoje.withDayOfMonth(1).minusDays(1));
        jaAcabou.setAplicarAPartirDe(hoje.withDayOfMonth(1));
        assertThatThrownBy(() -> gerenciais.atualizar(id, entregador.getId(), "motoboy", jaAcabou))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("não há meses seguintes para aplicar a mudança");
        // Nada disso mexeu no lançamento.
        assertThat(gerencialRepo.findById(id).orElseThrow().getRecorrenteAte()).isNull();
        assertThat(gerencialRepo.findById(id).orElseThrow().getValor()).isEqualByComparingTo("70.00");

        // Sem ocorrência antes da data, não há passado a preservar: é a
        // edição comum, na mesma linha.
        LancamentoGerencialRequest desdeOComeco = pedido("seguro", "80.00", primeira, null);
        desdeOComeco.setRecorrente(true);
        desdeOComeco.setAplicarAPartirDe(primeira);
        long linhasAntes = gerencialRepo.count();
        assertThat(gerenciais.atualizar(id, entregador.getId(), "motoboy", desdeOComeco).id()).isEqualTo(id);
        assertThat(gerencialRepo.count()).isEqualTo(linhasAntes);

        // Um recorrente que já tinha acabado antes da data continua acabando
        // onde acabava: a divisão encerra, não estende.
        LocalDate fimAntigo = primeira.plusDays(40);
        LancamentoGerencialRequest comFim = pedido("celular_internet", "35.00", primeira, null);
        comFim.setRecorrente(true);
        comFim.setRecorrenteAte(fimAntigo);
        Long celular = gerenciais.criar(entregador.getId(), "motoboy", comFim).id();
        LancamentoGerencialRequest retomado = pedido("celular_internet", "45.00", primeira, null);
        retomado.setRecorrente(true);
        retomado.setAplicarAPartirDe(hoje.withDayOfMonth(1));
        gerenciais.atualizar(celular, entregador.getId(), "motoboy", retomado);
        assertThat(gerencialRepo.findById(celular).orElseThrow().getRecorrenteAte()).isEqualTo(fimAntigo);
    }

    @Test
    @DisplayName("a lista mostra à frente o que ainda vai começar, com zero ocorrências — não conta na DRE, mas dá para corrigir e excluir")
    void listaMostraOQueAindaVaiComecar() {
        LocalDate hoje = LocalDate.now();
        Long futuro = gravarDireto(entregador, "seguro", "70.00", hoje.plusDays(3), true);
        Long deHoje = informar(entregador, "combustivel", "30.00", hoje, null);

        List<LancamentoGerencialResponse> lista = gerenciais.listar(entregador.getId(), hoje.minusDays(6), hoje);
        assertThat(lista).extracting(LancamentoGerencialResponse::id).containsExactly(futuro, deHoje);
        assertThat(lista.get(0).ocorrenciasNoPeriodo()).isZero();
        assertThat(lista.get(0).valorNoPeriodo()).isEqualByComparingTo("0.00");
        assertThat(lista.get(1).ocorrenciasNoPeriodo()).isEqualTo(1);

        // A lista e a DRE continuam somando o mesmo.
        DreResponse r = dre.dre(entregador.getId(), "motoboy", hoje.minusDays(6), hoje);
        assertThat(valor(r, "seguro")).isEqualByComparingTo("0.00");
        assertThat(valor(r, "combustivel")).isEqualByComparingTo("30.00");
        assertThat(r.lancamentosManuais()).isEqualTo(1);

        // Num período que já acabou, ele não tem o que fazer.
        assertThat(gerenciais.listar(entregador.getId(), inicio, fim)).isEmpty();

        // Corrigir exige trazer a data para hoje ou antes; excluir, nada.
        assertThatThrownBy(() -> gerenciais.atualizar(futuro, entregador.getId(), "motoboy",
                pedido("seguro", "70.00", hoje.plusDays(3), null)))
                .isInstanceOf(ResponseStatusException.class);
        gerenciais.atualizar(futuro, entregador.getId(), "motoboy", pedido("seguro", "70.00", hoje, null));
        assertThat(valor(dre.dre(entregador.getId(), "motoboy", hoje, hoje), "seguro"))
                .isEqualByComparingTo("70.00");
        gerenciais.excluir(futuro, entregador.getId());
        assertThat(gerenciais.listar(entregador.getId(), hoje, hoje))
                .extracting(LancamentoGerencialResponse::id).containsExactly(deHoje);
    }

    @Test
    @DisplayName("recorrente conta uma vez por ocorrência dentro do período, sem linha gravada por mês")
    void recorrente() {
        // Todo mês, desde 70 dias atrás, no dia do mês daquela data.
        LocalDate primeira = LocalDate.now().minusDays(70);
        LancamentoGerencialRequest req = pedido("parcela_ou_aluguel_veiculo", "200.00", primeira, null);
        req.setRecorrente(true);
        gerenciais.criar(entregador.getId(), "motoboy", req);

        int vezes = Recorrencia.vezes(primeira, null, primeira, LocalDate.now());
        assertThat(vezes).isBetween(2, 3);

        DreResponse r = dre.dre(entregador.getId(), "motoboy", primeira, LocalDate.now());
        assertThat(valor(r, "parcela_ou_aluguel_veiculo"))
                .isEqualByComparingTo(new BigDecimal("200.00").multiply(BigDecimal.valueOf(vezes)));
        // Um lançamento só — é uma regra, não uma linha por mês.
        assertThat(r.lancamentosManuais()).isEqualTo(1);

        // Um período em que o dia do mês não cai: em vigor, mas não aconteceu.
        LocalDate depois = primeira.plusDays(1);
        assertThat(valor(dre.dre(entregador.getId(), "motoboy", depois, depois.plusDays(5)),
                "parcela_ou_aluguel_veiculo")).isEqualByComparingTo("0.00");
    }

    @Test
    @DisplayName("o que é de outro usuário não entra na DRE de ninguém")
    void isolamentoEntreUsuarios() {
        Usuario outro = conta("motoboy", "Outro entregador");
        extrato(outro, TipoTransacao.PAGAMENTO_RECEBIDO, "400.00", noPeriodo, turno(noPeriodo, 4));
        informar(outro, "combustivel", "90.00", noPeriodo, null);

        DreResponse r = dre.dre(entregador.getId(), "motoboy", inicio, fim);
        assertThat(r.resultado()).isEqualByComparingTo("0.00");
        assertThat(r.lancamentosManuais()).isZero();
    }

    // ── Mês a mês ─────────────────────────────────────────────────────────

    @Test
    @DisplayName("mensal: doze linhas, e em cada uma receita − custos = resultado")
    void mensal() {
        LocalDate hoje = LocalDate.now();
        extrato(entregador, TipoTransacao.PAGAMENTO_RECEBIDO, "300.00", hoje, turno(hoje, 4));
        informar(entregador, "combustivel", "40.00", hoje, null);
        informar(entregador, "das_mei", "80.00", hoje, null);

        List<DreResponse.Mes> meses = dre.mensal(entregador.getId(), "motoboy", hoje.getYear());

        assertThat(meses).hasSize(12);
        assertThat(meses).extracting(DreResponse.Mes::mes)
                .containsExactly(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
        assertThat(meses.get(0).rotulo()).isEqualTo("Jan");
        assertThat(meses).allSatisfy(m ->
                assertThat(m.receita().subtract(m.custos())).isEqualByComparingTo(m.resultado()));

        DreResponse.Mes esteMes = meses.get(hoje.getMonthValue() - 1);
        assertThat(esteMes.receita()).isEqualByComparingTo("300.00");
        assertThat(esteMes.custos()).isEqualByComparingTo("120.00");
        assertThat(esteMes.resultado()).isEqualByComparingTo("180.00");
        assertThat(esteMes.situacao()).isEqualTo("lucro");

        // Um ano sem nada: doze zeros, não uma lista vazia.
        List<DreResponse.Mes> vazio = dre.mensal(entregador.getId(), "motoboy", Year.now().getValue() - 3);
        assertThat(vazio).hasSize(12)
                .allSatisfy(m -> assertThat(m.situacao()).isEqualTo("equilibrio"));
    }

    // ── Apoio ─────────────────────────────────────────────────────────────

    private static Linha linha(DreResponse r, String chave) {
        return r.linhas().stream().filter(l -> l.chave().equals(chave)).findFirst()
                .orElseThrow(() -> new AssertionError("sem a linha " + chave));
    }

    private static BigDecimal valor(DreResponse r, String chave) {
        return linha(r, chave).valor();
    }

    private Usuario conta(String tipo, String nome) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(tipo + "-" + UUID.randomUUID() + "@dre.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }

    /** Um turno finalizado de [horas] horas naquele dia — para as horas trabalhadas. */
    private Turno turno(LocalDate dia, int horas) {
        Turno t = new Turno();
        t.setLojistId(lojista.getId());
        t.setTitulo("Turno da DRE");
        t.setDataInicio(dia.atTime(10, 0));
        t.setDataFim(dia.atTime(10 + horas, 0));
        t.setValorEstimado(new BigDecimal("120.00"));
        t.setStatus(StatusTurno.FINALIZADO);
        return turnoRepo.save(t);
    }

    /** Um lançamento CONCLUÍDO no extrato, na data do teste. */
    private Transacao extrato(Usuario dono, TipoTransacao tipo, String valor, LocalDate dia, Turno turno) {
        Transacao t = new Transacao();
        t.setUsuarioId(dono.getId());
        t.setTurnoId(turno == null ? null : turno.getId());
        t.setTipo(tipo);
        t.setNatureza(switch (tipo) {
            case PAGAMENTO_RECEBIDO, BONUS, RECARGA, LIBERACAO_RESERVA, ESTORNO -> NaturezaTransacao.CREDITO;
            default -> NaturezaTransacao.DEBITO;
        });
        t.setValor(new BigDecimal(valor));
        t.setDescricao(tipo.getValor());
        t.setStatus(StatusTransacao.CONCLUIDO);
        t.setIdempotencyKey("dre-teste:" + UUID.randomUUID());
        t.setCriadoEm(dia.atTime(12, 0));
        return transacaoRepo.save(t);
    }

    private static LancamentoGerencialRequest pedido(String categoria, String valor, LocalDate data, String km) {
        LancamentoGerencialRequest req = new LancamentoGerencialRequest();
        req.setCategoria(categoria);
        req.setValor(new BigDecimal(valor));
        req.setData(data);
        req.setKm(km == null ? null : new BigDecimal(km));
        return req;
    }

    private Long informar(Usuario quem, String categoria, String valor, LocalDate data, String km) {
        return gerenciais.criar(quem.getId(), quem.getTipo(), pedido(categoria, valor, data, km)).id();
    }

    /**
     * Uma linha gravada sem passar pelo serviço — o que já estava no banco
     * antes de a data futura ser recusada, ou a regra nova de um recorrente
     * que ainda vai começar.
     */
    private Long gravarDireto(Usuario quem, String categoria, String valor, LocalDate data,
                              boolean recorrente) {
        LancamentoGerencial l = new LancamentoGerencial(quem.getId());
        l.setCategoria(CategoriaLancamento.de(categoria));
        l.setValor(new BigDecimal(valor));
        l.setData(data);
        l.setRecorrente(recorrente);
        return gerencialRepo.save(l).getId();
    }
}
