package com.motoshift.service;

import com.motoshift.dto.ExtratoFiltro;
import com.motoshift.dto.FluxoPontoResponse;
import com.motoshift.dto.ReservaAbertaResponse;
import com.motoshift.dto.ResumoFinanceiroResponse;
import com.motoshift.dto.TotalPorTipoResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.PontoDeFluxo;
import com.motoshift.service.fiscal.IndiceDeDocumentos;
import com.motoshift.util.Csv;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TransacaoSpecs;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.WeekFields;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * O extrato: consulta filtrada, resumo do período, série de fluxo e exportação.
 *
 * <p><b>O filtro mora aqui, e não no app.</b> A carteira devolvia o extrato
 * inteiro numa lista só e o cliente escondia as linhas que não interessavam.
 * Isso funciona com vinte lançamentos; com dois anos de uso é uma resposta
 * grande para mostrar dez linhas, e a paginação fica impossível — não dá para
 * paginar no servidor o que o cliente vai filtrar depois.
 *
 * <p><b>Nenhuma soma é feita percorrendo lançamentos em Java.</b> Resumo, fluxo
 * e quebra por tipo saem agregados do banco. A única dobra feita aqui é a de
 * dias em semanas e meses, e ela é limitada pelo tamanho do período consultado,
 * não pelo número de lançamentos — ver {@link PontoDeFluxo}.
 */
@Service
public class ExtratoService {

    /** Teto de itens por página. "Página" sem limite é a lista inteira com outro nome. */
    private static final int TAMANHO_MAXIMO = 100;

    /** Período padrão do resumo e do fluxo quando a chamada não informa datas. */
    private static final int DIAS_PADRAO = 30;

    private static final DateTimeFormatter DIA = DateTimeFormatter.ofPattern("dd/MM");
    private static final DateTimeFormatter DIA_HORA = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm");

    private final TransacaoRepository transacaoRepo;
    private final CarteiraService carteiras;
    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final IndiceDeDocumentos indice;

    public ExtratoService(TransacaoRepository transacaoRepo,
                          CarteiraService carteiras,
                          TurnoRepository turnoRepo,
                          TurnoInscricaoRepository inscricaoRepo,
                          IndiceDeDocumentos indice) {
        this.transacaoRepo = transacaoRepo;
        this.carteiras = carteiras;
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.indice = indice;
    }

    // -- Extrato -------------------------------------------------------------

    /** Lançamentos filtrados, do mais recente para o mais antigo. */
    @Transactional(readOnly = true)
    public Page<TransacaoResponse> extrato(Long usuarioId, ExtratoFiltro filtro, Pageable pagina) {
        Page<Transacao> lancamentos =
                transacaoRepo.findAll(TransacaoSpecs.de(usuarioId, filtro), pagina(pagina));
        // O documento de cada linha, em duas consultas para a página inteira.
        var documentos = indice.indexar(lancamentos.getContent());
        return lancamentos.map(t -> TransacaoResponse.from(t).comDocumento(documentos.get(t.getId())));
    }

    /**
     * O mesmo extrato em CSV.
     *
     * <p>Sem paginação de propósito: exportar meia página não exporta nada. O
     * teto é o do próprio filtro — quem exporta escolhe um período.
     */
    @Transactional(readOnly = true)
    public String exportarCsv(Long usuarioId, ExtratoFiltro filtro) {
        List<Transacao> lancamentos = transacaoRepo.findAll(
                TransacaoSpecs.de(usuarioId, filtro),
                Sort.by(Sort.Direction.DESC, "criadoEm"));

        StringBuilder csv = new StringBuilder();
        // Ponto e vírgula, não vírgula: o Excel em português trata a vírgula
        // como separador decimal, e um arquivo com "120,50" numa coluna
        // separada por vírgula abre todo torto.
        csv.append("data;tipo;natureza;descricao;valor;status;turno;contraparte;")
           .append("saldo_disponivel_apos;saldo_bloqueado_apos;operacao\n");

        for (Transacao t : lancamentos) {
            csv.append(t.getCriadoEm() == null ? "" : DIA_HORA.format(t.getCriadoEm())).append(';')
               .append(t.getTipo() == null ? "" : t.getTipo().getValor()).append(';')
               .append(t.getNatureza() == null ? "" : t.getNatureza().getValor()).append(';')
               .append(csvSeguro(t.getDescricao())).append(';')
               .append(decimal(t.getValor())).append(';')
               .append(t.getStatus() == null ? "" : t.getStatus().getValor()).append(';')
               .append(t.getTurnoId() == null ? "" : t.getTurnoId()).append(';')
               .append(t.getContraparteId() == null ? "" : t.getContraparteId()).append(';')
               .append(decimal(t.getSaldoDisponivelApos())).append(';')
               .append(decimal(t.getSaldoBloqueadoApos())).append(';')
               .append(t.getOperacaoId() == null ? "" : t.getOperacaoId())
               .append('\n');
        }
        return csv.toString();
    }

    // -- Resumo --------------------------------------------------------------

    @Transactional(readOnly = true)
    public ResumoFinanceiroResponse resumo(Long usuarioId, LocalDate inicio, LocalDate fim) {
        LocalDate de = inicio != null ? inicio : LocalDate.now().minusDays(DIAS_PADRAO - 1L);
        LocalDate ate = fim != null ? fim : LocalDate.now();
        exigirPeriodoValido(de, ate);

        BigDecimal entradas = BigDecimal.ZERO;
        BigDecimal saidas = BigDecimal.ZERO;
        for (Object[] linha : transacaoRepo.somarPorNatureza(
                usuarioId, de.atStartOfDay(), ate.plusDays(1).atStartOfDay())) {
            BigDecimal total = (BigDecimal) linha[1];
            if (linha[0] == NaturezaTransacao.CREDITO) {
                entradas = total;
            } else {
                saidas = total;
            }
        }

        Carteira carteira = carteiras.obterOuCriar(usuarioId);

        List<ReservaAbertaResponse> reservas = transacaoRepo.reservasAbertas(usuarioId).stream()
                .map(r -> new ReservaAbertaResponse(r.turnoId(), r.titulo(), emReais(r.valor())))
                .toList();

        List<TotalPorTipoResponse> porTipo = transacaoRepo.totalPorTipo(
                        usuarioId, de.atStartOfDay(), ate.plusDays(1).atStartOfDay()).stream()
                .map(t -> new TotalPorTipoResponse(t.tipo(), naturezaDe(t.tipo()),
                        emReais(t.total()), t.quantidade()))
                .toList();

        return new ResumoFinanceiroResponse(
                de, ate,
                emReais(entradas), emReais(saidas), emReais(entradas.subtract(saidas)),
                emReais(carteira.getSaldoDisponivel()),
                emReais(carteira.getSaldoBloqueado()),
                emReais(aReceber(usuarioId)),
                emReais(carteira.getSaldoBloqueado()),
                reservas, porTipo);
    }

    /**
     * Quanto o entregador ainda vai receber por trabalho já aceito.
     *
     * <p>Turnos em que ele tem inscrição ativa e que ainda não foram
     * finalizados. <b>Não é saldo</b> — o dinheiro está bloqueado na carteira do
     * lojista, não na dele, e o turno ainda pode ser cancelado. Aparece separado
     * de disponível e de bloqueado justamente para não ser confundido com
     * dinheiro que já é dele.
     */
    private BigDecimal aReceber(Long usuarioId) {
        List<Long> turnos = inscricaoRepo.findByMotoboyIdAndStatus(usuarioId, StatusInscricao.ACEITO)
                .stream()
                .map(i -> i.getTurnoId())
                .toList();
        if (turnos.isEmpty()) return BigDecimal.ZERO;

        return turnoRepo.findAllById(turnos).stream()
                .filter(t -> t.getStatus() != StatusTurno.FINALIZADO
                        && t.getStatus() != StatusTurno.CANCELADO
                        && t.getStatus() != StatusTurno.EXPIRADO)
                .map(t -> t.getValorEstimado() == null ? BigDecimal.ZERO : t.getValorEstimado())
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    // -- Fluxo ---------------------------------------------------------------

    /** Agrupamentos aceitos pela série de fluxo. */
    public enum Agrupamento {
        DIA, SEMANA, MES;

        static Agrupamento de(String valor) {
            if (valor == null || valor.isBlank()) return DIA;
            try {
                return valueOf(valor.trim().toUpperCase());
            } catch (IllegalArgumentException e) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Agrupamento inválido: use dia, semana ou mes.");
            }
        }
    }

    /**
     * Série de entradas e saídas por período.
     *
     * <p>Os baldes vêm somados do banco, um por dia; aqui eles são dobrados no
     * agrupamento pedido. Períodos sem lançamento nenhum entram com zero — uma
     * série com buracos desenha um gráfico que mente sobre o intervalo.
     */
    @Transactional(readOnly = true)
    public List<FluxoPontoResponse> fluxo(Long usuarioId, String agrupamento,
                                          LocalDate inicio, LocalDate fim) {
        Agrupamento como = Agrupamento.de(agrupamento);
        LocalDate de = inicio != null ? inicio : LocalDate.now().minusDays(DIAS_PADRAO - 1L);
        LocalDate ate = fim != null ? fim : LocalDate.now();
        exigirPeriodoValido(de, ate);

        Map<LocalDate, BigDecimal[]> baldes = new TreeMap<>();
        for (LocalDate d = inicioDoBalde(de, como);
             !d.isAfter(ate);
             d = proximoBalde(d, como)) {
            baldes.put(d, new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
        }

        for (PontoDeFluxo p : transacaoRepo.fluxoPorDia(
                usuarioId, de.atStartOfDay(), ate.plusDays(1).atStartOfDay())) {
            LocalDate balde = inicioDoBalde(LocalDate.of(p.ano(), p.mes(), p.dia()), como);
            BigDecimal[] acc = baldes.computeIfAbsent(balde,
                    k -> new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
            int i = p.natureza() == NaturezaTransacao.CREDITO ? 0 : 1;
            acc[i] = acc[i].add(p.total());
        }

        List<FluxoPontoResponse> serie = new ArrayList<>();
        for (Map.Entry<LocalDate, BigDecimal[]> e : baldes.entrySet()) {
            BigDecimal entradas = e.getValue()[0];
            BigDecimal saidas = e.getValue()[1];
            serie.add(new FluxoPontoResponse(e.getKey(), rotulo(e.getKey(), como),
                    emReais(entradas), emReais(saidas), emReais(entradas.subtract(saidas))));
        }
        return serie;
    }

    private static LocalDate inicioDoBalde(LocalDate dia, Agrupamento como) {
        return switch (como) {
            case DIA -> dia;
            // Semana ISO, começando na segunda — o mesmo corte que o calendário
            // brasileiro usa para "semana do dia 8".
            case SEMANA -> dia.with(WeekFields.ISO.dayOfWeek(), 1);
            case MES -> dia.withDayOfMonth(1);
        };
    }

    private static LocalDate proximoBalde(LocalDate atual, Agrupamento como) {
        return switch (como) {
            case DIA -> atual.plusDays(1);
            case SEMANA -> atual.plusWeeks(1);
            case MES -> atual.plusMonths(1);
        };
    }

    private static String rotulo(LocalDate inicio, Agrupamento como) {
        return switch (como) {
            case DIA -> DIA.format(inicio);
            case SEMANA -> DIA.format(inicio) + " a " + DIA.format(inicio.plusDays(6));
            case MES -> String.format("%02d/%d", inicio.getMonthValue(), inicio.getYear());
        };
    }

    // -- Apoio ---------------------------------------------------------------

    /**
     * Período invertido é erro de quem chamou, não uma consulta que devolve
     * vazio: vazio pareceria "não houve movimento" e esconderia o engano.
     */
    private static void exigirPeriodoValido(LocalDate inicio, LocalDate fim) {
        if (fim.isBefore(inicio)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A data final não pode ser anterior à inicial.");
        }
    }

    private static Pageable pagina(Pageable pedido) {
        if (pedido == null || pedido.isUnpaged()) {
            return PageRequest.of(0, 20, Sort.by(Sort.Direction.DESC, "criadoEm"));
        }
        int tamanho = Math.min(pedido.getPageSize(), TAMANHO_MAXIMO);
        return PageRequest.of(pedido.getPageNumber(), tamanho,
                Sort.by(Sort.Direction.DESC, "criadoEm"));
    }

    /**
     * A natureza de um tipo, para a quebra do resumo.
     *
     * <p>A quebra vem agregada do banco e não traz linhas individuais, então
     * não há de onde ler a coluna {@code natureza} — ela é derivada do tipo,
     * que é a mesma regra que o ledger aplica ao gravar.
     */
    private static NaturezaTransacao naturezaDe(com.motoshift.entity.TipoTransacao tipo) {
        return switch (tipo) {
            case SAQUE, RESERVA, PAGAMENTO_ENVIADO, RETENCAO_ISS, RETENCAO_IRRF ->
                    NaturezaTransacao.DEBITO;
            case RECARGA, LIBERACAO_RESERVA, PAGAMENTO_RECEBIDO, ESTORNO, BONUS ->
                    NaturezaTransacao.CREDITO;
        };
    }

    private static BigDecimal emReais(BigDecimal v) {
        return (v == null ? BigDecimal.ZERO : v).setScale(2, RoundingMode.HALF_UP);
    }

    // decimal e csvSeguro moraram aqui ate o informe de rendimentos passar a
    // exportar CSV tambem — agora sao util.Csv, uma copia so.
    private static String decimal(BigDecimal v) {
        return Csv.decimal(v);
    }

    private static String csvSeguro(String texto) {
        return Csv.seguro(texto);
    }
}
