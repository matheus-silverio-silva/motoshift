package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.ledger.LedgerService;
import com.motoshift.service.ledger.Movimento.MotivoLiberacao;
import com.motoshift.util.GeoUtils;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
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

    private static final DateTimeFormatter HORA = DateTimeFormatter.ofPattern("HH:mm");
    private static final DateTimeFormatter DIA = DateTimeFormatter.ofPattern("dd/MM");

    private final TurnoRepository turnoRepo;
    private final UsuarioRepository usuarioRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;
    private final PagamentoTurnoService pagamentos;
    private final CarteiraService carteiras;
    private final TurnoMapper mapper;
    private final TurnoAcesso acesso;
    private final FavoritoService favoritos;

    public TurnoService(TurnoRepository turnoRepo,
                        UsuarioRepository usuarioRepo,
                        TurnoInscricaoRepository inscricaoRepo,
                        NotificacaoService notificacoes,
                        PagamentoTurnoService pagamentos,
                        CarteiraService carteiras,
                        TurnoMapper mapper,
                        TurnoAcesso acesso,
                        FavoritoService favoritos) {
        this.turnoRepo = turnoRepo;
        this.usuarioRepo = usuarioRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
        this.pagamentos = pagamentos;
        this.carteiras = carteiras;
        this.mapper = mapper;
        this.acesso = acesso;
        this.favoritos = favoritos;
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

        // O turno precisa existir antes da reserva: a chave de idempotencia do
        // lancamento e "reserva:turno:{id}", e o id so existe depois do save.
        Turno salvo = turnoRepo.save(t);
        exigirSaldoParaPublicar(salvo, lojistaId);
        pagamentos.reservar(salvo);

        // Os entregadores favoritos da loja ficam sabendo (V18). Na mesma
        // transação: se a reserva falhar, ninguém é avisado de turno que não
        // existe.
        favoritos.avisarFavoritos(salvo, LocalDate.now());

        return mapper.toResponse(salvo);
    }

    /**
     * Barra a publicacao sem lastro, dizendo quanto falta.
     *
     * <p>O {@link com.motoshift.service.ledger.LedgerService} ja recusaria o
     * movimento — mas com a mensagem generica de quem so ve um saldo e um
     * delta. Aqui ha contexto: o custo, o quanto o lojista tem e a conta entre
     * os dois. "Faltam R$ 160,00" e acionavel; "saldo insuficiente" manda a
     * pessoa adivinhar quanto recarregar.
     *
     * <p>422 e nao 400: o pedido esta bem formado e foi entendido: o que
     * impede e o estado da carteira.
     */
    private void exigirSaldoParaPublicar(Turno turno, Long lojistaId) {
        BigDecimal custo = PagamentoTurnoService.custoTotal(turno);
        BigDecimal disponivel = carteiras.obterOuCriar(lojistaId).getSaldoDisponivel();
        if (disponivel.compareTo(custo) >= 0) return;

        String detalhe = turno.getVagas() > 1
                ? " (" + LedgerService.emReais(turno.getValorEstimado())
                        + " × " + turno.getVagas() + " vagas)"
                : "";

        throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                "Saldo insuficiente para publicar o turno. Ele custa "
                        + LedgerService.emReais(custo) + detalhe
                        + ", você tem " + LedgerService.emReais(disponivel)
                        + " disponível. Faltam " + LedgerService.emReais(custo.subtract(disponivel))
                        + " — adicione saldo para publicar.");
    }

    // RF05 — Aceitar turno (com vagas): cada motoboy que aceita vira uma inscrição.
    // O turno permanece ABERTO enquanto houver vagas; fecha (ACEITO) ao lotar.
    @Transactional
    public TurnoResponse aceitar(Long turnoId, Long motoboyId) {
        Turno turno = acesso.carregar(turnoId);

        if (turno.getStatus() != StatusTurno.ABERTO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno não está disponível para aceite.");
        }

        // Anti-duplicação: mesmo motoboy não pode aceitar o mesmo turno duas vezes.
        if (inscricaoRepo.existsByTurnoIdAndMotoboyIdAndStatus(turnoId, motoboyId, StatusInscricao.ACEITO)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já aceitou este turno.");
        }

        // Capacidade: respeita o número de vagas do turno.
        int vagas = turno.getVagas();
        long ocupadas = inscricaoRepo.countByTurnoIdAndStatus(turnoId, StatusInscricao.ACEITO);
        if (ocupadas >= vagas) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Todas as vagas deste turno já foram preenchidas.");
        }

        // Conflito de agenda considerando TODAS as inscrições ativas do motoboy
        // — inclusive em turno que continua ABERTO por ter vaga sobrando, que
        // o antigo findConflitos não pegava.
        if (turnoRepo.existeConflitoDeAgenda(motoboyId, turnoId,
                turno.getDataInicio(), turno.getDataFim())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já possui um turno agendado neste horário.");
        }

        // Registra a inscrição.
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(turnoId);
        ins.setMotoboyId(motoboyId);
        ins.setStatus(StatusInscricao.ACEITO);
        inscricaoRepo.save(ins);
        ocupadas++;

        // Primeiro inscrito vira o motoboy "principal" (compatibilidade com os
        // fluxos atuais de finalização/pagamento).
        if (turno.getMotoboyId() == null) {
            turno.setMotoboyId(motoboyId);
        }
        // Fecha o turno quando todas as vagas forem preenchidas.
        if (ocupadas >= vagas) {
            turno.setStatus(StatusTurno.ACEITO);
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
     * RF06 — Finalizar turno: paga, ali mesmo, quem trabalhou.
     *
     * <p>A liquidacao acontece nesta transacao, nao depois: ou o turno fica
     * FINALIZADO e todo mundo esta pago, ou nada disso aconteceu. O estado
     * intermediario — "finalizado, aguardando pagamento" — deixou de existir, e
     * com ele a dupla confirmacao que o sustentava.
     *
     * <p><b>Os dois participantes continuam podendo finalizar</b>: o dinheiro
     * ja estava reservado desde a publicacao, entao finalizar nao cria
     * compromisso nenhum — so transfere o que o lojista comprometeu.
     *
     * <p><b>Mas finalizar so paga quem trabalhou.</b> Ate aqui bastava ser
     * participante: o entregador aceitava um turno de amanha, tocava
     * "Finalizar" e recebia na hora. Duas travas fecham isso:
     * <ul>
     *   <li>o turno precisa ter comecado ({@code agora >= dataInicio});</li>
     *   <li>alguem precisa ter feito check-in.</li>
     * </ul>
     * E na liquidacao so recebe a inscricao com check-in. A aceita sem
     * check-in vira {@link StatusInscricao#FALTOU} — sem pagamento e, por
     * enquanto, sem penalidade de score — e a parte dela volta ao lojista
     * junto com a das vagas vazias (liberacao_reserva, motivo "sobra").
     */
    @Transactional
    public TurnoResponse finalizar(Long turnoId, Long usuarioId) {
        Turno turno = acesso.carregar(turnoId);
        acesso.exigirParticipante(turno, usuarioId);

        if (turno.getStatus() == StatusTurno.FINALIZADO || turno.getStatus() == StatusTurno.CANCELADO
                || turno.getStatus() == StatusTurno.EXPIRADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já encerrado.");
        }
        exigirQueTenhaComecado(turno, LocalDateTime.now());
        if (!inscricaoRepo.existsByTurnoIdAndStatusAndCheckinEmIsNotNull(
                turnoId, StatusInscricao.ACEITO)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Ninguém fez check-in neste turno — cancele-o para devolver a reserva.");
        }

        turno.setStatus(StatusTurno.FINALIZADO);

        PagamentoTurnoService.Fechamento fechamento = pagamentos.fecharInscricoes(turno);
        pagamentos.liquidar(turno, fechamento.presentes(), fechamento.faltosos().size());

        // O "principal" do turno e quem as telas e os relatorios do entregador
        // leem. Se ele faltou, passa a ser o primeiro que trabalhou — senao o
        // turno finalizado e pago apareceria no historico de quem nao veio.
        List<Long> pagos = fechamento.presentes().stream().map(TurnoInscricao::getMotoboyId).toList();
        if (!pagos.isEmpty() && !pagos.contains(turno.getMotoboyId())) {
            turno.setMotoboyId(pagos.get(0));
        }

        // PAGO, e nao PENDENTE: quando esta linha roda, o dinheiro ja mudou de
        // carteira dentro desta mesma transacao.
        turno.setPagamentoStatus(StatusPagamento.PAGO);
        turnoRepo.save(turno);

        List<Long> avaliam = new ArrayList<>(pagos);
        avaliam.add(0, turno.getLojistId());
        for (Long destinatario : avaliam) {
            notificacoes.criar(destinatario, "avaliacao_pendente",
                    "Turno finalizado",
                    "O turno \"" + turno.getTitulo() + "\" foi finalizado e o pagamento "
                            + "foi liquidado. Avalie a outra parte.",
                    "turno", turno.getId());
        }
        // Quem faltou fica sabendo — e sabendo por que nao recebeu.
        for (TurnoInscricao falta : fechamento.faltosos()) {
            notificacoes.criar(falta.getMotoboyId(), "turno_falta",
                    "Turno finalizado sem o seu check-in",
                    "O turno \"" + turno.getTitulo() + "\" foi finalizado e você não fez "
                            + "check-in: ficou registrado como falta, sem pagamento.",
                    "turno", turno.getId());
        }

        return mapper.toResponse(turno);
    }

    /**
     * 409 com a hora a partir da qual finalizar passa a valer.
     *
     * <p>"O turno ainda não começou" sozinho manda a pessoa adivinhar quando
     * tentar de novo; com a hora, a mensagem e acionavel. O dia entra quando
     * o turno nao e de hoje.
     */
    private static void exigirQueTenhaComecado(Turno turno, LocalDateTime agora) {
        LocalDateTime inicio = turno.getDataInicio();
        if (!agora.isBefore(inicio)) return;
        String quando = inicio.toLocalDate().equals(agora.toLocalDate())
                ? "depois das " + inicio.format(HORA)
                : "a partir de " + inicio.format(DIA) + ", às " + inicio.format(HORA);
        throw new ResponseStatusException(HttpStatus.CONFLICT,
                "O turno ainda não começou — finalize " + quando + ".");
    }

    // RF07 — Cancelar turno: penalidade no score se < 1h antes do início
    @Transactional
    public TurnoResponse cancelar(Long turnoId, Long usuarioId) {
        Turno turno = acesso.carregar(turnoId);
        acesso.exigirParticipante(turno, usuarioId);

        if (turno.getStatus() == StatusTurno.FINALIZADO || turno.getStatus() == StatusTurno.CANCELADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já encerrado.");
        }
        // Turno que começou não é cancelado como se não tivesse começado:
        // cancelar devolve a reserva INTEIRA ao lojista, e alguém já está
        // trabalhando. O check-in é o que diz que começou — inclusive o feito
        // antes do início, com o turno ainda ABERTO para as vagas que sobram.
        if (turno.getStatus() == StatusTurno.EM_ANDAMENTO
                || inscricaoRepo.existsByTurnoIdAndCheckinEmIsNotNull(turnoId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "O turno já começou — o entregador fez check-in. Finalize o turno para "
                            + "pagar quem trabalhou.");
        }

        boolean cancelamentoTardio = LocalDateTime.now().isAfter(
                turno.getDataInicio().minusHours(1));

        // A regra da reputação mora em Reputacao — valor inicial e penalidade
        // num lugar só, o mesmo que a análise de score usa.
        if (cancelamentoTardio && turno.getMotoboyId() != null) {
            usuarioRepo.findById(turno.getMotoboyId()).ifPresent(motoboy -> {
                motoboy.setScore(Reputacao.penalizar(motoboy.getScore()));
                usuarioRepo.save(motoboy);
            });
        }

        // Cancela também as inscrições ativas (libera as vagas ocupadas).
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdAndStatus(turnoId, StatusInscricao.ACEITO)) {
            ins.setStatus(StatusInscricao.CANCELADO);
            inscricaoRepo.save(ins);
        }

        // O dinheiro reservado volta inteiro ao disponivel do lojista. Sem
        // multa: a penalidade do cancelamento tardio e de score, logo acima, e
        // continua sendo a unica.
        pagamentos.liberarReserva(turno, MotivoLiberacao.CANCELAMENTO);

        turno.setStatus(StatusTurno.CANCELADO);
        // Quem cancelou (V19): o selo "30 dias sem cancelar" conta só o que o
        // entregador cancelou, não o que a loja cancelou com ele no turno.
        turno.setCanceladoPorId(usuarioId);
        turno.setCanceladoEm(LocalDateTime.now());
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
