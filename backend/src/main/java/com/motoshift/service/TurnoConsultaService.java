package com.motoshift.service;

import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.util.GeoUtils;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Tudo que so le turno: listagens, filtros, busca por id e inscritos.
 *
 * E metade do antigo TurnoService em linhas, e nao compartilha nada com a
 * escrita a nao ser o mapeamento. Separado, o servico de ciclo de vida cabe na
 * cabeca e o filtro geografico — que e a parte mais densa daqui — para de
 * disputar espaco com a regra de negocio.
 */
@Service
public class TurnoConsultaService {

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TurnoMapper mapper;
    private final TurnoAcesso acesso;

    public TurnoConsultaService(TurnoRepository turnoRepo,
                                TurnoInscricaoRepository inscricaoRepo,
                                UsuarioRepository usuarioRepo,
                                TurnoMapper mapper,
                                TurnoAcesso acesso) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.mapper = mapper;
        this.acesso = acesso;
    }

    public List<TurnoResponse> listarDisponiveis() {
        return turnoRepo.findByStatus(StatusTurno.ABERTO).stream()
                .map(mapper::toResponse)
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
            base = turnoRepo.findByStatus(StatusTurno.ABERTO);
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
                .map(t -> mapper.toResponse(t, geo ? lat : null, geo ? lng : null))
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarPorLojista(Long lojistId) {
        return turnoRepo.findByLojistId(lojistId).stream()
                .map(mapper::toResponse)
                .collect(Collectors.toList());
    }

    public List<TurnoResponse> listarPorMotoboy(Long motoboyId) {
        // Une turnos onde o motoboy é o principal (motoboyId) com aqueles em que
        // ele entrou por inscrição (vaga extra), sem duplicar.
        LinkedHashMap<Long, Turno> porId = new LinkedHashMap<>();
        for (Turno t : turnoRepo.findByMotoboyId(motoboyId)) {
            porId.put(t.getId(), t);
        }
        for (TurnoInscricao ins : inscricaoRepo.findByMotoboyIdAndStatus(motoboyId, StatusInscricao.ACEITO)) {
            if (!porId.containsKey(ins.getTurnoId())) {
                turnoRepo.findById(ins.getTurnoId()).ifPresent(t -> porId.put(t.getId(), t));
            }
        }
        // Também inclui inscrições já finalizadas (histórico), evitando duplicatas.
        for (TurnoInscricao ins : inscricaoRepo.findByMotoboyIdAndStatus(motoboyId, StatusInscricao.FINALIZADO)) {
            if (!porId.containsKey(ins.getTurnoId())) {
                turnoRepo.findById(ins.getTurnoId()).ifPresent(t -> porId.put(t.getId(), t));
            }
        }
        return porId.values().stream()
                .map(mapper::toResponse)
                .collect(Collectors.toList());
    }

    public TurnoResponse buscarPorId(Long id) {
        return mapper.toResponse(acesso.carregar(id));
    }

    /** Entregadores inscritos no turno, com o status de pagamento de cada um. */
    public List<Map<String, Object>> listarInscritos(Long turnoId, Long usuarioId) {
        acesso.exigirParticipante(acesso.carregar(turnoId), usuarioId);

        return inscricaoRepo.findByTurnoId(turnoId).stream()
                .filter(i -> i.getStatus() != StatusInscricao.CANCELADO)
                .map(i -> {
                    Map<String, Object> m = new HashMap<>();
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
