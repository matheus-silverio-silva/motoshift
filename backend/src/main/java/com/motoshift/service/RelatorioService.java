package com.motoshift.service;

import com.motoshift.dto.RelatorioFinanceiroResponse;
import com.motoshift.dto.RelatorioFinanceiroResponse.ItemDeQuebra;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoCobranca;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CobrancaRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.Duration;
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
 */
@Service
public class RelatorioService {

    private static final Logger log = LoggerFactory.getLogger(RelatorioService.class);

    private static final String[] MESES = {
        "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    };

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TransacaoRepository transacaoRepo;
    private final CobrancaRepository cobrancaRepo;
    private final AnthropicService anthropicService;

    public RelatorioService(TurnoRepository turnoRepo,
                            UsuarioRepository usuarioRepo,
                            TransacaoRepository transacaoRepo,
                            CobrancaRepository cobrancaRepo,
                            AnthropicService anthropicService) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.transacaoRepo = transacaoRepo;
        this.cobrancaRepo = cobrancaRepo;
        this.anthropicService = anthropicService;
    }

    // -- Entregador ----------------------------------------------------------

    @Transactional(readOnly = true)
    public RelatorioFinanceiroResponse doMotoboy(Long motoboyId, LocalDate inicio, LocalDate fim) {
        Usuario motoboy = exigirPerfil(motoboyId, "motoboy");
        Periodo p = Periodo.de(inicio, fim);

        List<Lancamento> ganhos = lancamentos(motoboyId, TipoTransacao.PAGAMENTO_RECEBIDO, p);
        BigDecimal total = soma(ganhos);

        BigDecimal saques = cobrancaRepo.somar(motoboyId, TipoCobranca.SAQUE,
                StatusCobranca.CONCLUIDO, p.inicio(), p.fim());

        // Horas efetivamente trabalhadas: a duração dos turnos que geraram
        // pagamento. Turno sem data (lançamento órfão) fica de fora da conta em
        // vez de entrar como zero hora, o que inflaria o valor por hora.
        double horas = ganhos.stream()
                .filter(l -> l.turno() != null
                        && l.turno().getDataInicio() != null && l.turno().getDataFim() != null)
                .mapToDouble(l -> Duration.between(
                        l.turno().getDataInicio(), l.turno().getDataFim()).toMinutes() / 60.0)
                .sum();

        Map<String, Object> numeros = new LinkedHashMap<>();
        numeros.put("turnosPagos", ganhos.size());
        numeros.put("ganhosTotais", emReais(total));
        numeros.put("ticketMedioPorTurno", media(total, ganhos.size()));
        numeros.put("horasTrabalhadas", arredondar(horas));
        numeros.put("valorPorHora", horas > 0
                ? emReais(total.divide(BigDecimal.valueOf(horas), 2, RoundingMode.HALF_UP))
                : BigDecimal.ZERO.setScale(2));
        numeros.put("saquesNoPeriodo", emReais(saques));
        numeros.put("score", motoboy.getScore() == null ? 5.0 : motoboy.getScore());
        numeros.put("mediaAvaliacao", motoboy.getMediaAvaliacao());

        Map<String, List<ItemDeQuebra>> series = new LinkedHashMap<>();
        series.put("porLojista", porContraparte(ganhos));
        series.put("porDiaDaSemana", porDiaDaSemana(ganhos));
        series.put("porFaixaDeHorario", porFaixaDeHorario(ganhos));

        String analise = analisar(
                AnthropicService.SYSTEM_PROMPT_RELATORIO_MOTOBOY,
                contextoDoMotoboy(motoboy, p, numeros, series));

        return RelatorioFinanceiroResponse.de("motoboy", p.rotulo(), p.dataInicio(), p.dataFim(),
                numeros, series, analise);
    }

    // -- Lojista -------------------------------------------------------------

    @Transactional(readOnly = true)
    public RelatorioFinanceiroResponse doLojista(Long lojistaId, LocalDate inicio, LocalDate fim) {
        Usuario lojista = exigirPerfil(lojistaId, "lojista");
        Periodo p = Periodo.de(inicio, fim);

        List<Lancamento> gastos = lancamentos(lojistaId, TipoTransacao.PAGAMENTO_ENVIADO, p);
        BigDecimal total = soma(gastos);

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

        double horas = gastos.stream()
                .filter(l -> l.turno() != null
                        && l.turno().getDataInicio() != null && l.turno().getDataFim() != null)
                .mapToDouble(l -> Duration.between(
                        l.turno().getDataInicio(), l.turno().getDataFim()).toMinutes() / 60.0)
                .sum();

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
        numeros.put("mediaAvaliacao", lojista.getMediaAvaliacao());

        Map<String, List<ItemDeQuebra>> series = new LinkedHashMap<>();
        series.put("porEntregador", porContraparte(gastos));
        series.put("porDiaDaSemana", porDiaDaSemana(gastos));
        series.put("porFaixaDeHorario", porFaixaDeHorario(gastos));

        String analise = analisar(
                AnthropicService.SYSTEM_PROMPT_RELATORIO_LOJISTA,
                contextoDoLojista(lojista, p, numeros, series));

        return RelatorioFinanceiroResponse.de("lojista", p.rotulo(), p.dataInicio(), p.dataFim(),
                numeros, series, analise);
    }

    // -- Apuração ------------------------------------------------------------

    /** Um lançamento e o turno de onde ele veio — o turno pode faltar. */
    private record Lancamento(Transacao transacao, Turno turno) {}

    private List<Lancamento> lancamentos(Long usuarioId, TipoTransacao tipo, Periodo p) {
        List<Lancamento> lista = new ArrayList<>();
        for (Object[] linha : transacaoRepo.lancamentosComTurno(
                usuarioId, tipo, p.inicio(), p.fim())) {
            lista.add(new Lancamento((Transacao) linha[0], (Turno) linha[1]));
        }
        return lista;
    }

    private static BigDecimal soma(List<Lancamento> lancamentos) {
        return lancamentos.stream()
                .map(l -> l.transacao().getValor())
                .filter(java.util.Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

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
                                     Map<String, List<ItemDeQuebra>> series) {
        return String.format(
                "Dados financeiros do entregador no período %s:%n"
                + "- Nome: %s%n"
                + "- Turnos pagos: %s%n"
                + "- Ganhos totais: R$ %s%n"
                + "- Ticket médio por turno: R$ %s%n"
                + "- Horas trabalhadas: %s%n"
                + "- Valor por hora: R$ %s%n"
                + "- Saques no período: R$ %s%n"
                + "- Score na plataforma: %s/5%n"
                + "- Ganhos por lojista: %s%n"
                + "- Ganhos por dia da semana: %s%n"
                + "- Ganhos por faixa de horário: %s%n%n"
                + "Gere um relatório financeiro personalizado em linguagem simples e "
                + "motivadora para este entregador. Inclua:%n"
                + "1. Um resumo do período em 2-3 frases%n"
                + "2. Seu ponto mais forte%n"
                + "3. Uma oportunidade clara de ganhar mais%n"
                + "4. Uma dica prática baseada nos dados%n"
                + "Seja direto, use linguagem informal e positiva. Máximo 150 palavras.",
                p.rotulo(), motoboy.getNome(),
                numeros.get("turnosPagos"), numeros.get("ganhosTotais"),
                numeros.get("ticketMedioPorTurno"), numeros.get("horasTrabalhadas"),
                numeros.get("valorPorHora"), numeros.get("saquesNoPeriodo"),
                numeros.get("score"),
                resumir(series.get("porLojista")),
                resumir(series.get("porDiaDaSemana")),
                resumir(series.get("porFaixaDeHorario")));
    }

    private String contextoDoLojista(Usuario lojista, Periodo p,
                                     Map<String, Object> numeros,
                                     Map<String, List<ItemDeQuebra>> series) {
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
                + "- Gasto por faixa de horário: %s%n%n"
                + "Gere um relatório operacional personalizado para este lojista. Inclua:%n"
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
                resumir(series.get("porFaixaDeHorario")));
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

    // -- Período e formatação ------------------------------------------------

    /**
     * O intervalo apurado.
     *
     * <p>Sem datas, é o mês corrente — que era o único recorte possível antes e
     * continua sendo o padrão, para o app atual não mudar de comportamento.
     */
    private record Periodo(LocalDate dataInicio, LocalDate dataFim, String rotulo) {

        static Periodo de(LocalDate inicio, LocalDate fim) {
            if (inicio == null && fim == null) {
                LocalDate hoje = LocalDate.now();
                LocalDate primeiro = hoje.withDayOfMonth(1);
                return new Periodo(primeiro, hoje,
                        MESES[hoje.getMonthValue() - 1] + " " + hoje.getYear());
            }
            LocalDate de = inicio != null ? inicio : LocalDate.now().withDayOfMonth(1);
            LocalDate ate = fim != null ? fim : LocalDate.now();
            if (ate.isBefore(de)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "A data final não pode ser anterior à inicial.");
            }
            return new Periodo(de, ate, String.format("%02d/%02d a %02d/%02d/%d",
                    de.getDayOfMonth(), de.getMonthValue(),
                    ate.getDayOfMonth(), ate.getMonthValue(), ate.getYear()));
        }

        LocalDateTime inicio() {
            return dataInicio.atStartOfDay();
        }

        /** Exclusivo: o dia final entra inteiro. */
        LocalDateTime fim() {
            return dataFim.plusDays(1).atStartOfDay();
        }
    }

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
