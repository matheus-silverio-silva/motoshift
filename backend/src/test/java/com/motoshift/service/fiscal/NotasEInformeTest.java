package com.motoshift.service.fiscal;

import com.motoshift.dto.InformeAnualResponse;
import com.motoshift.dto.NotaFiscalFiltro;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.support.CenarioFinanceiro;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Year;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * A lista de notas com filtros e o informe anual.
 *
 * <p>O teste que mais importa aqui é o da soma: o informe de rendimentos tem
 * de bater com os pagamentos recebidos concluídos do ano, conferidos direto no
 * extrato — inclusive quando falta nota para algum deles, e excluindo o que
 * caiu em outro ano.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class NotasEInformeTest {

    @Autowired private CenarioFinanceiro cenario;
    @Autowired private NotaFiscalService notas;
    @Autowired private InformeRendimentosService informes;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;
    @PersistenceContext private EntityManager em;

    private Long lojaA;
    private Long lojaB;
    private Long entregador;
    private Long outroEntregador;

    @BeforeEach
    void contas() {
        lojaA = cenario.conta("lojista", "Loja A", "11222333000144").getId();
        lojaB = cenario.conta("lojista", "Loja B", "55666777000188").getId();
        entregador = cenario.conta("motoboy", "Entregador Informado", "12345678900").getId();
        outroEntregador = cenario.conta("motoboy", "Outro", "98765432100").getId();
    }

    // ── Filtros ─────────────────────────────────────────────────────────────

    @Test
    @DisplayName("papel, status, contraparte e turno estreitam a lista; página traz o total")
    void filtros() {
        Turno t1 = cenario.turnoPago(lojaA, "100.00", entregador);
        Turno t2 = cenario.turnoPago(lojaB, "80.00", entregador);
        Turno t3 = cenario.turnoPago(lojaA, "60.00", outroEntregador);
        NotaFiscalResponse n1 = notas.emitir(t1.getId(), entregador, entregador).nota();
        NotaFiscalResponse n2 = notas.emitir(t2.getId(), entregador, entregador).nota();
        NotaFiscalResponse n3 = notas.emitir(t3.getId(), outroEntregador, lojaA).nota();
        notas.cancelar(n2.getId(), "teste", entregador);

        assertThat(ids(entregador, filtro(f -> f.setPapel("prestador")))).containsExactlyInAnyOrder(n1.getId(), n2.getId());
        assertThat(ids(entregador, filtro(f -> f.setPapel("tomador")))).isEmpty();
        assertThat(ids(lojaA, filtro(f -> f.setPapel("tomador")))).containsExactlyInAnyOrder(n1.getId(), n3.getId());

        assertThat(ids(entregador, filtro(f -> f.setStatus("emitida")))).containsExactly(n1.getId());
        assertThat(ids(entregador, filtro(f -> f.setStatus("cancelada")))).containsExactly(n2.getId());

        assertThat(ids(entregador, filtro(f -> f.setContraparteId(lojaB)))).containsExactly(n2.getId());
        assertThat(ids(lojaA, filtro(f -> f.setContraparteId(outroEntregador)))).containsExactly(n3.getId());

        assertThat(ids(lojaA, filtro(f -> f.setTurnoId(t1.getId())))).containsExactly(n1.getId());

        Page<NotaFiscalResponse> pagina = notas.listar(entregador, new NotaFiscalFiltro(), PageRequest.of(0, 1));
        assertThat(pagina.getContent()).hasSize(1);
        assertThat(pagina.getTotalElements()).isEqualTo(2);
    }

    @Test
    @DisplayName("o período filtra pela competência — a data do serviço, com o dia final inteiro")
    void periodoDeCompetencia() {
        Turno t = cenario.turnoPago(lojaA, "100.00", entregador);
        NotaFiscalResponse n = notas.emitir(t.getId(), entregador, entregador).nota();
        LocalDate dia = t.getDataInicio().toLocalDate();

        assertThat(ids(entregador, filtro(f -> { f.setCompetenciaDe(dia); f.setCompetenciaAte(dia); })))
                .containsExactly(n.getId());
        assertThat(ids(entregador, filtro(f -> f.setCompetenciaDe(dia.plusDays(1))))).isEmpty();
        assertThat(ids(entregador, filtro(f -> f.setCompetenciaAte(dia.minusDays(1))))).isEmpty();
    }

    @Test
    @DisplayName("filtro inválido é 400, e não uma lista vazia que pareceria 'sem notas'")
    void filtroInvalido() {
        for (NotaFiscalFiltro f : new NotaFiscalFiltro[]{
                filtro(x -> x.setPapel("prestdor")),
                filtro(x -> x.setStatus("rasurada")),
                filtro(x -> { x.setCompetenciaDe(LocalDate.of(2026, 5, 2)); x.setCompetenciaAte(LocalDate.of(2026, 5, 1)); })}) {
            assertThatExceptionOfType(ResponseStatusException.class)
                    .isThrownBy(() -> notas.listar(entregador, f, null))
                    .satisfies(e -> assertThat(e.getStatusCode().value()).isEqualTo(400));
        }
    }

    // ── Informe anual ───────────────────────────────────────────────────────

    @Test
    @DisplayName("a soma do informe é a soma dos pagamentos recebidos concluídos do ano")
    void informeBateComOExtrato() {
        cenario.turnoPago(lojaA, "100.00", entregador);
        Turno t2 = cenario.turnoPago(lojaA, "70.00", entregador);
        cenario.turnoPago(lojaB, "45.50", entregador);
        Turno doAnoPassado = cenario.turnoPago(lojaB, "999.00", entregador);
        moverParaOAnoPassado(cenario.pagamentoRecebido(doAnoPassado, entregador));
        // Uma nota emitida, as outras não: o informe conta todas.
        notas.emitir(t2.getId(), entregador, entregador);

        int ano = Year.now().getValue();
        InformeAnualResponse inf = informes.informe(entregador, false, ano);

        BigDecimal doExtrato = transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(entregador).stream()
                .filter(t -> t.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO)
                .filter(t -> t.getStatus() == StatusTransacao.CONCLUIDO)
                .filter(t -> t.getCriadoEm().getYear() == ano)
                .map(Transacao::getValor)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        assertThat(inf.total()).isEqualByComparingTo(doExtrato).isEqualByComparingTo("215.50");
        assertThat(inf.pagamentos()).isEqualTo(3);
        assertThat(inf.notasEmitidas()).isEqualTo(1);
        assertThat(inf.papel()).isEqualTo("prestador");

        // As duas quebras fecham no total.
        assertThat(inf.contrapartes().stream().map(InformeAnualResponse.PorContraparte::total)
                .reduce(BigDecimal.ZERO, BigDecimal::add)).isEqualByComparingTo(inf.total());
        assertThat(inf.meses()).hasSize(12);
        assertThat(inf.meses().stream().map(InformeAnualResponse.PorMes::total)
                .reduce(BigDecimal.ZERO, BigDecimal::add)).isEqualByComparingTo(inf.total());

        // Por fonte pagadora, com o CNPJ mascarado.
        assertThat(inf.contrapartes()).anySatisfy(c -> {
            assertThat(c.contraparteId()).isEqualTo(lojaA);
            assertThat(c.total()).isEqualByComparingTo("170.00");
            assertThat(c.documento()).isEqualTo("**.222.333/0001-**");
        });

        // O pagamento do ano passado está no informe do ano passado.
        assertThat(informes.informe(entregador, false, ano - 1).total()).isEqualByComparingTo("999.00");
    }

    @Test
    @DisplayName("para o lojista, o informe é o total de serviços tomados por prestador")
    void informeDoLojista() {
        cenario.turnoPago(lojaA, "100.00", entregador);
        cenario.turnoPago(lojaA, "60.00", entregador, outroEntregador);

        InformeAnualResponse inf = informes.informe(lojaA, true, Year.now().getValue());

        assertThat(inf.papel()).isEqualTo("tomador");
        assertThat(inf.total()).isEqualByComparingTo("220.00");
        assertThat(inf.contrapartes())
                .extracting(InformeAnualResponse.PorContraparte::contraparteId)
                .containsExactlyInAnyOrder(entregador, outroEntregador);
        // O entregador não tem CPF no cadastro: sai como não informado.
        assertThat(inf.contrapartes()).allSatisfy(c -> assertThat(c.documento()).isNull());
    }

    @Test
    @DisplayName("o CSV traz a marca de simulação, o total e não executa fórmula")
    void csv() {
        Usuario loja = usuarioRepo.findById(lojaA).orElseThrow();
        loja.setNomeFantasia("=HYPERLINK(\"http://mal\")");
        usuarioRepo.save(loja);
        cenario.turnoPago(lojaA, "100.00", entregador);

        String csv = informes.exportarCsv(entregador, false, Year.now().getValue());

        assertThat(csv).startsWith("DOCUMENTO SIMULADO — SEM VALOR FISCAL");
        assertThat(csv).contains("fonte_pagadora;documento;total;iss_retido;irrf_retido;pagamentos;notas_emitidas");
        assertThat(csv).contains("TOTAL;;100.00;");
        assertThat(csv).contains("'=HYPERLINK");
        assertThat(csv).doesNotContain(";=HYPERLINK").doesNotContain("\n=HYPERLINK");
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private java.util.List<Long> ids(Long usuario, NotaFiscalFiltro f) {
        return notas.listar(usuario, f, null).getContent().stream().map(NotaFiscalResponse::getId).toList();
    }

    private static NotaFiscalFiltro filtro(java.util.function.Consumer<NotaFiscalFiltro> ajuste) {
        NotaFiscalFiltro f = new NotaFiscalFiltro();
        ajuste.accept(f);
        return f;
    }

    /**
     * criado_em não é atualizável pela entidade (e não deve ser): o teste move
     * o lançamento no banco e limpa o contexto, para a leitura seguinte ver o
     * que o banco tem.
     */
    private void moverParaOAnoPassado(Transacao t) {
        em.flush();
        em.createNativeQuery("UPDATE transacoes SET criado_em = :d WHERE id = :id")
                .setParameter("d", LocalDateTime.of(Year.now().getValue() - 1, 6, 15, 12, 0))
                .setParameter("id", t.getId())
                .executeUpdate();
        em.clear();
    }
}
