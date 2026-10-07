package com.motoshift.service;

import com.motoshift.dto.DreResponse;
import com.motoshift.dto.DreResponse.Anterior;
import com.motoshift.dto.DreResponse.Linha;
import com.motoshift.dto.DreResponse.Mes;
import com.motoshift.entity.CategoriaLancamento;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.service.LancamentoGerencialService.Ocorrido;
import com.motoshift.service.LancamentosDoExtrato.Lancamento;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.Year;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Resultado do período — lucro ou prejuízo — numa DRE simplificada, para o
 * entregador e para o lojista (RF13 / SCRUM-47).
 *
 * <p><b>O que faltava.</b> O relatório dizia quanto entrou. "Ganhos", para o
 * entregador, era faturamento bruto: combustível, manutenção, DAS e custos
 * fixos não apareciam, e o app não sabia se ele teve lucro. O lojista via o
 * gasto com entregas, não o que elas renderam. A DRE junta o que o extrato
 * registrou com o que a pessoa informa ({@link LancamentoGerencialService}) e
 * chega à última linha.
 *
 * <p><b>Regime de caixa.</b> O mesmo do informe anual
 * ({@code InformeRendimentosService}): vale o dia em que o dinheiro entrou ou
 * saiu. No extrato, o {@code criadoEm} do lançamento CONCLUÍDO; no lançamento
 * gerencial, a {@code data} informada. Nada de provisão, e nada além de hoje.
 *
 * <p><b>Só leitura.</b> Este serviço não grava e não chama o
 * {@code LedgerService}: a plataforma não tem taxa nem receita própria nesta
 * fase, e a DRE é uma leitura de dois lugares, não um terceiro registro.
 *
 * <p><b>Reserva e liberação não entram na DRE do lojista.</b> São o dinheiro
 * dele mudando de bolso dentro da própria carteira — de disponível para
 * bloqueado e de volta —, não custo. O custo é o {@code pagamento_enviado}:
 * o que de fato saiu para o entregador. Contar a reserva seria contar o mesmo
 * turno duas vezes, e contar a liberação como receita faria um turno
 * cancelado dar lucro.
 */
@Service
public class DreService {

    private static final String[] MESES_CURTOS = {
        "Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"
    };

    static final String MOTIVO_SEM_TURNOS = "sem turnos pagos no período";
    static final String MOTIVO_MARGEM_NEGATIVA =
            "a margem por turno não cobre os custos variáveis";

    private final TransacaoRepository transacaoRepo;
    private final LancamentoGerencialService gerenciais;
    private final LancamentosDoExtrato extrato;

    public DreService(TransacaoRepository transacaoRepo,
                      LancamentoGerencialService gerenciais,
                      LancamentosDoExtrato extrato) {
        this.transacaoRepo = transacaoRepo;
        this.gerenciais = gerenciais;
        this.extrato = extrato;
    }

    // ── API do serviço ────────────────────────────────────────────────────

    /**
     * A DRE do período e a comparação com o período anterior de mesmo tamanho.
     * Sem datas, o mês corrente até hoje.
     */
    @Transactional(readOnly = true)
    public DreResponse dre(Long usuarioId, String papel, LocalDate inicio, LocalDate fim) {
        Periodo p = Periodo.de(inicio, fim);
        Apuracao atual = apurar(usuarioId, papel, p);

        Periodo antes = p.anterior();
        BigDecimal resultadoAnterior = apurar(usuarioId, papel, antes).resultado();

        return new DreResponse(
                papel, p.dataInicio(), p.dataFim(),
                atual.linhas(), atual.resultado(), DreResponse.situacaoDe(atual.resultado()),
                atual.indicadores(),
                new Anterior(antes.dataInicio(), antes.dataFim(), resultadoAnterior,
                        DreResponse.situacaoDe(resultadoAnterior)),
                atual.resultado().subtract(resultadoAnterior),
                atual.lancamentosManuais());
    }

    /** Doze meses do ano: receita, custos e resultado de cada um, para o gráfico. */
    @Transactional(readOnly = true)
    public List<Mes> mensal(Long usuarioId, String papel, Integer anoPedido) {
        int ano = anoPedido == null ? Year.now().getValue() : anoPedido;
        if (ano < 2000 || ano > 2100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ano fora do intervalo aceito.");
        }
        List<Mes> meses = new ArrayList<>();
        for (int m = 1; m <= 12; m++) {
            YearMonth mes = YearMonth.of(ano, m);
            Apuracao a = apurar(usuarioId, papel, Periodo.entre(mes.atDay(1), mes.atEndOfMonth()));
            meses.add(new Mes(m, MESES_CURTOS[m - 1], a.receita(),
                    emReais(a.receita().subtract(a.resultado())), a.resultado(),
                    DreResponse.situacaoDe(a.resultado())));
        }
        return meses;
    }

    // ── Apuração ──────────────────────────────────────────────────────────

    /** O que um período rendeu, já na forma da resposta. */
    private record Apuracao(List<Linha> linhas, BigDecimal receita, BigDecimal resultado,
                            Map<String, Object> indicadores, int lancamentosManuais) {}

    /** O que o usuário informou no período, somado por categoria. */
    private record Informado(Map<CategoriaLancamento, BigDecimal> porCategoria,
                             BigDecimal km, int quantidade) {

        BigDecimal de(CategoriaLancamento c) {
            return porCategoria.getOrDefault(c, BigDecimal.ZERO);
        }
    }

    private Apuracao apurar(Long usuarioId, String papel, Periodo p) {
        Informado informado = informado(usuarioId, p);
        return "lojista".equals(papel)
                ? doLojista(usuarioId, p, informado)
                : doEntregador(usuarioId, p, informado);
    }

    private Informado informado(Long usuarioId, Periodo p) {
        Map<CategoriaLancamento, BigDecimal> porCategoria = new EnumMap<>(CategoriaLancamento.class);
        BigDecimal km = BigDecimal.ZERO;
        List<Ocorrido> ocorridos = gerenciais.doPeriodo(usuarioId, p.dataInicio(), p.dataFim());
        for (Ocorrido o : ocorridos) {
            BigDecimal vezes = BigDecimal.valueOf(o.vezes());
            porCategoria.merge(o.lancamento().getCategoria(),
                    o.lancamento().getValor().multiply(vezes), BigDecimal::add);
            if (o.lancamento().getKm() != null) {
                km = km.add(o.lancamento().getKm().multiply(vezes));
            }
        }
        return new Informado(porCategoria, km, ocorridos.size());
    }

    /**
     * <pre>
     * Receita bruta           = pagamento_recebido + bonus (gorjetas)        [extrato]
     * (−) Deduções            = retencao_iss + retencao_irrf [extrato] + das_mei [manual]
     * = Receita líquida
     * (−) Custos variáveis    = combustivel + manutencao                      [manual]
     * = Margem de contribuição
     * (−) Despesas fixas      = celular, seguro, parcela/aluguel, outra       [manual]
     * = Resultado do período
     * </pre>
     */
    private Apuracao doEntregador(Long usuarioId, Periodo p, Informado inf) {
        List<Lancamento> pagos = extrato.doPeriodo(usuarioId, TipoTransacao.PAGAMENTO_RECEBIDO, p);
        BigDecimal pagamentos = LancamentosDoExtrato.soma(pagos);
        BigDecimal gorjetas = doExtrato(usuarioId, TipoTransacao.BONUS, p);
        BigDecimal retencoes = doExtrato(usuarioId, TipoTransacao.RETENCAO_ISS, p)
                .add(doExtrato(usuarioId, TipoTransacao.RETENCAO_IRRF, p));

        BigDecimal das = inf.de(CategoriaLancamento.DAS_MEI);
        BigDecimal combustivel = inf.de(CategoriaLancamento.COMBUSTIVEL);
        BigDecimal manutencao = inf.de(CategoriaLancamento.MANUTENCAO);
        BigDecimal celular = inf.de(CategoriaLancamento.CELULAR_INTERNET);
        BigDecimal seguro = inf.de(CategoriaLancamento.SEGURO);
        BigDecimal parcela = inf.de(CategoriaLancamento.PARCELA_OU_ALUGUEL_VEICULO);
        BigDecimal outra = inf.de(CategoriaLancamento.OUTRA_DESPESA_ENTREGADOR);

        BigDecimal receitaBruta = pagamentos.add(gorjetas);
        BigDecimal receitaLiquida = receitaBruta.subtract(retencoes).subtract(das);
        BigDecimal custosVariaveis = combustivel.add(manutencao);
        BigDecimal margem = receitaLiquida.subtract(custosVariaveis);
        BigDecimal despesasFixas = celular.add(seguro).add(parcela).add(outra);
        BigDecimal resultado = emReais(margem.subtract(despesasFixas));

        List<Linha> linhas = List.of(
                soma("pagamentos_recebidos", "Pagamentos de turnos", pagamentos, Linha.EXTRATO),
                soma("gorjetas_recebidas", "Gorjetas", gorjetas, Linha.EXTRATO),
                subtotal("receita_bruta", "Receita bruta", receitaBruta),
                menos("retencoes_na_fonte", "Retenções na fonte (ISS e IRRF)", retencoes, Linha.EXTRATO),
                menos(CategoriaLancamento.DAS_MEI, das),
                subtotal("receita_liquida", "Receita líquida", receitaLiquida),
                menos(CategoriaLancamento.COMBUSTIVEL, combustivel),
                menos(CategoriaLancamento.MANUTENCAO, manutencao),
                subtotal("margem_de_contribuicao", "Margem de contribuição", margem),
                menos(CategoriaLancamento.CELULAR_INTERNET, celular),
                menos(CategoriaLancamento.SEGURO, seguro),
                menos(CategoriaLancamento.PARCELA_OU_ALUGUEL_VEICULO, parcela),
                menos(CategoriaLancamento.OUTRA_DESPESA_ENTREGADOR, outra),
                new Linha("resultado", "Resultado do período", resultado,
                        Linha.RESULTADO, Linha.CALCULADO, false));

        int turnos = pagos.size();
        double horas = LancamentosDoExtrato.horasTrabalhadas(pagos);

        Map<String, Object> ind = new LinkedHashMap<>();
        ind.put("margemLiquida", percentual(resultado, receitaBruta));
        ind.put("turnosPagos", turnos);
        ind.put("horasTrabalhadas", Math.round(horas * 10.0) / 10.0);
        ind.put("lucroPorHora", horas > 0
                ? resultado.divide(BigDecimal.valueOf(horas), 2, RoundingMode.HALF_UP) : null);
        ind.put("lucroPorTurno", turnos > 0 ? por(resultado, turnos) : null);
        // Custo por km: tudo o que varia com rodar, sobre os km informados.
        // Sem km informado não há conta — e zero seria mentira.
        ind.put("kmInformados", inf.km().signum() > 0 ? inf.km().setScale(1, RoundingMode.HALF_UP) : null);
        ind.put("custoPorKm", inf.km().signum() > 0
                ? custosVariaveis.divide(inf.km(), 2, RoundingMode.HALF_UP) : null);
        pontoDeEquilibrio(ind, despesasFixas, margem, turnos);

        return new Apuracao(linhas, emReais(receitaBruta), resultado, ind, inf.quantidade());
    }

    /**
     * Quantos turnos pagam as despesas fixas: despesas fixas ÷ margem de
     * contribuição média por turno, arredondado para cima (meio turno não
     * existe).
     *
     * <p>Com margem por turno zero ou negativa não há ponto de equilíbrio:
     * cada turno a mais aumenta o buraco. Aí o número vem nulo, com o motivo —
     * um "9999 turnos" seria um número, e esconderia que a conta não fecha.
     */
    private static void pontoDeEquilibrio(Map<String, Object> ind, BigDecimal despesasFixas,
                                          BigDecimal margem, int turnos) {
        BigDecimal margemPorTurno = por(margem, turnos);
        Integer ponto = null;
        String motivo = null;
        if (turnos == 0) {
            motivo = MOTIVO_SEM_TURNOS;
        } else if (margemPorTurno.signum() <= 0) {
            motivo = MOTIVO_MARGEM_NEGATIVA;
        } else {
            ponto = despesasFixas.divide(margemPorTurno, 0, RoundingMode.CEILING).intValueExact();
        }
        ind.put("margemDeContribuicaoPorTurno", turnos > 0 ? margemPorTurno : null);
        ind.put("pontoDeEquilibrioTurnos", ponto);
        ind.put("pontoDeEquilibrioMotivo", motivo);
    }

    /**
     * <pre>
     * Receita de entregas        = taxa_de_entrega_cobrada                  [manual]
     * (−) Custo dos entregadores = pagamento_enviado + bonus_enviado        [extrato]
     * (−) Entregas fora do app   = entrega_fora_do_app                      [manual]
     * = Margem da operação
     * (−) Outras despesas        = outra_despesa_entrega                    [manual]
     * = Resultado da operação de entrega
     * </pre>
     *
     * {@code reserva} e {@code liberacao_reserva} não aparecem: ver o
     * comentário da classe.
     */
    private Apuracao doLojista(Long usuarioId, Periodo p, Informado inf) {
        List<Lancamento> pagos = extrato.doPeriodo(usuarioId, TipoTransacao.PAGAMENTO_ENVIADO, p);
        BigDecimal pagamentos = LancamentosDoExtrato.soma(pagos);
        BigDecimal gorjetas = doExtrato(usuarioId, TipoTransacao.BONUS_ENVIADO, p);

        BigDecimal receita = inf.de(CategoriaLancamento.TAXA_DE_ENTREGA_COBRADA);
        BigDecimal foraDoApp = inf.de(CategoriaLancamento.ENTREGA_FORA_DO_APP);
        BigDecimal outras = inf.de(CategoriaLancamento.OUTRA_DESPESA_ENTREGA);

        BigDecimal custoDosEntregadores = pagamentos.add(gorjetas);
        BigDecimal custoDeEntrega = custoDosEntregadores.add(foraDoApp);
        BigDecimal margem = receita.subtract(custoDeEntrega);
        BigDecimal resultado = emReais(margem.subtract(outras));

        List<Linha> linhas = List.of(
                new Linha("receita_de_entregas", "Receita de entregas (taxas cobradas)",
                        emReais(receita), Linha.LINHA, Linha.MANUAL, false),
                menos("custo_dos_entregadores", "Pagamentos e gorjetas a entregadores",
                        custoDosEntregadores, Linha.EXTRATO),
                menos(CategoriaLancamento.ENTREGA_FORA_DO_APP, foraDoApp),
                subtotal("margem_da_operacao", "Margem da operação", margem),
                menos(CategoriaLancamento.OUTRA_DESPESA_ENTREGA, outras),
                new Linha("resultado", "Resultado da operação de entrega", resultado,
                        Linha.RESULTADO, Linha.CALCULADO, false));

        // Pelo extrato, como o custo: um turno conta no período em que foi pago.
        int turnos = (int) LancamentosDoExtrato.turnosDistintos(pagos);

        Map<String, Object> ind = new LinkedHashMap<>();
        ind.put("custoSobreReceita", percentual(custoDeEntrega, receita));
        ind.put("turnosFinalizados", turnos);
        ind.put("custoMedioPorTurno", turnos > 0 ? por(custoDosEntregadores, turnos) : null);
        ind.put("resultadoPorTurno", turnos > 0 ? por(resultado, turnos) : null);
        ind.put("gorjetasDadas", emReais(gorjetas));

        return new Apuracao(linhas, emReais(receita), resultado, ind, inf.quantidade());
    }

    // ── Contas e formatação ───────────────────────────────────────────────

    /** Soma de um tipo no período — CONCLUÍDOS, como toda leitura do extrato. */
    private BigDecimal doExtrato(Long usuarioId, TipoTransacao tipo, Periodo p) {
        return transacaoRepo.somarTipoNoPeriodo(usuarioId, tipo, p.inicio(), p.fim());
    }

    private static Linha soma(String chave, String rotulo, BigDecimal valor, String origem) {
        return new Linha(chave, rotulo, emReais(valor), Linha.LINHA, origem, false);
    }

    private static Linha menos(String chave, String rotulo, BigDecimal valor, String origem) {
        return new Linha(chave, rotulo, emReais(valor), Linha.LINHA, origem, true);
    }

    /** A linha de uma categoria informada: a chave é o valor da categoria. */
    private static Linha menos(CategoriaLancamento c, BigDecimal valor) {
        return menos(c.getValor(), c.getRotulo(), valor, Linha.MANUAL);
    }

    private static Linha subtotal(String chave, String rotulo, BigDecimal valor) {
        return new Linha(chave, rotulo, emReais(valor), Linha.SUBTOTAL, Linha.CALCULADO, false);
    }

    /** {@code parte ÷ todo × 100}, com duas casas; nulo sem base para dividir. */
    private static BigDecimal percentual(BigDecimal parte, BigDecimal todo) {
        if (todo == null || todo.signum() <= 0) return null;
        return parte.multiply(BigDecimal.valueOf(100)).divide(todo, 2, RoundingMode.HALF_UP);
    }

    /** Valor por unidade; zero unidades dá zero, como a média do relatório. */
    private static BigDecimal por(BigDecimal total, int quantidade) {
        return quantidade == 0
                ? BigDecimal.ZERO.setScale(2)
                : total.divide(BigDecimal.valueOf(quantidade), 2, RoundingMode.HALF_UP);
    }

    private static BigDecimal emReais(BigDecimal v) {
        return (v == null ? BigDecimal.ZERO : v).setScale(2, RoundingMode.HALF_UP);
    }
}
