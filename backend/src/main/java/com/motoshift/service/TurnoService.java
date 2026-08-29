package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.util.GeoUtils;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Ciclo de vida do turno: publicar, aceitar, finalizar, cancelar.
 *
 * Este arquivo tinha 604 linhas e fazia tambem consulta, filtro geografico,
 * confirmacao de pagamento, credito em carteira e transacao. Ficou com o que e
 * de fato o ciclo de vida; o resto foi para {@link TurnoConsultaService} e
 * {@link PagamentoTurnoService}, e o que os tres compartilham esta em
 * {@link TurnoMapper} e {@link TurnoAcesso}.
 */
@Service
public class TurnoService {

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;
    private final PagamentoTurnoService pagamentos;
    private final TurnoMapper mapper;
    private final TurnoAcesso acesso;

    public TurnoService(TurnoRepository turnoRepo,
                        UsuarioRepository usuarioRepo,
                        TurnoInscricaoRepository inscricaoRepo,
                        NotificacaoService notificacoes,
                        PagamentoTurnoService pagamentos,
                        TurnoMapper mapper,
                        TurnoAcesso acesso) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
        this.pagamentos = pagamentos;
        this.mapper = mapper;
        this.acesso = acesso;
    }

    // RF04 — Criar turno: início deve ser >= agora + 2h
    @Transactional
    public TurnoResponse criar(TurnoRequest req, Long lojistaId) {
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
        // O dono sai do token, nunca do corpo: com lojistId vindo do JSON,
        // qualquer um publicava turno no nome de outra loja.
        t.setLojistId(lojistaId);
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

        return mapper.toResponse(turnoRepo.save(t));
    }

    // RF05 — Aceitar turno (com vagas): cada motoboy que aceita vira uma inscrição.
    // O turno permanece ABERTO enquanto houver vagas; fecha (ACEITO) ao lotar.
    @Transactional
    public TurnoResponse aceitar(Long turnoId, Long motoboyId) {
        Turno turno = acesso.carregar(turnoId);

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

        return mapper.toResponse(turno);
    }

    /**
     * Verifica se o motoboy já tem alguma inscrição ativa cujo turno se
     * sobrepõe ao horário do turno alvo. Cobre o cenário multi-vaga em que o
     * turno de origem ainda está ABERTO (não pego pelo antigo findConflitos).
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

    // RF06 — Finalizar turno: gera a dívida com cada entregador do turno.
    @Transactional
    public TurnoResponse finalizar(Long turnoId, Long usuarioId) {
        Turno turno = acesso.carregar(turnoId);
        acesso.exigirParticipante(turno, usuarioId);

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
            pagamentos.criarTransacaoPendente(turno, turno.getMotoboyId());
        } else {
            // Cada entregador inscrito gera sua própria transação/pagamento.
            for (TurnoInscricao ins : inscricoes) {
                ins.setStatus("finalizado");
                ins.setPagamentoStatus("pendente");
                inscricaoRepo.save(ins);
                pagamentos.criarTransacaoPendente(turno, ins.getMotoboyId());
            }
        }

        for (Long destinatario : acesso.participantes(turno)) {
            notificacoes.criar(destinatario, "avaliacao_pendente",
                    "Turno finalizado",
                    "O turno \"" + turno.getTitulo() + "\" foi finalizado. "
                            + "Confirme o pagamento e avalie a outra parte.",
                    "turno", turno.getId());
        }

        return mapper.toResponse(turno);
    }

    // RF07 — Cancelar turno: penalidade no score se < 1h antes do início
    @Transactional
    public TurnoResponse cancelar(Long turnoId, Long usuarioId) {
        Turno turno = acesso.carregar(turnoId);
        acesso.exigirParticipante(turno, usuarioId);

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
        for (Long destinatario : acesso.participantes(turno)) {
            notificacoes.criar(destinatario, "turno_cancelado",
                    "Turno cancelado",
                    "O turno \"" + turno.getTitulo() + "\" foi cancelado.",
                    "turno", turno.getId());
        }

        return mapper.toResponse(turno);
    }
}
