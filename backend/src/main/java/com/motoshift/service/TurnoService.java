package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
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

    public TurnoService(TurnoRepository turnoRepo,
                        UsuarioRepository usuarioRepo,
                        CarteiraRepository carteiraRepo,
                        TransacaoRepository transacaoRepo) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
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

        return TurnoResponse.from(turnoRepo.save(t));
    }

    // RF05 — Aceitar turno: verifica conflito de agenda
    @Transactional
    public TurnoResponse aceitar(Long turnoId, Long motoboyId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));

        if (!"aberto".equals(turno.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno não está disponível para aceite.");
        }

        List<Turno> conflitos = turnoRepo.findConflitos(motoboyId, turno.getDataInicio(), turno.getDataFim());
        if (!conflitos.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já possui um turno agendado neste horário.");
        }

        turno.setMotoboyId(motoboyId);
        turno.setStatus("aceito");
        return TurnoResponse.from(turnoRepo.save(turno));
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
        turnoRepo.save(turno);

        // Credita valor na carteira
        Carteira carteira = carteiraRepo.findByMotoboyId(turno.getMotoboyId())
                .orElseGet(() -> {
                    Carteira c = new Carteira();
                    c.setMotoboyId(turno.getMotoboyId());
                    return c;
                });
        carteira.setSaldoAtual(carteira.getSaldoAtual() + turno.getValorEstimado());
        carteira.setGanhosMensais(carteira.getGanhosMensais() + turno.getValorEstimado());
        carteiraRepo.save(carteira);

        // Registra transação
        Transacao tx = new Transacao();
        tx.setMotoboyId(turno.getMotoboyId());
        tx.setTurnoId(turno.getId());
        tx.setTipo("turno");
        tx.setValor(turno.getValorEstimado());
        tx.setDescricao("Turno finalizado: " + turno.getTitulo());
        tx.setStatus("processado");
        transacaoRepo.save(tx);

        return TurnoResponse.from(turno);
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

        turno.setStatus("cancelado");
        return TurnoResponse.from(turnoRepo.save(turno));
    }

    public List<TurnoResponse> listarDisponiveis() {
        return turnoRepo.findByStatus("aberto").stream()
                .map(TurnoResponse::from)
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarDisponiveisComFiltros(
            String horarioInicio, String horarioFim, Integer diaSemana,
            Double raioMaxKm, String dataInicio, String dataFim, String ordenarPor) {

        DateTimeFormatter hmFmt = DateTimeFormatter.ofPattern("HH:mm");
        Stream<Turno> stream = turnoRepo.findByStatus("aberto").stream();

        if (horarioInicio != null && !horarioInicio.isBlank()) {
            LocalTime hiTime = LocalTime.parse(horarioInicio, hmFmt);
            stream = stream.filter(t -> !t.getDataInicio().toLocalTime().isBefore(hiTime));
        }
        if (horarioFim != null && !horarioFim.isBlank()) {
            LocalTime hfTime = LocalTime.parse(horarioFim, hmFmt);
            stream = stream.filter(t -> !t.getDataFim().toLocalTime().isAfter(hfTime));
        }
        if (diaSemana != null) {
            stream = stream.filter(t -> t.getDataInicio().getDayOfWeek().getValue() == diaSemana);
        }
        if (raioMaxKm != null) {
            stream = stream.filter(t -> t.getRaioEntregaKm() <= raioMaxKm);
        }
        if (dataInicio != null && !dataInicio.isBlank()) {
            LocalDate di = LocalDate.parse(dataInicio);
            stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isBefore(di));
        }
        if (dataFim != null && !dataFim.isBlank()) {
            LocalDate df = LocalDate.parse(dataFim);
            stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isAfter(df));
        }

        Comparator<Turno> comparator = switch (ordenarPor != null ? ordenarPor : "") {
            case "valorDesc"  -> Comparator.comparingDouble(Turno::getValorEstimado).reversed();
            case "raioAsc"    -> Comparator.comparingDouble(Turno::getRaioEntregaKm);
            case "dataInicio" -> Comparator.comparing(Turno::getDataInicio);
            default           -> Comparator.comparingDouble(Turno::getValorEstimado);
        };

        return stream.sorted(comparator)
                .map(TurnoResponse::from)
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarPorLojista(Long lojistId) {
        return turnoRepo.findByLojistId(lojistId).stream()
                .map(TurnoResponse::from)
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarPorMotoboy(Long motoboyId) {
        return turnoRepo.findByMotoboyId(motoboyId).stream()
                .map(TurnoResponse::from)
                .collect(Collectors.toList());
    }

    public TurnoResponse buscarPorId(Long id) {
        return turnoRepo.findById(id)
                .map(TurnoResponse::from)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado"));
    }
}
