package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.util.GeoUtils;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
public class TurnoService {

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;

    public TurnoService(TurnoRepository turnoRepo,
                        UsuarioRepository usuarioRepo,
                        CarteiraRepository carteiraRepo,
                        TransacaoRepository transacaoRepo,
                        TurnoInscricaoRepository inscricaoRepo,
                        NotificacaoService notificacoes) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
    }

    /**
     * Monta o TurnoResponse já preenchendo {@code vagasPreenchidas} com a
     * contagem de inscrições ativas (status "aceito"). Centraliza para que
     * todas as listagens exponham a ocupação real do turno.
     */
    private TurnoResponse toResponse(Turno t) {
        return toResponse(t, null, null);
    }

    /**
     * Igual ao anterior, mas preenche {@code distanciaKm} quando a requisição
     * informou a posição do usuário (SCRUM-18).
     */
    private TurnoResponse toResponse(Turno t, Double origemLat, Double origemLng) {
        TurnoResponse r = TurnoResponse.from(t);
        long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), "aceito");
        r.setVagasPreenchidas((int) ativas);
        r.setDistanciaKm(GeoUtils.arredondar1(
                GeoUtils.distanciaKm(origemLat, origemLng, t.getLatitude(), t.getLongitude())));
        return r;
    }

    // RF04 — Criar turno: início deve ser >= agora + 2h
    @Transactional
    public TurnoResponse criar(TurnoRequest req) {
        LocalDateTime limiteMinimo = LocalDateTime.now().plusHours(2);
        if (req.getDataInicio().isBefore(limiteMinimo)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "O início do turno deve ser agendado com pelo menos 2 horas de antecedência.");
        }
        if (!req.getDataFim().isAfter(req.getDataInicio())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A hora de fim deve ser posterior à hora de início.");
        }

        Turno t = new Turno();
        t.setLojistId(req.getLojistId());
        t.setTitulo(req.getTitulo());
        t.setDescricao(req.getDescricao());
        t.setRegiao(req.getRegiao());
        t.setDataInicio(req.getDataInicio());
        t.setDataFim(req.getDataFim());
        t.setValorEstimado(req.getValorEstimado());
        t.setRaioEntregaKm(req.getRaioEntregaKm());

        // Geolocalização (SCRUM-18): opcional, mas se vier tem que ser válida.
        if (req.getLatitude() != null || req.getLongitude() != null) {
            if (!GeoUtils.coordenadaValida(req.getLatitude(), req.getLongitude())) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Latitude/longitude inválidas.");
            }
            t.setLatitude(req.getLatitude());
            t.setLongitude(req.getLongitude());
        }
        t.setEndereco(req.getEndereco());

        int vagas = req.getVagas() == null ? 1 : req.getVagas();
        if (vagas < 1) vagas = 1;
        if (vagas > 20) vagas = 20; // teto de segurança
        t.setVagas(vagas);

        return toResponse(turnoRepo.save(t));
    }

    // RF05 — Aceitar turno (com vagas): cada motoboy que aceita vira uma inscrição.
    // O turno permanece "aberto" enquanto houver vagas; fecha ("aceito") ao lotar.
    @Transactional
    public TurnoResponse aceitar(Long turnoId, Long motoboyId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));

        if (!"aberto".equals(turno.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno não está disponível para aceite.");
        }

        // Anti-duplicação: mesmo motoboy não pode aceitar o mesmo turno duas vezes.
        if (inscricaoRepo.existsByTurnoIdAndMotoboyIdAndStatus(turnoId, motoboyId, "aceito")) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já aceitou este turno.");
        }

        // Capacidade: respeita o número de vagas do turno.
        int vagas = turno.getVagas();
        long ocupadas = inscricaoRepo.countByTurnoIdAndStatus(turnoId, "aceito");
        if (ocupadas >= vagas) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Todas as vagas deste turno já foram preenchidas.");
        }

        // Conflito de agenda considerando TODAS as inscrições ativas do motoboy.
        if (temConflitoDeAgenda(motoboyId, turno)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já possui um turno agendado neste horário.");
        }

        // Registra a inscrição.
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(turnoId);
        ins.setMotoboyId(motoboyId);
        ins.setStatus("aceito");
        inscricaoRepo.save(ins);
        ocupadas++;

        // Primeiro inscrito vira o motoboy "principal" (compatibilidade com os
        // fluxos atuais de finalização/pagamento).
        if (turno.getMotoboyId() == null) {
            turno.setMotoboyId(motoboyId);
        }
        // Fecha o turno quando todas as vagas forem preenchidas.
        if (ocupadas >= vagas) {
            turno.setStatus("aceito");
        }
        turnoRepo.save(turno);

        // SCRUM-20: lojista é avisado de cada aceite.
        String nomeMotoboy = usuarioRepo.findById(motoboyId)
                .map(Usuario::getNome).orElse("Um entregador");
        notificacoes.criar(turno.getLojistId(), "turno_aceito",
                "Vaga preenchida",
                nomeMotoboy + " aceitou o turno \"" + turno.getTitulo() + "\" ("
                        + ocupadas + "/" + vagas + " vagas).",
                "turno", turno.getId());

        return toResponse(turno);
    }

    /**
     * Verifica se o motoboy já tem alguma inscrição ativa cujo turno se
     * sobrepõe ao horário do turno alvo. Cobre o cenário multi-vaga em que o
     * turno de origem ainda está "aberto" (não pego pelo antigo findConflitos).
     */
    private boolean temConflitoDeAgenda(Long motoboyId, Turno alvo) {
        List<TurnoInscricao> ativas = inscricaoRepo.findByMotoboyIdAndStatus(motoboyId, "aceito");
        for (TurnoInscricao ins : ativas) {
            Turno outro = turnoRepo.findById(ins.getTurnoId()).orElse(null);
            if (outro == null) continue;
            if (outro.getId().equals(alvo.getId())) continue;
            if ("cancelado".equals(outro.getStatus())) continue;
            boolean sobrepoe = outro.getDataInicio().isBefore(alvo.getDataFim())
                    && outro.getDataFim().isAfter(alvo.getDataInicio());
            if (sobrepoe) return true;
        }
        return false;
    }

    // RF06 — Finalizar turno: credita valor na carteira do motoboy
    @Transactional
    public TurnoResponse finalizar(Long turnoId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));

        if (turno.getMotoboyId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Turno sem motoboy atribuído.");
        }
        if ("finalizado".equals(turno.getStatus()) || "cancelado".equals(turno.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já encerrado.");
        }

        turno.setStatus("finalizado");
        turno.setPagamentoStatus("pendente");
        turnoRepo.save(turno);

        List<TurnoInscricao> inscricoes =
                inscricaoRepo.findByTurnoIdAndStatus(turno.getId(), "aceito");

        if (inscricoes.isEmpty()) {
            // Legado: turno sem inscrições (aceito antes do sistema de vagas).
            criarTransacaoPendente(turno, turno.getMotoboyId());
        } else {
            // Cada entregador inscrito gera sua própria transação/pagamento.
            for (TurnoInscricao ins : inscricoes) {
                ins.setStatus("finalizado");
                ins.setPagamentoStatus("pendente");
                inscricaoRepo.save(ins);
                criarTransacaoPendente(turno, ins.getMotoboyId());
            }
        }

        for (Long destinatario : participantesDoTurno(turno)) {
            notificacoes.criar(destinatario, "avaliacao_pendente",
                    "Turno finalizado",
                    "O turno \"" + turno.getTitulo() + "\" foi finalizado. "
                            + "Confirme o pagamento e avalie a outra parte.",
                    "turno", turno.getId());
        }

        return toResponse(turno);
    }

    /** Lojista + todos os entregadores não cancelados do turno. */
    private List<Long> participantesDoTurno(Turno turno) {
        java.util.LinkedHashSet<Long> ids = new java.util.LinkedHashSet<>();
        if (turno.getLojistId() != null) ids.add(turno.getLojistId());
        if (turno.getMotoboyId() != null) ids.add(turno.getMotoboyId());
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoId(turno.getId())) {
            if (!"cancelado".equals(ins.getStatus())) ids.add(ins.getMotoboyId());
        }
        return new java.util.ArrayList<>(ids);
    }

    private void criarTransacaoPendente(Turno turno, Long motoboyId) {
        if (motoboyId == null) return;
        Transacao tx = new Transacao();
        tx.setMotoboyId(motoboyId);
        tx.setTurnoId(turno.getId());
        tx.setTipo("turno");
        tx.setValor(turno.getValorEstimado());
        tx.setDescricao("Turno finalizado: " + turno.getTitulo());
        tx.setStatus("pendente");
        transacaoRepo.save(tx);
    }

    // Lojista declara que enviou o pagamento a um entregador específico.
    // Pagamento só é efetivado quando AMBAS as partes confirmarem (anti-fraude).
    // motoboyId identifica qual entregador está sendo pago (multi-vaga). Se null,
    // usa o motoboy principal do turno (compatibilidade).
    @Transactional
    public TurnoResponse confirmarPagamentoLojista(Long turnoId, Long lojistaId, Long motoboyId) {
        Turno turno = carregarParaConfirmacao(turnoId);

        if (!turno.getLojistId().equals(lojistaId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Apenas o lojista do turno pode confirmar o pagamento.");
        }

        Long alvo = motoboyId != null ? motoboyId : turno.getMotoboyId();
        TurnoInscricao ins = alvo == null ? null
                : inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, alvo).orElse(null);

        if (ins != null) {
            if (ins.getLojistaConfirmouEm() != null) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "Você já confirmou o pagamento deste entregador. Aguardando a confirmação dele.");
            }
            ins.setLojistaConfirmouEm(LocalDateTime.now());
            inscricaoRepo.save(ins);
            liquidarInscricao(turno, ins);
            atualizarPagamentoTurno(turno);
            return toResponse(turnoRepo.save(turno));
        }

        // Fallback legado (turno sem inscrições).
        if (turno.getLojistaConfirmouEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já confirmou o pagamento. Aguardando confirmação do motoboy.");
        }
        turno.setLojistaConfirmouEm(LocalDateTime.now());
        tentarEfetivarPagamento(turno);
        return toResponse(turnoRepo.save(turno));
    }

    // Motoboy declara que recebeu o pagamento.
    @Transactional
    public TurnoResponse confirmarRecebimentoMotoboy(Long turnoId, Long motoboyId) {
        Turno turno = carregarParaConfirmacao(turnoId);

        TurnoInscricao ins =
                inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, motoboyId).orElse(null);

        if (ins != null) {
            if (ins.getMotoboyConfirmouEm() != null) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "Você já confirmou o recebimento. Aguardando confirmação do lojista.");
            }
            ins.setMotoboyConfirmouEm(LocalDateTime.now());
            inscricaoRepo.save(ins);
            liquidarInscricao(turno, ins);
            atualizarPagamentoTurno(turno);
            return toResponse(turnoRepo.save(turno));
        }

        // Fallback legado (turno sem inscrições).
        if (turno.getMotoboyId() == null || !turno.getMotoboyId().equals(motoboyId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Apenas o motoboy do turno pode confirmar o recebimento.");
        }
        if (turno.getMotoboyConfirmouEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já confirmou o recebimento. Aguardando confirmação do lojista.");
        }
        turno.setMotoboyConfirmouEm(LocalDateTime.now());
        tentarEfetivarPagamento(turno);
        return toResponse(turnoRepo.save(turno));
    }

    /** Efetiva o pagamento de UMA inscrição quando ambas as partes confirmaram. */
    private void liquidarInscricao(Turno turno, TurnoInscricao ins) {
        if (ins.getLojistaConfirmouEm() == null || ins.getMotoboyConfirmouEm() == null) {
            return; // aguardando a outra parte
        }
        if ("pago".equals(ins.getPagamentoStatus())) return;

        ins.setPagamentoStatus("pago");
        inscricaoRepo.save(ins);
        creditarCarteira(ins.getMotoboyId(), turno.getValorEstimado());
        marcarTransacaoProcessada(ins.getMotoboyId(), turno.getId());

        notificacoes.criar(ins.getMotoboyId(), "pagamento_confirmado",
                "Pagamento confirmado",
                "O pagamento do turno \"" + turno.getTitulo() + "\" foi creditado na sua carteira.",
                "carteira", turno.getId());
    }

    /** Turno vira "pago" quando todas as inscrições finalizadas foram pagas. */
    private void atualizarPagamentoTurno(Turno turno) {
        List<TurnoInscricao> participantes = inscricaoRepo.findByTurnoId(turno.getId())
                .stream()
                .filter(i -> i.getPagamentoStatus() != null)
                .collect(Collectors.toList());
        if (!participantes.isEmpty()
                && participantes.stream().allMatch(i -> "pago".equals(i.getPagamentoStatus()))) {
            turno.setPagamentoStatus("pago");
        }
    }

    private Turno carregarParaConfirmacao(Long turnoId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));
        if (!"finalizado".equals(turno.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Só é possível confirmar pagamento de turnos finalizados.");
        }
        if ("pago".equals(turno.getPagamentoStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já foi pago.");
        }
        return turno;
    }

    // Legado: efetiva pagamento no nível do turno (motoboy único, sem inscrições).
    private void tentarEfetivarPagamento(Turno turno) {
        if (turno.getLojistaConfirmouEm() == null
                || turno.getMotoboyConfirmouEm() == null) {
            return; // ainda aguardando a outra parte
        }
        turno.setPagamentoStatus("pago");
        creditarCarteira(turno.getMotoboyId(), turno.getValorEstimado());
        marcarTransacaoProcessada(turno.getMotoboyId(), turno.getId());
    }

    // Credita saldo e ganhos mensais na carteira do motoboy.
    private void creditarCarteira(Long motoboyId, BigDecimal valor) {
        if (motoboyId == null || valor == null) return;
        Carteira carteira = carteiraRepo.findByMotoboyId(motoboyId)
                .orElseGet(() -> {
                    Carteira c = new Carteira();
                    c.setMotoboyId(motoboyId);
                    return c;
                });
        carteira.setSaldoAtual(carteira.getSaldoAtual().add(valor));
        carteira.setGanhosMensais(carteira.getGanhosMensais().add(valor));
        carteiraRepo.save(carteira);
    }

    // Marca a transação pendente daquele motoboy/turno como processada.
    private void marcarTransacaoProcessada(Long motoboyId, Long turnoId) {
        if (motoboyId == null) return;
        transacaoRepo.findByMotoboyIdOrderByCriadoEmDesc(motoboyId)
                .stream()
                .filter(t -> turnoId.equals(t.getTurnoId()) && "pendente".equals(t.getStatus()))
                .findFirst()
                .ifPresent(tx -> {
                    tx.setStatus("processado");
                    transacaoRepo.save(tx);
                });
    }

    // RF07 — Cancelar turno: penalidade no score se < 1h antes do início
    @Transactional
    public TurnoResponse cancelar(Long turnoId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));

        if ("finalizado".equals(turno.getStatus()) || "cancelado".equals(turno.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já encerrado.");
        }

        boolean cancelamentoTardio = LocalDateTime.now().isAfter(
                turno.getDataInicio().minusHours(1));

        if (cancelamentoTardio && turno.getMotoboyId() != null) {
            usuarioRepo.findById(turno.getMotoboyId()).ifPresent(motoboy -> {
                double novoScore = Math.max(0.0, motoboy.getScore() - 0.5);
                motoboy.setScore(novoScore);
                usuarioRepo.save(motoboy);
            });
        }

        // Cancela também as inscrições ativas (libera as vagas ocupadas).
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdAndStatus(turnoId, "aceito")) {
            ins.setStatus("cancelado");
            inscricaoRepo.save(ins);
        }

        turno.setStatus("cancelado");
        turnoRepo.save(turno);

        // SCRUM-20: todo mundo que estava no turno precisa saber.
        for (Long destinatario : participantesDoTurno(turno)) {
            notificacoes.criar(destinatario, "turno_cancelado",
                    "Turno cancelado",
                    "O turno \"" + turno.getTitulo() + "\" foi cancelado.",
                    "turno", turno.getId());
        }

        return toResponse(turno);
    }

    public List<TurnoResponse> listarDisponiveis() {
        return turnoRepo.findByStatus("aberto").stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarDisponiveisComFiltros(
            String horarioInicio, String horarioFim, Integer diaSemana,
            Double raioMaxKm, String dataInicio, String dataFim, String ordenarPor,
            Double lat, Double lng, Double raioKm) {

        // Filtro geográfico só liga se houver posição do usuário E raio.
        final boolean geo = GeoUtils.coordenadaValida(lat, lng) && raioKm != null && raioKm > 0;

        // Pré-filtro no banco: bounding box (usa índice) em vez de carregar
        // todos os turnos abertos para a memória.
        List<Turno> base;
        if (geo) {
            double dLat = GeoUtils.deltaLatitude(raioKm);
            double dLng = GeoUtils.deltaLongitude(raioKm, lat);
            base = turnoRepo.findAbertosNaArea(lat - dLat, lat + dLat, lng - dLng, lng + dLng);
        } else {
            base = turnoRepo.findByStatus("aberto");
        }

        DateTimeFormatter hmFmt = DateTimeFormatter.ofPattern("HH:mm");
        Stream<Turno> stream = base.stream();

        try {
            if (horarioInicio != null && !horarioInicio.isBlank()) {
                LocalTime hiTime = LocalTime.parse(horarioInicio, hmFmt);
                stream = stream.filter(t -> !t.getDataInicio().toLocalTime().isBefore(hiTime));
            }
            if (horarioFim != null && !horarioFim.isBlank()) {
                LocalTime hfTime = LocalTime.parse(horarioFim, hmFmt);
                stream = stream.filter(t -> !t.getDataFim().toLocalTime().isAfter(hfTime));
            }
            if (dataInicio != null && !dataInicio.isBlank()) {
                LocalDate di = LocalDate.parse(dataInicio);
                stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isBefore(di));
            }
            if (dataFim != null && !dataFim.isBlank()) {
                LocalDate df = LocalDate.parse(dataFim);
                stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isAfter(df));
            }
        } catch (DateTimeParseException e) {
            // Antes isso virava 500. Formato ruim é erro do cliente.
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Formato de data/hora inválido. Use HH:mm para horários e yyyy-MM-dd para datas.");
        }

        if (diaSemana != null) {
            stream = stream.filter(t -> t.getDataInicio().getDayOfWeek().getValue() == diaSemana);
        }

        // raioEntregaKm é nullable: sem o teste de null isto lançava NPE no
        // unboxing e derrubava a listagem inteira.
        if (raioMaxKm != null) {
            stream = stream.filter(t -> t.getRaioEntregaKm() != null
                    && t.getRaioEntregaKm() <= raioMaxKm);
        }

        // Refino exato do raio: a bounding box é um quadrado, o raio é um círculo.
        if (geo) {
            stream = stream.filter(t -> {
                Double d = GeoUtils.distanciaKm(lat, lng, t.getLatitude(), t.getLongitude());
                return d != null && d <= raioKm;
            });
        }

        Comparator<Turno> comparator = switch (ordenarPor != null ? ordenarPor : "") {
            case "valorDesc"    -> Comparator.comparing(Turno::getValorEstimado,
                                       Comparator.nullsLast(Comparator.reverseOrder()));
            case "raioAsc"      -> Comparator.comparing(Turno::getRaioEntregaKm,
                                       Comparator.nullsLast(Comparator.naturalOrder()));
            case "dataInicio"   -> Comparator.comparing(Turno::getDataInicio);
            case "distanciaAsc" -> Comparator.comparingDouble((Turno t) -> {
                                       Double d = GeoUtils.distanciaKm(
                                               lat, lng, t.getLatitude(), t.getLongitude());
                                       return d == null ? Double.MAX_VALUE : d;
                                   });
            default             -> Comparator.comparing(Turno::getValorEstimado,
                                       Comparator.nullsLast(Comparator.naturalOrder()));
        };

        return stream.sorted(comparator)
                .map(t -> toResponse(t, geo ? lat : null, geo ? lng : null))
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarPorLojista(Long lojistId) {
        return turnoRepo.findByLojistId(lojistId).stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarPorMotoboy(Long motoboyId) {
        // Une turnos onde o motoboy é o principal (motoboyId) com aqueles em que
        // ele entrou por inscrição (vaga extra), sem duplicar.
        java.util.LinkedHashMap<Long, Turno> porId = new java.util.LinkedHashMap<>();
        for (Turno t : turnoRepo.findByMotoboyId(motoboyId)) {
            porId.put(t.getId(), t);
        }
        for (TurnoInscricao ins : inscricaoRepo.findByMotoboyIdAndStatus(motoboyId, "aceito")) {
            if (!porId.containsKey(ins.getTurnoId())) {
                turnoRepo.findById(ins.getTurnoId()).ifPresent(t -> porId.put(t.getId(), t));
            }
        }
        // Também inclui inscrições já finalizadas (histórico), evitando duplicatas.
        for (TurnoInscricao ins : inscricaoRepo.findByMotoboyIdAndStatus(motoboyId, "finalizado")) {
            if (!porId.containsKey(ins.getTurnoId())) {
                turnoRepo.findById(ins.getTurnoId()).ifPresent(t -> porId.put(t.getId(), t));
            }
        }
        return porId.values().stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    public TurnoResponse buscarPorId(Long id) {
        return turnoRepo.findById(id)
                .map(this::toResponse)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));
    }

    /** Entregadores inscritos no turno, com o status de pagamento de cada um. */
    public List<java.util.Map<String, Object>> listarInscritos(Long turnoId) {
        return inscricaoRepo.findByTurnoId(turnoId).stream()
                .filter(i -> !"cancelado".equals(i.getStatus()))
                .map(i -> {
                    java.util.Map<String, Object> m = new java.util.HashMap<>();
                    m.put("motoboyId", i.getMotoboyId());
                    m.put("nome", usuarioRepo.findById(i.getMotoboyId())
                            .map(Usuario::getNome).orElse("Entregador"));
                    m.put("status", i.getStatus());
                    m.put("pagamentoStatus", i.getPagamentoStatus());
                    m.put("lojistaConfirmou", i.getLojistaConfirmouEm() != null);
                    m.put("motoboyConfirmou", i.getMotoboyConfirmouEm() != null);
                    return m;
                })
                .collect(Collectors.toList());
    }
}
