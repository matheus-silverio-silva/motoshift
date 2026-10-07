package com.motoshift.service;

import com.motoshift.dto.DreResponse;
import com.motoshift.dto.RelatorioFinanceiroResponse;
import com.motoshift.dto.RelatorioFinanceiroResponse.ItemDeQuebra;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoCobranca;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CobrancaRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.LancamentosDoExtrato.Lancamento;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * Relatório financeiro do entregador e do lojista.
 *
 * <p><b>A apuração saiu de {@code Turno.valorEstimado} e passou para o
 * EXTRATO.</b> Não é troca de fonte por gosto: {@code valorEstimado} é o que o
 * turno <i>prometia</i> pagar por entregador, e o relatório precisa do que foi
 * de fato pago. Num turno de três vagas com dois inscritos, somar
 * {@code valorEstimado} dá R$ 120 quando o lojista gastou R$ 240; num turno
 * cancelado, dá um gasto que nunca existiu. O extrato não tem esse problema
 * porque cada linha dele é um movimento que aconteceu.
 *
 * <p><b>A IA virou um campo, e não a resposta.</b> Antes, uma falha na chamada
 * ao Claude devolvia 503 e o usuário ficava sem relatório nenhum — embora todos
 * os números já estivessem calculados. Agora eles são a resposta, e a análise
 * vem {@code null} quando a IA não responde.
 *
 * <p><b>O resultado vem da DRE, sem recalcular (RF13).</b> Faturamento não é
 * lucro. {@code resultadoDoPeriodo}, {@code situacao} e os indicadores que os
 * acompanham são lidos do {@link DreService} para o mesmo período — a tela de
 * resultado e o relatório não podem dar duas respostas para "tive lucro?". E
 * a IA passa a comentar o resultado, avisando quando ele só conhece o que
 * passou pela plataforma.
 */
@Service
public class RelatorioService {

    private static final Logger log = LoggerFactory.getLogger(RelatorioService.class);

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TransacaoRepository transacaoRepo;
    private final CobrancaRepository cobrancaRepo;
    private final AnthropicService anthropicService;
    private final Reputacao reputacao;
    private final LancamentosDoExtrato extrato;
    private final DreService dre;

    public RelatorioService(TurnoRepository turnoRepo,
                            UsuarioRepository usuarioRepo,
                            TransacaoRepository transacaoRepo,
                            CobrancaRepository cobrancaRepo,
                            AnthropicService anthropicService,
                            Reputacao reputacao,
                            LancamentosDoExtrato extrato,
                            DreService dre) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.transacaoRepo = transacaoRepo;
        this.cobrancaRepo = cobrancaRepo;
        this.anthropicService = anthropicService;
        this.reputacao = reputacao;
        this.extrato = extrato;
        this.dre = dre;
    }

    // -- Entregador ----------------------------------------------------------

    @Transactional(readOnly = true)
    public RelatorioFinanceiroResponse doMotoboy(Long motoboyId, LocalDate inicio, LocalDate fim) {
        Usuario motoboy = exigirPerfil(motoboyId, "motoboy");
        Periodo p = Periodo.de(inicio, fim);

        List<Lancamento> ganhos = extrato.doPeriodo(motoboyId, TipoTransacao.PAGAMENTO_RECEBIDO, p);
        BigDecimal total = LancamentosDoExtrato.soma(ganhos);

        BigDecimal saques = cobrancaRepo.somar(motoboyId, TipoCobranca.SAQUE,
                StatusCobranca.CONCLUIDO, p.inicio(), p.fim());

        // A regra das horas mora num lugar só: é o mesmo divisor do "lucro por
        // hora" da DRE.
        double horas = LancamentosDoExtrato.horasTrabalhadas(ganhos);

        Map<String, Object> numeros = new LinkedHashMap<>();
        numeros.put("turnosPagos", ganhos.size());
        numeros.put("ganhosTotais", emReais(total));
        numeros.put("ticketMedioPorTurno", media(total, ganhos.size()));
        numeros.put("horasTrabalhadas", arredondar(horas));
        numeros.put("valorPorHora", horas > 0
                ? emReais(total.divide(BigDecimal.valueOf(horas), 2, RoundingMode.HALF_UP))
                : BigDecimal.ZERO.setScale(2));
        numeros.put("saquesNoPeriodo", emReais(saques));
        // Gorjetas (bonus): além dos ganhos dos turnos, que ficam como estão
        // — o valor por hora é do turno, não da gorjeta.
        numeros.put("gorjetasRecebidas", emReais(transacaoRepo.somarTipoNoPeriodo(
                motoboyId, TipoTransacao.BONUS, p.inicio(), p.fim())));
        // Sem histórico o score não é reputação, é o ponto de partida da conta:
        // o relatório diz isso em vez de apresentar um 5,0 que nada produziu.
        Double score = reputacao.scoreVisivel(motoboy);
        numeros.put("score", score);
        numeros.put("mediaAvaliacao", motoboy.getMediaAvaliacao());

        // O resultado (RF13): lido da DRE do mesmo período, não refeito aqui.
        DreResponse resultado = dre.dre(motoboyId, "motoboy", p.dataInicio(), p.dataFim());
        numeros.put("resultadoDoPeriodo", resultado.resultado());
        numeros.put("situacao", resultado.situacao());
        numeros.put("margemLiquida", resultado.indicadores().get("margemLiquida"));
        numeros.put("pontoDeEquilibrioTurnos",
                resultado.indicadores().get("pontoDeEquilibrioTurnos"));

        Map<String, List<ItemDeQuebra>> series = new LinkedHashMap<>();
        series.put("porLojista", porContraparte(ganhos));
        series.put("porDiaDaSemana", porDiaDaSemana(ganhos));
        series.put("porFaixaDeHorario", porFaixaDeHorario(ganhos));

        String analise = analisar(
                AnthropicService.SYSTEM_PROMPT_RELATORIO_MOTOBOY,
                contextoDoMotoboy(motoboy, p, numeros, series, resultado));

        return RelatorioFinanceiroResponse.de("motoboy", p.rotulo(), p.dataInicio(), p.dataFim(),
                numeros, series, analise);
    }

    // -- Lojista -------------------------------------------------------------

    @Transactional(readOnly = true)
    public RelatorioFinanceiroResponse doLojista(Long lojistaId, LocalDate inicio, LocalDate fim) {
        Usuario lojista = exigirPerfil(lojistaId, "lojista");
        Periodo p = Periodo.de(inicio, fim);

        List<Lancamento> gastos = extrato.doPeriodo(lojistaId, TipoTransacao.PAGAMENTO_ENVIADO, p);
        BigDecimal total = LancamentosDoExtrato.soma(gastos);

        BigDecimal recargas = cobrancaRepo.somar(lojistaId, TipoCobranca.RECARGA,
                StatusCobranca.CONCLUIDO, p.inicio(), p.fim());

        BigDecimal devolvido = transacaoRepo.somarTipoNoPeriodo(
                lojistaId, TipoTransacao.LIBERACAO_RESERVA, p.inicio(), p.fim());

        BigDecimal reservasAbertas = transacaoRepo.reservasAbertas(lojistaId).stream()
                .map(r -> r.valor())
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        // Turnos que não chegaram a acontecer, contados pelo próprio turno: o
        // extrato mostra o dinheiro voltando, mas não diz se foi cancelamento
        // ou vencimento, e a diferença importa para quem publica.
        List<Turno> doPeriodo = turnoRepo.findByLojistId(lojistaId).stream()
                .filter(t -> t.getCriadoEm() != null
                        && !t.getCriadoEm().isBefore(p.inicio())
                        && t.getCriadoEm().isBefore(p.fim()))
                .toList();
        long cancelados = doPeriodo.stream()
                .filter(t -> t.getStatus() == StatusTurno.CANCELADO).count();
        long expirados = doPeriodo.stream()
                .filter(t -> t.getStatus() == StatusTurno.EXPIRADO).count();

        double horas = LancamentosDoExtrato.horasTrabalhadas(gastos);

        Map<String, Object> numeros = new LinkedHashMap<>();
        numeros.put("turnosPublicados", doPeriodo.size());
        numeros.put("pagamentosFeitos", gastos.size());
        numeros.put("gastoTotal", emReais(total));
        numeros.put("custoMedioPorTurno", media(total, gastos.size()));
        numeros.put("custoMedioPorHora", horas > 0
                ? emReais(total.divide(BigDecimal.valueOf(horas), 2, RoundingMode.HALF_UP))
                : BigDecimal.ZERO.setScale(2));
        numeros.put("recargasNoPeriodo", emReais(recargas));
        numeros.put("reservasAbertas", emReais(reservasAbertas));
        numeros.put("turnosCancelados", cancelados);
        numeros.put("turnosExpirados", expirados);
        numeros.put("valorDevolvido", emReais(devolvido));
        numeros.put("gorjetasDadas", emReais(transacaoRepo.somarTipoNoPeriodo(
                lojistaId, TipoTransacao.BONUS_ENVIADO, p.inicio(), p.fim())));
        numeros.put("mediaAvaliacao", lojista.getMediaAvaliacao());

        // O resultado da operação de entrega (RF13), lido da DRE do período.
        DreResponse resultado = dre.dre(lojistaId, "lojista", p.dataInicio(), p.dataFim());
        numeros.put("resultadoDoPeriodo", resultado.resultado());
        numeros.put("situacao", resultado.situacao());
        numeros.put("custoSobreReceita", resultado.indicadores().get("custoSobreReceita"));

        Map<String, List<ItemDeQuebra>> series = new LinkedHashMap<>();
        series.put("porEntregador", porContraparte(gastos));
        series.put("porDiaDaSemana", porDiaDaSemana(gastos));
        series.put("porFaixaDeHorario", porFaixaDeHorario(gastos));

        String analise = analisar(
                AnthropicService.SYSTEM_PROMPT_RELATORIO_LOJISTA,
                contextoDoLojista(lojista, p, numeros, series, resultado));

        return RelatorioFinanceiroResponse.de("lojista", p.rotulo(), p.dataInicio(), p.dataFim(),
                numeros, series, analise);
    }

    // -- Apuração ------------------------------------------------------------

    /**
     * Quebra por quem estava do outro lado — lojista ou entregador.
     *
     * <p>Os nomes vêm numa consulta só. A versão anterior deste serviço fazia
     * um {@code findById} por turno dentro do laço, e isso continua sendo o
     * tipo de coisa que passa despercebida até o relatório de alguém com
     * duzentos turnos.
     */
    private List<ItemDeQuebra> porContraparte(List<Lancamento> lancamentos) {
        List<Long> ids = lancamentos.stream()
                .map(l -> l.transacao().getContraparteId())
                .filter(java.util.Objects::nonNull)
                .distinct()
                .toList();
        Map<Long, String> nomes = new LinkedHashMap<>();
        if (!ids.isEmpty()) {
            usuarioRepo.findAllById(ids).forEach(u -> nomes.put(u.getId(), u.getNome()));
        }

        Map<String, BigDecimal[]> acumulado = new LinkedHashMap<>();
        for (Lancamento l : lancamentos) {
            Long id = l.transacao().getContraparteId();
            String rotulo = id == null ? "Sem contraparte" : nomes.getOrDefault(id, "Conta " + id);
            somar(acumulado, rotulo, l.transacao().getValor());
        }
        return emLista(acumulado, true);
    }

    private static List<ItemDeQuebra> porDiaDaSemana(List<Lancamento> lancamentos) {
        // TreeMap pela ordem do enum: segunda a domingo, e não alfabética.
        Map<DayOfWeek, BigDecimal[]> acumulado = new TreeMap<>();
        for (Lancamento l : lancamentos) {
            LocalDateTime quando = quandoAconteceu(l);
            if (quando == null) continue;
            acumulado.computeIfAbsent(quando.getDayOfWeek(),
                    k -> new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
            BigDecimal[] acc = acumulado.get(quando.getDayOfWeek());
            acc[0] = acc[0].add(valorOuZero(l));
            acc[1] = acc[1].add(BigDecimal.ONE);
        }

        List<ItemDeQuebra> lista = new ArrayList<>();
        acumulado.forEach((dia, acc) ->
                lista.add(new ItemDeQuebra(nomeDoDia(dia), emReais(acc[0]), acc[1].longValue())));
        return lista;
    }

    /**
     * Faixas de quatro horas, e não hora a hora.
     *
     * <p>Vinte e quatro baldes num relatório mensal deixam quase todos vazios e
     * escondem o padrão que a pergunta quer ver — em que parte do dia o dinheiro
     * acontece.
     */
    private static List<ItemDeQuebra> porFaixaDeHorario(List<Lancamento> lancamentos) {
        Map<Integer, BigDecimal[]> acumulado = new TreeMap<>();
        for (Lancamento l : lancamentos) {
            LocalDateTime quando = quandoAconteceu(l);
            if (quando == null) continue;
            int faixa = quando.getHour() / 4;
            acumulado.computeIfAbsent(faixa, k -> new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
            BigDecimal[] acc = acumulado.get(faixa);
            acc[0] = acc[0].add(valorOuZero(l));
            acc[1] = acc[1].add(BigDecimal.ONE);
        }

        List<ItemDeQuebra> lista = new ArrayList<>();
        acumulado.forEach((faixa, acc) -> lista.add(new ItemDeQuebra(
                String.format("%02dh - %02dh", faixa * 4, faixa * 4 + 4),
                emReais(acc[0]), acc[1].longValue())));
        return lista;
    }

    /**
     * Quando o trabalho aconteceu, e não quando o dinheiro foi lançado.
     *
     * <p>Para "melhor dia da semana" e "faixa de horário", o que interessa é o
     * início do turno: um turno de sábado à noite finalizado na segunda de manhã
     * é ganho de sábado à noite. Sem turno, resta a data do lançamento.
     */
    private static LocalDateTime quandoAconteceu(Lancamento l) {
        if (l.turno() != null && l.turno().getDataInicio() != null) {
            return l.turno().getDataInicio();
        }
        return l.transacao().getCriadoEm();
    }

    private static void somar(Map<String, BigDecimal[]> acumulado, String rotulo, BigDecimal valor) {
        acumulado.computeIfAbsent(rotulo, k -> new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
        BigDecimal[] acc = acumulado.get(rotulo);
        acc[0] = acc[0].add(valor == null ? BigDecimal.ZERO : valor);
        acc[1] = acc[1].add(BigDecimal.ONE);
    }

    private static List<ItemDeQuebra> emLista(Map<String, BigDecimal[]> acumulado, boolean maiorPrimeiro) {
        List<ItemDeQuebra> lista = new ArrayList<>();
        acumulado.forEach((rotulo, acc) ->
                lista.add(new ItemDeQuebra(rotulo, emReais(acc[0]), acc[1].longValue())));
        if (maiorPrimeiro) {
            lista.sort(Comparator.comparing(ItemDeQuebra::total).reversed());
        }
        return lista;
    }

    private static BigDecimal valorOuZero(Lancamento l) {
        return l.transacao().getValor() == null ? BigDecimal.ZERO : l.transacao().getValor();
    }

    // -- IA ------------------------------------------------------------------

    /**
     * Pede a leitura à IA — e devolve {@code null} se ela não vier.
     *
     * <p>Esta é a mudança de contrato mais visível do serviço. A versão anterior
     * transformava qualquer falha aqui em 503, e o usuário ficava sem relatório
     * apesar de todos os números estarem prontos. Uma dependência externa
     * opcional não pode derrubar a resposta inteira.
     */
    private String analisar(String systemPrompt, String contexto) {
        try {
            return anthropicService.chamarClaude(systemPrompt, contexto);
        } catch (Exception e) {
            log.warn("[relatorio] a IA nao respondeu; devolvendo os numeros sem analise: {}",
                    e.getMessage());
            return null;
        }
    }

    private String contextoDoMotoboy(Usuario motoboy, Periodo p,
                                     Map<String, Object> numeros,
                                     Map<String, List<ItemDeQuebra>> series,
                                     DreResponse resultado) {
        Object margem = numeros.get("margemLiquida");
        Object equilibrio = numeros.get("pontoDeEquilibrioTurnos");
        return String.format(
                "Dados financeiros do entregador no período %s:%n"
                + "- Nome: %s%n"
                + "- Turnos pagos: %s%n"
                + "- Ganhos totais: R$ %s%n"
                + "- Ticket médio por turno: R$ %s%n"
                + "- Horas trabalhadas: %s%n"
                + "- Valor por hora: R$ %s%n"
                + "- Saques no período: R$ %s%n"
                + "- Score na plataforma: %s%n"
                + "- Ganhos por lojista: %s%n"
                + "- Ganhos por dia da semana: %s%n"
                + "- Ganhos por faixa de horário: %s%n"
                + "- Resultado do período (receita menos deduções, custos e despesas): "
                + "R$ %s — %s%n"
                + "- Margem líquida: %s%n"
                + "- Ponto de equilíbrio: %s%n"
                + "- %s%n%n"
                + "Gere um relatório financeiro personalizado em linguagem simples e "
                + "motivadora para este entregador. Comente o RESULTADO do período "
                + "(lucro ou prejuízo), e não só o faturamento. Inclua:%n"
                + "1. Um resumo do período em 2-3 frases%n"
                + "2. Seu ponto mais forte%n"
                + "3. Uma oportunidade clara de ganhar mais%n"
                + "4. Uma dica prática baseada nos dados%n"
                + "Seja direto, use linguagem informal e positiva. Máximo 150 palavras.",
                p.rotulo(), motoboy.getNome(),
                numeros.get("turnosPagos"), numeros.get("ganhosTotais"),
                numeros.get("ticketMedioPorTurno"), numeros.get("horasTrabalhadas"),
                numeros.get("valorPorHora"), numeros.get("saquesNoPeriodo"),
                numeros.get("score") == null ? "sem histórico ainda (novo na plataforma)"
                        : numeros.get("score") + "/5",
                resumir(series.get("porLojista")),
                resumir(series.get("porDiaDaSemana")),
                resumir(series.get("porFaixaDeHorario")),
                resultado.resultado(), situacaoPorExtenso(resultado.situacao()),
                margem == null ? "sem receita no período" : margem + "% da receita bruta",
                equilibrio == null ? "não calculável neste período"
                        : equilibrio + " turno(s) para cobrir as despesas fixas",
                avisoSobreCustos(resultado));
    }

    private String contextoDoLojista(Usuario lojista, Periodo p,
                                     Map<String, Object> numeros,
                                     Map<String, List<ItemDeQuebra>> series,
                                     DreResponse resultado) {
        Object custoSobreReceita = numeros.get("custoSobreReceita");
        return String.format(
                "Dados operacionais do lojista no período %s:%n"
                + "- Estabelecimento: %s%n"
                + "- Turnos publicados: %s%n"
                + "- Pagamentos feitos: %s%n"
                + "- Gasto total com frete: R$ %s%n"
                + "- Custo médio por turno: R$ %s%n"
                + "- Custo médio por hora: R$ %s%n"
                + "- Recargas no período: R$ %s%n"
                + "- Reservas ainda abertas: R$ %s%n"
                + "- Turnos cancelados: %s / expirados: %s%n"
                + "- Valor devolvido por cancelamento ou vencimento: R$ %s%n"
                + "- Gasto por entregador: %s%n"
                + "- Gasto por dia da semana: %s%n"
                + "- Gasto por faixa de horário: %s%n"
                + "- Resultado da operação de entrega (taxas cobradas menos o custo das "
                + "entregas): R$ %s — %s%n"
                + "- Custo de entrega sobre a receita de entrega: %s%n"
                + "- %s%n%n"
                + "Gere um relatório operacional personalizado para este lojista. Comente o "
                + "RESULTADO da operação de entrega (lucro ou prejuízo), e não só o gasto. "
                + "Inclua:%n"
                + "1. Resumo do período em 2-3 frases%n"
                + "2. O que funcionou bem na operação de delivery%n"
                + "3. Principal problema operacional identificado nos dados%n"
                + "4. Uma recomendação prática para reduzir custos ou melhorar a cobertura%n"
                + "Linguagem profissional mas acessível. Máximo 150 palavras.",
                p.rotulo(), lojista.getNome(),
                numeros.get("turnosPublicados"), numeros.get("pagamentosFeitos"),
                numeros.get("gastoTotal"), numeros.get("custoMedioPorTurno"),
                numeros.get("custoMedioPorHora"), numeros.get("recargasNoPeriodo"),
                numeros.get("reservasAbertas"), numeros.get("turnosCancelados"),
                numeros.get("turnosExpirados"), numeros.get("valorDevolvido"),
                resumir(series.get("porEntregador")),
                resumir(series.get("porDiaDaSemana")),
                resumir(series.get("porFaixaDeHorario")),
                resultado.resultado(), situacaoPorExtenso(resultado.situacao()),
                custoSobreReceita == null ? "sem receita de entrega informada"
                        : custoSobreReceita + "%",
                avisoSobreCustos(resultado));
    }

    private static String situacaoPorExtenso(String situacao) {
        return switch (situacao) {
            case DreResponse.LUCRO -> "lucro";
            case DreResponse.PREJUIZO -> "prejuízo";
            default -> "equilíbrio";
        };
    }

    /**
     * O que a IA precisa saber antes de chamar um número de "lucro": se o
     * usuário não informou nada à mão, o resultado só conhece o extrato — para
     * o entregador, é receita sem custo nenhum; para o lojista, custo sem
     * receita nenhuma. Sem este aviso ela comemoraria um lucro que ninguém
     * mediu, ou lamentaria um prejuízo que talvez não exista.
     */
    private static String avisoSobreCustos(DreResponse resultado) {
        return resultado.lancamentosManuais() == 0
                ? "ATENÇÃO: nenhum custo ou receita foi informado pelo usuário neste período. "
                        + "Diga com clareza que o resultado ignora custos não informados e "
                        + "sugira informá-los na tela de resultado."
                : "Custos e receitas informados pelo usuário no período: "
                        + resultado.lancamentosManuais() + " lançamento(s).";
    }

    /** As cinco primeiras linhas de uma quebra, em texto — o resto é ruído no prompt. */
    private static String resumir(List<ItemDeQuebra> itens) {
        if (itens == null || itens.isEmpty()) return "sem dados";
        StringBuilder sb = new StringBuilder();
        itens.stream().limit(5).forEach(i -> sb
                .append(sb.length() == 0 ? "" : "; ")
                .append(i.rotulo()).append(": R$ ").append(i.total()));
        return sb.toString();
    }

    // -- Formatação ----------------------------------------------------------

    private Usuario exigirPerfil(Long id, String tipo) {
        Usuario u = usuarioRepo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        ("motoboy".equals(tipo) ? "Motoboy" : "Lojista") + " não encontrado."));
        if (!tipo.equals(u.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Endpoint exclusivo para perfil " + tipo + ".");
        }
        return u;
    }

    private static BigDecimal media(BigDecimal total, int quantidade) {
        return quantidade == 0
                ? BigDecimal.ZERO.setScale(2)
                : total.divide(BigDecimal.valueOf(quantidade), 2, RoundingMode.HALF_UP);
    }

    private static BigDecimal emReais(BigDecimal v) {
        return (v == null ? BigDecimal.ZERO : v).setScale(2, RoundingMode.HALF_UP);
    }

    private static double arredondar(double v) {
        return Math.round(v * 10.0) / 10.0;
    }

    private static String nomeDoDia(DayOfWeek dia) {
        return switch (dia) {
            case MONDAY -> "Segunda";
            case TUESDAY -> "Terça";
            case WEDNESDAY -> "Quarta";
            case THURSDAY -> "Quinta";
            case FRIDAY -> "Sexta";
            case SATURDAY -> "Sábado";
            case SUNDAY -> "Domingo";
        };
    }
}
