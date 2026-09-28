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
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

/**
 * Check-in e check-out: o horário REAL em que o entregador chegou e saiu.
 *
 * <p><b>Regras.</b>
 * <ul>
 *   <li>só o entregador inscrito e aceito no turno — nem o lojista, nem quem
 *       cancelou a inscrição;</li>
 *   <li>o check-in abre {@link #ANTECEDENCIA} antes do início e fecha no fim
 *       do turno;</li>
 *   <li>a no máximo {@code motoshift.checkin.raio-metros} (padrão 500) do
 *       ponto do turno. A trava pode ser desligada por
 *       {@code motoshift.checkin.exigir-proximidade=false} — é a apresentação
 *       feita de casa, longe de qualquer loja da massa;</li>
 *   <li>o check-out só depois do check-in.</li>
 * </ul>
 * Repetir qualquer um dos dois não muda nada: a segunda chamada devolve o
 * turno como está, sem notificar de novo. Um toque duplo no celular não pode
 * virar dois avisos para o lojista.
 *
 * <p><b>Status.</b> O primeiro check-in leva o turno de ACEITO a EM_ANDAMENTO
 * — é o que o enum esperava desde que existe. Turno ainda ABERTO (vaga
 * sobrando) só muda se o horário de início já passou; antes disso as vagas
 * continuam abertas, e quem fecha o turno na hora de começar é o job de
 * vencimento, que agora o leva direto a EM_ANDAMENTO se alguém já chegou.
 *
 * <p>Não move dinheiro: quem paga continua sendo a finalização.
 */
@Service
public class CheckinService {

    /** Quanto antes do início o check-in já vale. */
    static final Duration ANTECEDENCIA = Duration.ofMinutes(30);

    private static final DateTimeFormatter HORA = DateTimeFormatter.ofPattern("HH:mm");

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final NotificacaoService notificacoes;
    private final TurnoAcesso acesso;
    private final TurnoMapper mapper;
    private final double raioMetros;
    private final boolean exigirProximidade;

    public CheckinService(TurnoRepository turnoRepo,
                          TurnoInscricaoRepository inscricaoRepo,
                          UsuarioRepository usuarioRepo,
                          NotificacaoService notificacoes,
                          TurnoAcesso acesso,
                          TurnoMapper mapper,
                          @Value("${motoshift.checkin.raio-metros:500}") double raioMetros,
                          @Value("${motoshift.checkin.exigir-proximidade:true}") boolean exigirProximidade) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.notificacoes = notificacoes;
        this.acesso = acesso;
        this.mapper = mapper;
        this.raioMetros = raioMetros;
        this.exigirProximidade = exigirProximidade;
    }

    /** "Cheguei": grava a chegada e avisa o lojista. */
    @Transactional
    public TurnoResponse checkin(Long turnoId, Long motoboyId, Double lat, Double lng) {
        return checkin(turnoId, motoboyId, lat, lng, LocalDateTime.now());
    }

    /**
     * O mesmo, com o relógio na mão. Existe para a massa de demonstração, que
     * conta cinco meses de história pelos serviços reais: a chegada de um
     * turno do passado é conferida contra a hora DELE, com as mesmas regras.
     */
    @Transactional
    public TurnoResponse checkin(Long turnoId, Long motoboyId, Double lat, Double lng,
                                 LocalDateTime agora) {
        Turno turno = acesso.carregar(turnoId);
        TurnoInscricao ins = inscricaoAtiva(turno, motoboyId);
        if (ins.getCheckinEm() != null) return mapper.toResponse(turno);

        exigirTurnoVivo(turno);
        LocalDateTime abre = turno.getDataInicio().minus(ANTECEDENCIA);
        if (agora.isBefore(abre)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "O check-in abre 30 minutos antes do início, às " + abre.format(HORA) + ".");
        }
        if (agora.isAfter(turno.getDataFim())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "O turno já terminou às " + turno.getDataFim().format(HORA)
                            + "; não dá mais para fazer check-in.");
        }
        exigirProximidade(turno, lat, lng);

        ins.setCheckinEm(agora);
        if (GeoUtils.coordenadaValida(lat, lng)) {
            ins.setCheckinLatitude(lat);
            ins.setCheckinLongitude(lng);
        }
        inscricaoRepo.save(ins);

        // ACEITO → EM_ANDAMENTO no primeiro check-in. ABERTO só depois do
        // início: antes dele ainda pode entrar gente nas vagas que sobram.
        boolean comecou = !agora.isBefore(turno.getDataInicio());
        if (turno.getStatus() == StatusTurno.ACEITO
                || (turno.getStatus() == StatusTurno.ABERTO && comecou)) {
            turno.setStatus(StatusTurno.EM_ANDAMENTO);
            turnoRepo.save(turno);
        }

        String nome = primeiroNome(motoboyId);
        notificacoes.criar(turno.getLojistId(), "entregador_chegou",
                "Entregador chegou",
                nome + " chegou às " + agora.format(HORA) + " ("
                        + relativoAoInicio(agora, turno.getDataInicio()) + ") — \""
                        + turno.getTitulo() + "\".",
                "turno", turno.getId());

        return mapper.toResponse(turno);
    }

    /** "Encerrar turno": grava a saída. Não finaliza — finalizar é pagar. */
    @Transactional
    public TurnoResponse checkout(Long turnoId, Long motoboyId) {
        return checkout(turnoId, motoboyId, LocalDateTime.now());
    }

    /** O mesmo, com o relógio na mão — ver {@link #checkin(Long, Long, Double, Double, LocalDateTime)}. */
    @Transactional
    public TurnoResponse checkout(Long turnoId, Long motoboyId, LocalDateTime agora) {
        Turno turno = acesso.carregar(turnoId);
        TurnoInscricao ins = inscricaoAtiva(turno, motoboyId);
        if (ins.getCheckinEm() == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Faça o check-in (\"Cheguei\") antes de encerrar o turno.");
        }
        if (ins.getCheckoutEm() != null) return mapper.toResponse(turno);

        ins.setCheckoutEm(agora);
        inscricaoRepo.save(ins);

        notificacoes.criar(turno.getLojistId(), "entregador_saiu",
                "Entregador encerrou o turno",
                primeiroNome(motoboyId) + " saiu às " + agora.format(HORA) + " — \""
                        + turno.getTitulo() + "\". Finalize para liberar o pagamento.",
                "turno", turno.getId());

        return mapper.toResponse(turno);
    }

    /** "3 min antes", "no horário", "12 min depois". */
    static String relativoAoInicio(LocalDateTime chegada, LocalDateTime inicio) {
        long min = Duration.between(inicio, chegada).toMinutes();
        if (min == 0) return "no horário";
        return Math.abs(min) + " min " + (min < 0 ? "antes" : "depois");
    }

    /** "a 1,2 km" ou "a 650 m" — como a tela mostra distância. */
    static String distanciaLegivel(double km) {
        if (km < 1.0) return "a " + Math.round(km * 1000) + " m";
        return "a " + String.format(new Locale("pt", "BR"), "%.1f", km) + " km";
    }

    // ── regras ──────────────────────────────────────────────────────────────

    private TurnoInscricao inscricaoAtiva(Turno turno, Long motoboyId) {
        return inscricaoRepo.findByTurnoIdAndMotoboyId(turno.getId(), motoboyId)
                .filter(i -> i.getStatus() == StatusInscricao.ACEITO)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN,
                        "Só o entregador inscrito e aceito neste turno faz check-in e check-out."));
    }

    private static void exigirTurnoVivo(Turno turno) {
        StatusTurno s = turno.getStatus();
        if (s != StatusTurno.ABERTO && s != StatusTurno.ACEITO && s != StatusTurno.EM_ANDAMENTO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Este turno está " + s.getValor().replace('_', ' ') + "; não há check-in a fazer.");
        }
    }

    private void exigirProximidade(Turno turno, Double lat, Double lng) {
        if (!exigirProximidade) return;
        // Turno legado, sem ponto: não há contra o que medir.
        if (turno.getLatitude() == null || turno.getLongitude() == null) return;
        if (!GeoUtils.coordenadaValida(lat, lng)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Envie a sua localização para fazer o check-in.");
        }
        double km = GeoUtils.distanciaKm(lat, lng, turno.getLatitude(), turno.getLongitude());
        if (km * 1000 > raioMetros) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Você está " + distanciaLegivel(km) + " do local. O check-in é liberado a até "
                            + Math.round(raioMetros) + " m do ponto do turno.");
        }
    }

    private String primeiroNome(Long usuarioId) {
        return usuarioRepo.findById(usuarioId)
                .map(Usuario::getNome)
                .map(n -> n.trim().split("\\s+")[0])
                .orElse("O entregador");
    }
}
