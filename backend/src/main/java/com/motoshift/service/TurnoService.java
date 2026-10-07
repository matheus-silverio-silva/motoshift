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
 * Ciclo de vida do turno: publicar, aceitar, finalizar, cancelar (a loja) e
 * desistir da vaga (o entregador).
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
    //
    // A linha do turno fica travada do começo ao fim (carregarTravandoAsVagas):
    // contar as vagas e gravar a inscrição não é atômico, e sem a trava dois
    // entregadores entravam juntos na última vaga.
    @Transactional
    public TurnoResponse aceitar(Long turnoId, Long motoboyId) {
        Turno turno = acesso.carregarTravandoAsVagas(turnoId);

        if (turno.getStatus() != StatusTurno.ABERTO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno não está disponível para aceite.");
        }

        // Anti-duplicação: mesmo motoboy não pode aceitar o mesmo turno duas vezes.
        if (inscricaoRepo.existsByTurnoIdAndMotoboyIdAndStatus(turnoId, motoboyId, StatusInscricao.ACEITO)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já aceitou este turno.");
        }
        // Quem desistiu da vaga não a aceita de novo: a inscrição é uma por
        // pessoa e turno (uk_turno_motoboy), e é ela que guarda a desistência.
        // Sem esta recusa o INSERT esbarraria na unicidade e viraria um 500.
        if (inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, motoboyId).isPresent()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você desistiu deste turno e não pode aceitá-lo de novo.");
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

        PagamentoTurnoService.Fechamento fechamento = pagarQuemTrabalhou(turno);

        List<Long> avaliam = new ArrayList<>(pagos(fechamento));
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
     * O que finalizar faz com o turno e com o dinheiro — o mesmo para quem
     * tocou o botão ({@link #finalizar}) e para o job de finalização
     * automática ({@link #finalizarPeloSistema}). Duas finalizações com regras
     * de pagamento escritas duas vezes acabariam pagando diferente.
     *
     * <p>Quem chama já conferiu que há ao menos um check-in.
     */
    private PagamentoTurnoService.Fechamento pagarQuemTrabalhou(Turno turno) {
        turno.setStatus(StatusTurno.FINALIZADO);

        PagamentoTurnoService.Fechamento fechamento = pagamentos.fecharInscricoes(turno);
        pagamentos.liquidar(turno, fechamento.presentes(), fechamento.faltosos().size());

        // O "principal" do turno e quem as telas e os relatorios do entregador
        // leem. Se ele faltou, passa a ser o primeiro que trabalhou — senao o
        // turno finalizado e pago apareceria no historico de quem nao veio.
        List<Long> pagos = pagos(fechamento);
        if (!pagos.isEmpty() && !pagos.contains(turno.getMotoboyId())) {
            turno.setMotoboyId(pagos.get(0));
        }

        // PAGO, e nao PENDENTE: quando esta linha roda, o dinheiro ja mudou de
        // carteira dentro desta mesma transacao.
        turno.setPagamentoStatus(StatusPagamento.PAGO);
        turnoRepo.save(turno);
        return fechamento;
    }

    private static List<Long> pagos(PagamentoTurnoService.Fechamento fechamento) {
        return fechamento.presentes().stream().map(TurnoInscricao::getMotoboyId).toList();
    }

    /** O que o job de finalização automática fez com um turno. */
    public enum FinalizacaoAutomatica {
        /** Havia check-in: quem trabalhou foi pago, como em {@link #finalizar}. */
        PAGA,
        /** Ninguém fez check-in: faltas, reserva de volta e turno EXPIRADO. */
        SEM_CHECKIN,
        /** O turno já não estava mais em jogo — alguém finalizou ou cancelou antes. */
        IGNORADA
    }

    /**
     * Finalização pelo SISTEMA — o turno que terminou e ninguém finalizou.
     *
     * <p>Chamado só pelo job ({@code TurnoExpiracaoService.finalizarTurnosEsquecidos}),
     * depois que o prazo de {@code motoshift.finalizacao.automatica-horas}
     * passou do fim do turno. Sem ele o dinheiro ficava reservado para sempre:
     * o job só cobrava a finalização por notificação, e bastava as duas partes
     * esquecerem o turno.
     *
     * <p><b>Pula {@code exigirParticipante}, de propósito.</b> Aquela trava
     * responde "esta pessoa pode mexer neste turno?", e aqui não há pessoa:
     * quem chama é um job do próprio backend, e este método não é alcançável
     * por rota nenhuma. As regras de DINHEIRO são as mesmas de
     * {@link #finalizar} — o mesmo {@link #pagarQuemTrabalhou}: só recebe quem
     * fez check-in, quem aceitou e não chegou vira FALTOU e a sobra volta ao
     * lojista. A trava de "já começou" é dispensável: o turno já terminou.
     *
     * <p><b>Sem nenhum check-in</b> não há quem pagar, e finalizar não é a
     * palavra: as inscrições aceitas viram FALTOU, a reserva volta inteira
     * (motivo próprio, {@code sem_checkin}) e o turno vai para EXPIRADO — ele
     * venceu sem acontecer.
     *
     * <p>As duas partes são avisadas com {@code criarUnica}: se o job repetir
     * o turno (uma falha depois do aviso, duas instâncias), ninguém é avisado
     * duas vezes.
     *
     * @param prazoHoras o prazo que venceu — só para o texto do aviso
     */
    @Transactional
    public FinalizacaoAutomatica finalizarPeloSistema(Long turnoId, int prazoHoras) {
        Turno turno = acesso.carregar(turnoId);
        if (turno.getStatus() != StatusTurno.ACEITO && turno.getStatus() != StatusTurno.EM_ANDAMENTO) {
            return FinalizacaoAutomatica.IGNORADA;
        }
        String prazo = "há mais de " + prazoHoras + (prazoHoras == 1 ? " hora" : " horas");

        if (inscricaoRepo.existsByTurnoIdAndStatusAndCheckinEmIsNotNull(turnoId, StatusInscricao.ACEITO)) {
            PagamentoTurnoService.Fechamento fechamento = pagarQuemTrabalhou(turno);

            notificacoes.criarUnica(turno.getLojistId(), TIPO_FINALIZACAO_AUTOMATICA,
                    "Turno finalizado automaticamente",
                    "O turno \"" + turno.getTitulo() + "\" terminou " + prazo + " sem ser "
                            + "finalizado. Quem fez check-in foi pago. Avalie o entregador.",
                    "turno", turno.getId());
            for (Long pago : pagos(fechamento)) {
                notificacoes.criarUnica(pago, TIPO_FINALIZACAO_AUTOMATICA,
                        "Turno finalizado automaticamente",
                        "O turno \"" + turno.getTitulo() + "\" terminou " + prazo + " sem ser "
                                + "finalizado. O pagamento foi creditado na sua carteira. "
                                + "Avalie a loja.",
                        "turno", turno.getId());
            }
            avisarFaltas(turno, fechamento);
            return FinalizacaoAutomatica.PAGA;
        }

        // Ninguém chegou. As inscrições aceitas viram FALTOU e nada é pago.
        PagamentoTurnoService.Fechamento fechamento = pagamentos.fecharInscricoes(turno);
        pagamentos.liberarReserva(turno, MotivoLiberacao.SEM_CHECKIN);

        turno.setStatus(StatusTurno.EXPIRADO);
        turno.setExpiradoEm(LocalDateTime.now());
        // Sem ninguém que tenha trabalhado, o turno não é de entregador nenhum.
        turno.setMotoboyId(null);
        turnoRepo.save(turno);

        notificacoes.criarUnica(turno.getLojistId(), TIPO_FINALIZACAO_AUTOMATICA,
                "Turno encerrado sem check-in",
                "O turno \"" + turno.getTitulo() + "\" terminou " + prazo + " sem nenhum "
                        + "check-in e foi encerrado. A reserva voltou inteira ao seu saldo.",
                "turno", turno.getId());
        avisarFaltas(turno, fechamento);
        return FinalizacaoAutomatica.SEM_CHECKIN;
    }

    /** O tipo da notificação da finalização automática — um por pessoa e turno. */
    public static final String TIPO_FINALIZACAO_AUTOMATICA = "turno_finalizado_automaticamente";

    private void avisarFaltas(Turno turno, PagamentoTurnoService.Fechamento fechamento) {
        for (TurnoInscricao falta : fechamento.faltosos()) {
            notificacoes.criarUnica(falta.getMotoboyId(), "turno_falta",
                    "Turno encerrado sem o seu check-in",
                    "O turno \"" + turno.getTitulo() + "\" foi encerrado e você não fez "
                            + "check-in: ficou registrado como falta, sem pagamento.",
                    "turno", turno.getId());
        }
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

    /**
     * RF07 — Cancelar o turno: só o lojista que o publicou.
     *
     * <p>Derruba o turno inteiro, devolve a reserva e <b>não penaliza
     * ninguém</b>. Era um botão só para os dois lados, e a penalidade do
     * cancelamento tardio caía no primeiro inscrito fosse quem fosse que
     * tivesse cancelado: a loja cancelava a 20 minutos do início e o
     * entregador perdia 0,5 de score. Quem sai do turno por conta própria é o
     * entregador, por {@link #desistir} — e é lá que mora a penalidade.
     */
    @Transactional
    public TurnoResponse cancelar(Long turnoId, Long lojistaId) {
        Turno turno = acesso.carregar(turnoId);
        if (lojistaId == null || !lojistaId.equals(turno.getLojistId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Só o lojista que publicou o turno pode cancelá-lo. Para sair da sua vaga, "
                            + "use \"Desistir da vaga\".");
        }

        if (turno.getStatus() == StatusTurno.FINALIZADO || turno.getStatus() == StatusTurno.CANCELADO
                || turno.getStatus() == StatusTurno.EXPIRADO) {
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

        LocalDateTime agora = LocalDateTime.now();

        // Cancela também as inscrições ativas, registrando que foi a loja:
        // é o que impede este cancelamento de contar contra o entregador.
        List<Long> avisados = new ArrayList<>();
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdAndStatus(turnoId, StatusInscricao.ACEITO)) {
            ins.cancelar(lojistaId, agora);
            inscricaoRepo.save(ins);
            avisados.add(ins.getMotoboyId());
        }

        // O dinheiro reservado volta inteiro ao disponivel do lojista, sem
        // multa.
        pagamentos.liberarReserva(turno, MotivoLiberacao.CANCELAMENTO);

        turno.setStatus(StatusTurno.CANCELADO);
        turno.setCanceladoPorId(lojistaId);
        turno.setCanceladoEm(agora);
        turnoRepo.save(turno);

        // SCRUM-20: todo mundo que estava no turno precisa saber. A lista sai
        // das inscrições que estavam ativas — depois de canceladas, elas não
        // contam mais como participantes, e num turno de várias vagas só o
        // primeiro inscrito era avisado.
        notificacoes.criar(lojistaId, "turno_cancelado",
                "Turno cancelado",
                "O turno \"" + turno.getTitulo() + "\" foi cancelado e a reserva voltou "
                        + "ao seu saldo.",
                "turno", turno.getId());
        for (Long entregador : avisados) {
            notificacoes.criar(entregador, "turno_cancelado",
                    "Turno cancelado pela loja",
                    "O turno \"" + turno.getTitulo() + "\" foi cancelado pela loja. "
                            + "Isso não muda o seu score.",
                    "turno", turno.getId());
        }

        return mapper.toResponse(turno);
    }

    /**
     * RF07 — Desistir da vaga: só o entregador inscrito, e só da vaga dele.
     *
     * <p>Cancela a inscrição de quem desiste e mais nada: os colegas de um
     * turno de várias vagas continuam nele, e a reserva do lojista continua
     * bloqueada — a vaga existe, só ficou sem dono. Antes disso o entregador
     * que saía de um turno de três vagas derrubava o turno dos outros dois.
     *
     * <ul>
     *   <li>a vaga reabre: se o turno estava lotado (ACEITO) e ainda não
     *       começou, volta a ABERTO;</li>
     *   <li>se quem saiu era o "principal" do turno, o posto passa ao próximo
     *       inscrito ativo, ou fica vazio;</li>
     *   <li>a menos de {@link Reputacao#FOLGA_SEM_PENALIDADE} do início, a
     *       desistência custa {@link Reputacao#PENALIDADE_CANCELAMENTO_TARDIO}
     *       de score — a ele, e só a ele;</li>
     *   <li>depois do check-in não há desistência: o turno começou para ele,
     *       e a saída é finalizar.</li>
     * </ul>
     *
     * <p>Quem desistiu não volta para o mesmo turno ({@link #aceitar}): a
     * inscrição é a identidade de "esta pessoa neste turno", e é ela que
     * guarda a desistência.
     */
    @Transactional
    public TurnoResponse desistir(Long turnoId, Long motoboyId) {
        Turno turno = acesso.carregarTravandoAsVagas(turnoId);
        TurnoInscricao ins = inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, motoboyId)
                .filter(i -> i.getStatus() == StatusInscricao.ACEITO || i.getStatus() == StatusInscricao.FINALIZADO)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN,
                        "Você não tem vaga neste turno."));

        if (ins.getStatus() != StatusInscricao.ACEITO
                || turno.getStatus() == StatusTurno.FINALIZADO
                || turno.getStatus() == StatusTurno.CANCELADO
                || turno.getStatus() == StatusTurno.EXPIRADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Turno já encerrado.");
        }
        if (ins.getCheckinEm() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Você já fez check-in — o turno começou para você. Finalize o turno "
                            + "em vez de desistir.");
        }

        LocalDateTime agora = LocalDateTime.now();
        boolean emCimaDaHora = Reputacao.emCimaDaHora(agora, turno.getDataInicio());

        ins.cancelar(motoboyId, agora);
        inscricaoRepo.save(ins);

        // A regra da reputação mora em Reputacao — valor inicial e penalidade
        // num lugar só, o mesmo que a análise de score usa.
        if (emCimaDaHora) {
            usuarioRepo.findById(motoboyId).ifPresent(motoboy -> {
                motoboy.setScore(Reputacao.penalizar(motoboy.getScore()));
                usuarioRepo.save(motoboy);
            });
        }

        if (motoboyId.equals(turno.getMotoboyId())) {
            turno.setMotoboyId(inscricaoRepo
                    .findByTurnoIdAndStatusOrderByIdAsc(turnoId, StatusInscricao.ACEITO).stream()
                    .map(TurnoInscricao::getMotoboyId)
                    .findFirst().orElse(null));
        }
        // Turno lotado que perdeu um inscrito volta a aceitar gente — enquanto
        // não começou. Depois do início as vagas já estavam fechadas.
        boolean reabriu = turno.getStatus() == StatusTurno.ACEITO
                && agora.isBefore(turno.getDataInicio());
        if (reabriu) {
            turno.setStatus(StatusTurno.ABERTO);
        }
        turnoRepo.save(turno);

        String nome = usuarioRepo.findById(motoboyId).map(Usuario::getNome).orElse("Um entregador");
        notificacoes.criar(turno.getLojistId(), "entregador_desistiu",
                "Entregador desistiu da vaga",
                nome + " desistiu da vaga no turno \"" + turno.getTitulo() + "\"."
                        + (turno.getStatus() == StatusTurno.ABERTO
                                ? " A vaga voltou a ficar aberta." : ""),
                "turno", turno.getId());

        return mapper.toResponse(turno);
    }
}
