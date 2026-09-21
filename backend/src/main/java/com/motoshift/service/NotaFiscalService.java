package com.motoshift.service;

import com.motoshift.dto.NotaFiscalPendenteResponse;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.fiscal.CalculoTributario;
import com.motoshift.service.fiscal.EmissorDeNotas;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Emissão da nota fiscal de serviço de um pagamento de turno.
 *
 * <p><b>O que é e o que não é.</b> A nota emitida aqui é um documento
 * SIMULADO, com a estrutura de uma NFS-e: prestador, tomador, discriminação do
 * serviço, base de cálculo, tributos e valor líquido. Não há transmissão à
 * prefeitura, RPS nem certificado digital. Quem numera e autentica é o
 * {@link EmissorDeNotas}; trocar a simulação por um provedor real é trocar a
 * implementação dele, sem mexer neste serviço nem no modelo — ver
 * {@code docs/financeiro/FISCAL.md}.
 *
 * <p><b>A nota documenta um pagamento.</b> Até a V14 ela nascia do turno, com
 * a base de cálculo tirada do valor estimado. Agora nasce do
 * {@code pagamento_recebido} concluído no extrato: a base é o que entrou na
 * carteira, e sem esse lançamento não há o que documentar. Os dois caminhos de
 * emissão — pelo turno ({@link #emitir}) e pelo lançamento do extrato
 * ({@link #emitirParaPagamento}) — terminam no mesmo lugar.
 *
 * <p><b>Os dois lados.</b> O documento é sempre o mesmo — o entregador presta,
 * o lojista toma —, mas qualquer um dos dois pode disparar a emissão. O
 * lojista chega a ela pelo pagamento_enviado dele, que tem a mesma operação do
 * pagamento_recebido do entregador. Não existe "nota do lojista" separada: uma
 * segunda nota documentaria um serviço que não houve.
 *
 * <p><b>Tributos.</b> ISS e IRRF — ver {@link CalculoTributario}. A nota não
 * decide se houve retenção: ela procura os lançamentos de retenção da mesma
 * operação. Havendo, os valores retidos vão para a nota e o líquido é o que
 * sobrou; não havendo, os tributos são o valor aproximado (informativo) e o
 * líquido é o próprio valor do serviço — igual ao extrato.
 */
@Service
public class NotaFiscalService {

    private static final DateTimeFormatter DATA = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final DateTimeFormatter HORA = DateTimeFormatter.ofPattern("HH:mm");

    private final NotaFiscalRepository notaRepo;
    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TransacaoRepository transacaoRepo;
    private final NotificacaoService notificacoes;
    private final CalculoTributario tributos;
    private final EmissorDeNotas emissor;

    public NotaFiscalService(NotaFiscalRepository notaRepo,
                             TurnoRepository turnoRepo,
                             TurnoInscricaoRepository inscricaoRepo,
                             UsuarioRepository usuarioRepo,
                             TransacaoRepository transacaoRepo,
                             NotificacaoService notificacoes,
                             CalculoTributario tributos,
                             EmissorDeNotas emissor) {
        this.notaRepo = notaRepo;
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.transacaoRepo = transacaoRepo;
        this.notificacoes = notificacoes;
        this.tributos = tributos;
        this.emissor = emissor;
    }

    // ── Emissão ─────────────────────────────────────────────────────────────

    /**
     * Emite (ou devolve, se já existir) a nota do par turno + entregador.
     *
     * <p>Caminho da tela de notas e do "O que falta" do turno: acha o
     * pagamento daquele entregador no turno e delega a
     * {@link #emitirParaPagamento}.
     */
    @Transactional
    public Emissao emitir(Long turnoId, Long prestadorId, Long solicitanteId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Turno não encontrado."));

        Long prestador = resolverPrestador(turno, prestadorId, solicitanteId);
        exigirParticipante(turno, prestador, solicitanteId);

        // A nota documenta um serviço prestado: antes de o turno terminar não
        // há o que declarar.
        if (turno.getStatus() != StatusTurno.FINALIZADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A nota fiscal só pode ser emitida depois que o turno for finalizado.");
        }

        Transacao pagamento = pagamentoDe(turnoId, prestador)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.CONFLICT,
                        "Não há pagamento concluído deste turno no extrato do entregador."));
        return emitirParaPagamento(pagamento, solicitanteId);
    }

    /**
     * Emite (ou devolve) a NFS-e de um pagamento_recebido concluído.
     *
     * <p>Idempotente de propósito: os dois lados veem o mesmo botão, e duas
     * chamadas não podem gerar dois documentos para o mesmo serviço. A
     * unicidade está no banco (uma nota por pagamento, V14; uma por turno e
     * prestador, V7) — a busca abaixo é o caminho rápido, o índice é a
     * garantia.
     */
    @Transactional
    public Emissao emitirParaPagamento(Transacao pagamento, Long solicitanteId) {
        if (pagamento.getTipo() != TipoTransacao.PAGAMENTO_RECEBIDO) {
            throw new IllegalArgumentException(
                    "NFS-e documenta pagamento recebido, não " + pagamento.getTipo().getValor());
        }
        if (pagamento.getStatus() != StatusTransacao.CONCLUIDO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A nota fiscal só pode ser emitida para um pagamento concluído.");
        }
        Long prestador = pagamento.getUsuarioId();
        Long tomador = pagamento.getContraparteId();
        if (!solicitanteId.equals(prestador) && !solicitanteId.equals(tomador)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: este pagamento não é seu.");
        }

        Optional<NotaFiscal> existente = notaRepo.findByTransacaoId(pagamento.getId());
        if (existente.isPresent()) {
            return new Emissao(montar(existente.get(), solicitanteId), false);
        }

        // Nota anterior à V14 que o backfill não conseguiu ligar: é a mesma
        // nota (mesmo turno, mesmo prestador), só falta o vínculo.
        if (pagamento.getTurnoId() != null) {
            Optional<NotaFiscal> doTurno =
                    notaRepo.findByTurnoIdAndPrestadorId(pagamento.getTurnoId(), prestador);
            if (doTurno.isPresent()) {
                NotaFiscal n = doTurno.get();
                n.setTransacaoId(pagamento.getId());
                n.setOperacaoId(pagamento.getOperacaoId());
                return new Emissao(montar(notaRepo.save(n), solicitanteId), false);
            }
        }

        Turno turno = pagamento.getTurnoId() == null ? null
                : turnoRepo.findById(pagamento.getTurnoId()).orElse(null);
        NotaFiscal salva = notaRepo.save(montarNota(pagamento, turno, solicitanteId));

        avisarAsPartes(salva, turno, solicitanteId);
        return new Emissao(montar(salva, solicitanteId), true);
    }

    /** O pagamento_recebido concluído de um entregador num turno. */
    public Optional<Transacao> pagamentoDe(Long turnoId, Long prestadorId) {
        return transacaoRepo.findFirstByTurnoIdAndUsuarioIdAndTipoAndStatusOrderByCriadoEmAsc(
                turnoId, prestadorId, TipoTransacao.PAGAMENTO_RECEBIDO, StatusTransacao.CONCLUIDO);
    }

    private NotaFiscal montarNota(Transacao pagamento, Turno turno, Long solicitanteId) {
        BigDecimal base = emReais(pagamento.getValor());

        NotaFiscal n = new NotaFiscal();
        n.setTurnoId(pagamento.getTurnoId());
        n.setPrestadorId(pagamento.getUsuarioId());
        n.setTomadorId(pagamento.getContraparteId());
        n.setEmitidaPorId(solicitanteId);
        n.setTransacaoId(pagamento.getId());
        n.setOperacaoId(pagamento.getOperacaoId());
        n.setCompetencia(turno == null ? pagamento.getCriadoEm() : turno.getDataInicio());
        n.setDescricaoServico(discriminacao(turno));
        n.setValorServico(base);
        aplicarTributos(n, pagamento, base);
        n.setEmitidaEm(LocalDateTime.now());

        EmissorDeNotas.Autorizacao a = emissor.autorizar(n);
        n.setNumero(a.numero());
        n.setSerie(a.serie());
        n.setCodigoVerificacao(a.codigoVerificacao());
        return n;
    }

    /**
     * ISS, IRRF e líquido, lidos do extrato quando houve retenção.
     *
     * <p>Com retenção, os valores vêm dos lançamentos retencao_iss e
     * retencao_irrf da mesma operação, e a alíquota é a efetiva — a que valeu
     * no dia da liquidação, não a configurada hoje. Sem retenção, é a conta com
     * as alíquotas vigentes, e o líquido é o próprio valor do serviço.
     */
    private void aplicarTributos(NotaFiscal n, Transacao pagamento, BigDecimal base) {
        List<Transacao> retencoes = pagamento.getOperacaoId() == null ? List.of()
                : transacaoRepo.findByOperacaoIdAndUsuarioIdAndTipoIn(
                        pagamento.getOperacaoId(), pagamento.getUsuarioId(),
                        List.of(TipoTransacao.RETENCAO_ISS, TipoTransacao.RETENCAO_IRRF))
                        .stream()
                        .filter(t -> t.getStatus() == StatusTransacao.CONCLUIDO)
                        .toList();

        if (retencoes.isEmpty()) {
            CalculoTributario.Tributos t = tributos.calcular(base);
            n.setIssAliquota(t.issAliquota());
            n.setIssValor(t.iss());
            n.setIrrfAliquota(t.irrfAliquota());
            n.setIrrfValor(t.irrf());
            n.setTributosRetidos(false);
            n.setValorLiquido(base);
            return;
        }

        BigDecimal iss = somaDoTipo(retencoes, TipoTransacao.RETENCAO_ISS);
        BigDecimal irrf = somaDoTipo(retencoes, TipoTransacao.RETENCAO_IRRF);
        n.setIssAliquota(CalculoTributario.aliquotaDe(iss, base));
        n.setIssValor(iss);
        n.setIrrfAliquota(CalculoTributario.aliquotaDe(irrf, base));
        n.setIrrfValor(irrf);
        n.setTributosRetidos(true);
        n.setValorLiquido(base.subtract(iss).subtract(irrf));
    }

    private static BigDecimal somaDoTipo(List<Transacao> lancamentos, TipoTransacao tipo) {
        return lancamentos.stream()
                .filter(t -> t.getTipo() == tipo)
                .map(Transacao::getValor)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .setScale(2, RoundingMode.HALF_UP);
    }

    /** Discriminação do serviço: turno, data, horário e região. */
    static String discriminacao(Turno turno) {
        if (turno == null) {
            return "Serviço de entrega em turno agendado.";
        }
        String regiao = turno.getRegiao() == null || turno.getRegiao().isBlank()
                ? "região não informada"
                : turno.getRegiao();
        StringBuilder sb = new StringBuilder("Serviço de entrega em turno agendado — ")
                .append(turno.getTitulo()).append(". ");
        if (turno.getDataInicio() != null) {
            sb.append("Data: ").append(DATA.format(turno.getDataInicio()));
            if (turno.getDataFim() != null) {
                sb.append(", das ").append(HORA.format(turno.getDataInicio()))
                        .append(" às ").append(HORA.format(turno.getDataFim()));
            }
            sb.append(". ");
        }
        sb.append("Região: ").append(regiao).append('.');
        String texto = sb.toString();
        // A coluna é de 300: um título longo não pode derrubar a emissão.
        return texto.length() <= 300 ? texto : texto.substring(0, 297) + "...";
    }

    private void avisarAsPartes(NotaFiscal nota, Turno turno, Long solicitanteId) {
        String titulo = "Nota fiscal emitida";
        String mensagem = "A NFS-e nº " + nota.getNumero()
                + (turno == null ? "" : " do turno \"" + turno.getTitulo() + "\"")
                + " foi emitida.";
        // Só o outro lado é notificado: quem clicou acabou de ver o resultado.
        Long outro = solicitanteId.equals(nota.getPrestadorId())
                ? nota.getTomadorId()
                : nota.getPrestadorId();
        notificacoes.criar(outro, "nota_fiscal_emitida", titulo, mensagem,
                "nota_fiscal", nota.getId());
    }

    // ── Cancelamento ────────────────────────────────────────────────────────

    /**
     * Cancela a nota. Só o prestador cancela — é dele o documento.
     *
     * <p><b>Cancelar a nota NÃO estorna dinheiro.</b> A nota documenta um
     * pagamento que aconteceu; cancelar o documento não desfaz o pagamento, do
     * mesmo jeito que rasgar um recibo não devolve o valor pago. O extrato
     * continua com o pagamento_recebido e o pagamento_enviado. E, como a
     * unicidade é por pagamento, uma nota cancelada não é substituída por
     * outra: gerar o documento de novo devolve a cancelada.
     */
    @Transactional
    public NotaFiscalResponse cancelar(Long notaId, String motivo, Long solicitanteId) {
        NotaFiscal nota = notaRepo.findById(notaId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Nota fiscal não encontrada."));

        if (!nota.getPrestadorId().equals(solicitanteId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Apenas o prestador do serviço pode cancelar a nota fiscal.");
        }
        if (nota.isCancelada()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Esta nota fiscal já está cancelada.");
        }

        nota.setCanceladaEm(LocalDateTime.now());
        nota.setMotivoCancelamento(
                motivo == null || motivo.isBlank() ? "Cancelada pelo prestador" : motivo.trim());
        NotaFiscal salva = notaRepo.save(nota);

        notificacoes.criar(salva.getTomadorId(), "nota_fiscal_cancelada",
                "Nota fiscal cancelada",
                "A NFS-e nº " + salva.getNumero() + " foi cancelada pelo prestador.",
                "nota_fiscal", salva.getId());

        return montar(salva, solicitanteId);
    }

    // ── Consultas ───────────────────────────────────────────────────────────

    public List<NotaFiscalResponse> listarDoUsuario(Long usuarioId) {
        return montarTodas(notaRepo.findDoUsuario(usuarioId), usuarioId);
    }

    /** Monta várias notas com uma consulta de pessoas, em vez de duas por nota. */
    public List<NotaFiscalResponse> montarTodas(List<NotaFiscal> notas, Long usuarioId) {
        Map<Long, Usuario> pessoas = carregarPessoas(notas);
        List<NotaFiscalResponse> saida = new ArrayList<>(notas.size());
        for (NotaFiscal n : notas) {
            saida.add(NotaFiscalResponse.from(n, pessoas.get(n.getPrestadorId()),
                    pessoas.get(n.getTomadorId()), usuarioId));
        }
        return saida;
    }

    public NotaFiscalResponse buscar(Long notaId, Long solicitanteId) {
        NotaFiscal nota = notaRepo.findById(notaId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Nota fiscal não encontrada."));

        // Nota fiscal é documento das duas partes e de mais ninguém.
        if (!nota.getPrestadorId().equals(solicitanteId)
                && !nota.getTomadorId().equals(solicitanteId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: esta nota fiscal não é sua.");
        }
        return montar(nota, solicitanteId);
    }

    /**
     * Pagamentos de turno que ainda não geraram nota, do ponto de vista de
     * quem pergunta. O lojista vê um item por entregador de cada turno seu; o
     * entregador vê os turnos em que trabalhou.
     *
     * <p>Só entra o que tem pagamento concluído no extrato — é a condição da
     * emissão. Um turno finalizado antes do ledger, sem crédito registrado,
     * não aparece como pendência que depois o botão recusaria.
     *
     * <p>Quatro consultas no total, independentemente do número de turnos.
     */
    public List<NotaFiscalPendenteResponse> pendentes(Long usuarioId, boolean ehLojista) {
        List<Turno> turnos = (ehLojista
                ? turnoRepo.findByLojistId(usuarioId)
                : turnosDoEntregador(usuarioId))
                .stream()
                .filter(t -> t.getId() != null && t.getStatus() == StatusTurno.FINALIZADO)
                .toList();
        if (turnos.isEmpty()) return List.of();

        Map<Long, List<Long>> prestadores = prestadoresPorTurno(turnos, usuarioId, ehLojista);
        // "turnoId:prestadorId" das notas que já existem para este usuário.
        Set<String> jaEmitidas = notaRepo.findDoUsuario(usuarioId).stream()
                .map(n -> n.getTurnoId() + ":" + n.getPrestadorId())
                .collect(Collectors.toSet());
        // "turnoId:prestadorId" → valor pago, dos pagamentos concluídos.
        Map<String, BigDecimal> pagos = new HashMap<>();
        for (Transacao t : transacaoRepo.findByTurnoIdInAndTipoAndStatus(
                turnos.stream().map(Turno::getId).toList(),
                TipoTransacao.PAGAMENTO_RECEBIDO, StatusTransacao.CONCLUIDO)) {
            pagos.putIfAbsent(t.getTurnoId() + ":" + t.getUsuarioId(), t.getValor());
        }

        List<NotaFiscalPendenteResponse> saida = new ArrayList<>();
        Map<Long, String> nomes = nomesDe(turnos, prestadores, ehLojista);

        for (Turno t : turnos) {
            for (Long prestador : prestadores.getOrDefault(t.getId(), List.of())) {
                String par = t.getId() + ":" + prestador;
                if (jaEmitidas.contains(par) || !pagos.containsKey(par)) continue;

                Long contraparte = ehLojista ? prestador : t.getLojistId();
                saida.add(new NotaFiscalPendenteResponse(
                        t.getId(),
                        prestador,
                        t.getTitulo(),
                        t.getDataInicio(),
                        emReais(pagos.get(par)),
                        nomes.getOrDefault(contraparte, "—"),
                        ehLojista ? "tomador" : "prestador"));
            }
        }
        saida.sort((a, b) -> b.getDataInicio().compareTo(a.getDataInicio()));
        return saida;
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    /**
     * Quem prestou o serviço em cada turno. Para o entregador é sempre ele; para
     * o lojista, os entregadores inscritos — numa consulta para todos os turnos.
     *
     * <p>Inscrição CANCELADA fica de fora; ACEITO e FINALIZADO entram.
     */
    private Map<Long, List<Long>> prestadoresPorTurno(List<Turno> turnos, Long usuarioId,
                                                      boolean ehLojista) {
        Map<Long, List<Long>> porTurno = new HashMap<>();
        if (!ehLojista) {
            turnos.forEach(t -> porTurno.put(t.getId(), List.of(usuarioId)));
            return porTurno;
        }

        for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdIn(turnos.stream().map(Turno::getId).toList())) {
            if (ins.getStatus() == StatusInscricao.CANCELADO) continue;
            porTurno.computeIfAbsent(ins.getTurnoId(), k -> new ArrayList<>()).add(ins.getMotoboyId());
        }
        // Turno legado sem inscrição ainda tem o entregador no próprio turno.
        for (Turno t : turnos) {
            if (!porTurno.containsKey(t.getId()) && t.getMotoboyId() != null) {
                porTurno.put(t.getId(), List.of(t.getMotoboyId()));
            }
        }
        return porTurno;
    }

    /** Turnos em que o entregador trabalhou, numa consulta só. */
    private List<Turno> turnosDoEntregador(Long motoboyId) {
        return turnoRepo.findDoEntregador(motoboyId,
                List.of(StatusInscricao.ACEITO, StatusInscricao.FINALIZADO),
                Pageable.unpaged()).getContent();
    }

    /** Os nomes das contrapartes de uma vez — era um findById por pendência. */
    private Map<Long, String> nomesDe(List<Turno> turnos, Map<Long, List<Long>> prestadores,
                                      boolean ehLojista) {
        Set<Long> ids = new HashSet<>();
        if (ehLojista) {
            prestadores.values().forEach(ids::addAll);
        } else {
            turnos.forEach(t -> ids.add(t.getLojistId()));
        }
        Map<Long, String> nomes = new HashMap<>();
        for (Usuario u : usuarioRepo.findAllById(ids)) {
            nomes.put(u.getId(), u.getNome());
        }
        return nomes;
    }

    /** Se o pedido não disse quem prestou, o próprio solicitante é o entregador. */
    private Long resolverPrestador(Turno turno, Long prestadorId, Long solicitanteId) {
        if (prestadorId != null) return prestadorId;
        if (!solicitanteId.equals(turno.getLojistId())) return solicitanteId;
        if (turno.getMotoboyId() != null) return turno.getMotoboyId();
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Informe o entregador do turno para emitir a nota fiscal.");
    }

    /** Emitir a nota de um serviço alheio não é possível: ou presta, ou toma. */
    private void exigirParticipante(Turno turno, Long prestadorId, Long solicitanteId) {
        boolean ehTomador = solicitanteId.equals(turno.getLojistId());
        boolean ehPrestador = solicitanteId.equals(prestadorId);
        if (!ehTomador && !ehPrestador) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: você não participou deste turno.");
        }
        boolean inscrito = turno.getId() != null
                && (inscricaoRepo.findByTurnoIdAndMotoboyId(turno.getId(), prestadorId).isPresent()
                    || prestadorId.equals(turno.getMotoboyId()));
        if (!inscrito) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Este entregador não participou do turno.");
        }
    }

    NotaFiscalResponse montar(NotaFiscal n, Long solicitanteId) {
        return montarTodas(List.of(n), solicitanteId).get(0);
    }

    /** Uma consulta para todos os nomes, em vez de duas por nota na lista. */
    private Map<Long, Usuario> carregarPessoas(List<NotaFiscal> notas) {
        Set<Long> ids = new HashSet<>();
        for (NotaFiscal n : notas) {
            ids.add(n.getPrestadorId());
            ids.add(n.getTomadorId());
        }
        Map<Long, Usuario> mapa = new HashMap<>();
        for (Usuario u : usuarioRepo.findAllById(ids)) {
            mapa.put(u.getId(), u);
        }
        return mapa;
    }

    /**
     * Duas casas decimais, como todo valor que sai daqui para o app. O
     * {@code CarteiraResponse} faz o mesmo com os saldos.
     */
    private static BigDecimal emReais(BigDecimal valor) {
        return valor == null
                ? BigDecimal.ZERO.setScale(2)
                : valor.setScale(2, RoundingMode.HALF_UP);
    }

    /** Resultado da emissão: a nota e se ela nasceu agora ou já existia. */
    public record Emissao(NotaFiscalResponse nota, boolean criada) {}
}
