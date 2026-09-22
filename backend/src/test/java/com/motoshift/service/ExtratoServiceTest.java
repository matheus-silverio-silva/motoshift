package com.motoshift.service;

import com.motoshift.dto.ExtratoFiltro;
import com.motoshift.dto.FluxoPontoResponse;
import com.motoshift.dto.ResumoFinanceiroResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * Os filtros do extrato, um a um e combinados.
 *
 * <p>Cada filtro é testado sozinho de propósito: combinados, um filtro quebrado
 * pode ser mascarado por outro que já teria removido a linha errada. Depois vêm
 * as combinações, que é como a tela realmente usa.
 *
 * <p>Os lançamentos são gravados direto pelo repositório, e não pelo ledger: o
 * que está sendo testado é a consulta, e passar pelo ledger amarraria o cenário
 * às regras de saldo — não dá para ter um débito de R$ 500 e um de R$ 10 numa
 * carteira montada só para exercitar um WHERE.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class ExtratoServiceTest {

    @Autowired private ExtratoService extrato;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    private Long usuario;
    private Long outro;

    @BeforeEach
    void cenario() {
        usuario = conta().getId();
        outro = conta().getId();

        // Um extrato pequeno e variado, com datas espalhadas.
        lancamento(TipoTransacao.RECARGA, "1000.00", dia(20), null, null, "Recarga via Pix");
        lancamento(TipoTransacao.RESERVA, "360.00", dia(18), 500L, null, "Reserva do turno: Pizzaria");
        lancamento(TipoTransacao.PAGAMENTO_ENVIADO, "120.00", dia(15), 500L, outro,
                "Pagamento do turno: Pizzaria");
        lancamento(TipoTransacao.LIBERACAO_RESERVA, "240.00", dia(15), 500L, null,
                "Vagas não preenchidas: Pizzaria");
        lancamento(TipoTransacao.PAGAMENTO_RECEBIDO, "95.00", dia(5), 501L, outro,
                "Turno finalizado: Farmácia");
        lancamento(TipoTransacao.SAQUE, "200.00", dia(2), null, null, "Transferência Pix — a@b.com");
    }

    // -- Filtros isolados ----------------------------------------------------

    @Nested
    @DisplayName("cada filtro sozinho")
    class Isolados {

        @Test
        @DisplayName("sem filtro nenhum, o extrato é o do dono — e só dele")
        void semFiltro_soODono() {
            assertThat(buscar(new ExtratoFiltro())).hasSize(6);

            ExtratoFiltro f = new ExtratoFiltro();
            assertThat(extrato.extrato(outro, f, PageRequest.of(0, 50)).getContent()).isEmpty();
        }

        @Test
        @DisplayName("período: as duas pontas entram inteiras")
        void periodo_inclusivoNasDuasPontas() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setDataInicio(LocalDate.now().minusDays(15));
            f.setDataFim(LocalDate.now().minusDays(15));

            // Os dois lançamentos do dia 15 entram: o fim do intervalo cobre o
            // dia inteiro, não só a meia-noite.
            assertThat(buscar(f)).hasSize(2);
        }

        @Test
        @DisplayName("tipos: aceita uma lista, não só um valor")
        void tipos_aceitaLista() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setTipos(List.of(TipoTransacao.RECARGA, TipoTransacao.SAQUE));

            assertThat(buscar(f)).extracting(TransacaoResponse::getTipo)
                    .containsExactlyInAnyOrder(TipoTransacao.RECARGA, TipoTransacao.SAQUE);
        }

        @Test
        @DisplayName("natureza: separa o que entrou do que saiu")
        void natureza_separaEntradaDeSaida() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setNatureza(NaturezaTransacao.DEBITO);

            assertThat(buscar(f)).extracting(TransacaoResponse::getTipo)
                    .containsExactlyInAnyOrder(TipoTransacao.RESERVA,
                            TipoTransacao.PAGAMENTO_ENVIADO, TipoTransacao.SAQUE);
        }

        @Test
        @DisplayName("turno: traz o que aconteceu com um turno específico")
        void turno_filtra() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setTurnoId(500L);

            assertThat(buscar(f)).hasSize(3);
        }

        @Test
        @DisplayName("contraparte: o que foi trocado com uma pessoa")
        void contraparte_filtra() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setContraparteId(outro);

            assertThat(buscar(f)).hasSize(2);
        }

        @Test
        @DisplayName("faixa de valor: mínimo e máximo, ambos inclusivos")
        void faixaDeValor_inclusiva() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setValorMin(new BigDecimal("120.00"));
            f.setValorMax(new BigDecimal("240.00"));

            assertThat(buscar(f)).extracting(TransacaoResponse::getValor)
                    .allSatisfy(v -> assertThat(v)
                            .isGreaterThanOrEqualTo(new BigDecimal("120.00"))
                            .isLessThanOrEqualTo(new BigDecimal("240.00")));
            // 120 (pagamento), 200 (saque) e 240 (liberação) — as pontas entram.
            assertThat(buscar(f)).hasSize(3);
        }

        @Test
        @DisplayName("busca: texto na descrição, sem diferenciar maiúsculas")
        void busca_ignoraCaixa() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setBusca("pizzaria");

            assertThat(buscar(f)).hasSize(3);
        }

        @Test
        @DisplayName("status: pendente e concluído não se misturam")
        void status_filtra() {
            ExtratoFiltro f = new ExtratoFiltro();
            f.setStatus(StatusTransacao.CONCLUIDO);
            assertThat(buscar(f)).hasSize(6);

            f.setStatus(StatusTransacao.PENDENTE);
            assertThat(buscar(f)).isEmpty();
        }
    }

    // -- Combinações e paginação ---------------------------------------------

    @Test
    @DisplayName("filtros combinados se acumulam — cada um estreita o resultado")
    void filtrosCombinados_seAcumulam() {
        ExtratoFiltro f = new ExtratoFiltro();
        f.setTurnoId(500L);
        f.setNatureza(NaturezaTransacao.DEBITO);
        f.setValorMin(new BigDecimal("100.00"));

        assertThat(buscar(f)).extracting(TransacaoResponse::getTipo)
                .containsExactlyInAnyOrder(TipoTransacao.RESERVA, TipoTransacao.PAGAMENTO_ENVIADO);
    }

    @Test
    @DisplayName("combinação que não casa com nada devolve vazio, não a lista inteira")
    void combinacaoImpossivel_devolveVazio() {
        ExtratoFiltro f = new ExtratoFiltro();
        f.setTipos(List.of(TipoTransacao.SAQUE));
        f.setTurnoId(500L);

        assertThat(buscar(f)).isEmpty();
    }

    @Test
    @DisplayName("paginação respeita o total e a ordem, do mais recente para o mais antigo")
    void paginacao() {
        ExtratoFiltro f = new ExtratoFiltro();

        Page<TransacaoResponse> primeira = extrato.extrato(usuario, f, PageRequest.of(0, 4));
        Page<TransacaoResponse> segunda = extrato.extrato(usuario, f, PageRequest.of(1, 4));

        assertThat(primeira.getTotalElements()).isEqualTo(6);
        assertThat(primeira.getContent()).hasSize(4);
        assertThat(segunda.getContent()).hasSize(2);

        // Mais recente primeiro, e sem repetir linha entre as páginas.
        assertThat(primeira.getContent().get(0).getCriadoEm())
                .isAfter(primeira.getContent().get(3).getCriadoEm());
        assertThat(segunda.getContent()).extracting(TransacaoResponse::getId)
                .doesNotContainAnyElementsOf(
                        primeira.getContent().stream().map(TransacaoResponse::getId).toList());
    }

    @Test
    @DisplayName("o filtro vale também na exportação — CSV não é a lista inteira disfarçada")
    void exportar_respeitaOFiltro() {
        ExtratoFiltro f = new ExtratoFiltro();
        f.setTipos(List.of(TipoTransacao.SAQUE));

        String csv = extrato.exportarCsv(usuario, f);

        assertThat(csv.lines()).hasSize(2); // cabeçalho + 1 lançamento
        assertThat(csv).contains("saque").doesNotContain("recarga");
    }

    @Test
    @DisplayName("o CSV neutraliza texto que a planilha executaria como fórmula")
    void exportar_neutralizaFormula() {
        lancamento(TipoTransacao.BONUS, "10.00", dia(1), null, null, "=SOMA(A1:A9)");

        ExtratoFiltro f = new ExtratoFiltro();
        f.setTipos(List.of(TipoTransacao.BONUS));

        assertThat(extrato.exportarCsv(usuario, f)).contains("'=SOMA(A1:A9)");
    }

    // -- Resumo --------------------------------------------------------------

    @Test
    @DisplayName("resumo soma entradas e saídas do período e mostra o saldo atual")
    void resumo_somaOPeriodo() {
        ResumoFinanceiroResponse r = extrato.resumo(
                usuario, LocalDate.now().minusDays(30), LocalDate.now());

        // 1000 + 240 + 95 de crédito; 360 + 120 + 200 de débito.
        assertThat(r.entradas()).isEqualByComparingTo("1335.00");
        assertThat(r.saidas()).isEqualByComparingTo("680.00");
        assertThat(r.liquido()).isEqualByComparingTo("655.00");
        assertThat(r.porTipo()).isNotEmpty();
    }

    @Test
    @DisplayName("resumo recorta pelo período pedido")
    void resumo_recortaPeriodo() {
        ResumoFinanceiroResponse r = extrato.resumo(
                usuario, LocalDate.now().minusDays(6), LocalDate.now());

        // Só o pagamento recebido (dia 5) e o saque (dia 2).
        assertThat(r.entradas()).isEqualByComparingTo("95.00");
        assertThat(r.saidas()).isEqualByComparingTo("200.00");
    }

    @Test
    @DisplayName("período invertido é erro, não um resultado vazio que parece 'sem movimento'")
    void resumo_periodoInvertido_erro() {
        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> extrato.resumo(
                        usuario, LocalDate.now(), LocalDate.now().minusDays(10)))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));
    }

    // -- Fluxo ---------------------------------------------------------------

    @Test
    @DisplayName("fluxo por dia traz um ponto por dia do período, com zero onde não houve nada")
    void fluxo_porDia_preencheOsBuracos() {
        List<FluxoPontoResponse> serie = extrato.fluxo(usuario, "dia",
                LocalDate.now().minusDays(6), LocalDate.now());

        assertThat(serie).hasSize(7);
        assertThat(serie).anySatisfy(p ->
                assertThat(p.entradas()).isEqualByComparingTo("95.00"));
        assertThat(serie).anySatisfy(p ->
                assertThat(p.saidas()).isEqualByComparingTo("200.00"));
        // Dias sem lançamento existem na série, zerados.
        assertThat(serie).anySatisfy(p -> {
            assertThat(p.entradas()).isEqualByComparingTo("0.00");
            assertThat(p.saidas()).isEqualByComparingTo("0.00");
        });
    }

    @Test
    @DisplayName("fluxo por mês dobra os dias e o líquido fecha com o resumo")
    void fluxo_porMes_fechaComOResumo() {
        LocalDate de = LocalDate.now().minusDays(30);
        LocalDate ate = LocalDate.now();

        BigDecimal liquidoDaSerie = extrato.fluxo(usuario, "mes", de, ate).stream()
                .map(FluxoPontoResponse::liquido)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        assertThat(liquidoDaSerie).isEqualByComparingTo(extrato.resumo(usuario, de, ate).liquido());
    }

    @Test
    @DisplayName("fluxo por semana começa na segunda-feira")
    void fluxo_porSemana_comecaNaSegunda() {
        List<FluxoPontoResponse> serie = extrato.fluxo(usuario, "semana",
                LocalDate.now().minusDays(21), LocalDate.now());

        assertThat(serie).isNotEmpty();
        assertThat(serie).allSatisfy(p ->
                assertThat(p.inicio().getDayOfWeek()).isEqualTo(java.time.DayOfWeek.MONDAY));
    }

    @Test
    @DisplayName("agrupamento desconhecido é 400, não um gráfico silenciosamente errado")
    void fluxo_agrupamentoInvalido_erro() {
        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> extrato.fluxo(usuario, "trimestre", null, null))
                .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));
    }

    // -- Apoio ---------------------------------------------------------------

    private List<TransacaoResponse> buscar(ExtratoFiltro filtro) {
        return extrato.extrato(usuario, filtro, PageRequest.of(0, 50)).getContent();
    }

    private static LocalDateTime dia(int atras) {
        return LocalDate.now().minusDays(atras).atTime(12, 0);
    }

    private Usuario conta() {
        Usuario u = new Usuario();
        u.setNome("Conta de extrato");
        u.setEmail("extrato-" + UUID.randomUUID() + "@ledger.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo("motoboy");
        return usuarioRepo.save(u);
    }

    private void lancamento(TipoTransacao tipo, String valor, LocalDateTime quando,
                            Long turnoId, Long contraparteId, String descricao) {
        Transacao t = new Transacao();
        t.setUsuarioId(usuario);
        t.setContraparteId(contraparteId);
        t.setTurnoId(turnoId);
        t.setTipo(tipo);
        t.setNatureza(switch (tipo) {
            case SAQUE, RESERVA, PAGAMENTO_ENVIADO -> NaturezaTransacao.DEBITO;
            default -> NaturezaTransacao.CREDITO;
        });
        t.setValor(new BigDecimal(valor));
        t.setDescricao(descricao);
        t.setStatus(StatusTransacao.CONCLUIDO);
        t.setIdempotencyKey("extrato-teste:" + UUID.randomUUID());
        t.setCriadoEm(quando);
        transacaoRepo.save(t);
    }
}
