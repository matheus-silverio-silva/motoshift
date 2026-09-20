package com.motoshift.service;

import com.motoshift.dto.NotaFiscalPendenteResponse;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Emissão da nota fiscal de serviço de um turno.
 *
 * <p><b>O que é e o que não é.</b> A nota emitida aqui é um documento interno
 * da plataforma, com a estrutura de uma NFS-e: prestador, tomador, descrição
 * do serviço, base de cálculo, tributos e valor líquido. Não há transmissão à
 * prefeitura, RPS nem assinatura digital — a integração com o provedor
 * municipal entraria exatamente neste serviço, preservando o modelo de dados.
 *
 * <p><b>Os dois casos.</b> Entregador e lojista emitem pela mesma rota. O
 * documento é sempre o mesmo — o entregador presta, o lojista toma — mas
 * qualquer um dos dois pode disparar a emissão e os dois passam a ver a nota
 * na lista, cada um do seu lado. Não existe "nota do lojista" separada: uma
 * segunda nota, em sentido contrário, documentaria um serviço que não houve.
 *
 * <p><b>Tributos.</b> Dois, e propositalmente poucos: ISS (municipal, sobre o
 * serviço) e IRRF (retenção na fonte). Alíquotas configuráveis, com valores de
 * exemplo. Eles existem para mostrar a mecânica — base de cálculo, alíquota,
 * retenção, líquido —, não para servir de apuração fiscal.
 */
@Service
public class NotaFiscalService {

    /** Série única: não há talão por filial neste MVP. */
    private static final String SERIE = "A1";

    private final NotaFiscalRepository notaRepo;
    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final NotificacaoService notificacoes;

    /** ISS de 5% — teto do que os municípios podem cobrar (LC 116/2003). */
    @Value("${motoshift.nf.iss-aliquota:0.05}")
    private BigDecimal issAliquota;

    /** IRRF de 1,5%, a retenção usual sobre serviços de transporte. */
    @Value("${motoshift.nf.irrf-aliquota:0.015}")
    private BigDecimal irrfAliquota;

    public NotaFiscalService(NotaFiscalRepository notaRepo,
                             TurnoRepository turnoRepo,
                             TurnoInscricaoRepository inscricaoRepo,
                             UsuarioRepository usuarioRepo,
                             NotificacaoService notificacoes) {
        this.notaRepo = notaRepo;
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.notificacoes = notificacoes;
    }

    // ── Emissão ─────────────────────────────────────────────────────────────

    /**
     * Emite (ou devolve, se já existir) a nota do par turno + entregador.
     *
     * Idempotente de propósito: os dois lados veem o mesmo botão, e dois
     * cliques simultâneos não podem gerar dois documentos para o mesmo
     * serviço. Quem chama sabe se criou pelo {@code criada} do resultado.
     */
    @Transactional
    public Emissao emitir(Long turnoId, Long prestadorId, Long solicitanteId) {
        Turno turno = turnoRepo.findById(turnoId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Turno não encontrado."));

        Long prestador = resolverPrestador(turno, prestadorId, solicitanteId);
        exigirParticipante(turno, prestador, solicitanteId);

        // A nota documenta um serviço prestado: antes de o turno terminar não
        // há o que declarar. O pagamento não entra na condição — nota fiscal e
        // quitação são eventos diferentes, e amarrá-los impediria de emitir a
        // nota de um serviço feito e ainda não pago, que é o caso comum.
        if (turno.getStatus() != StatusTurno.FINALIZADO) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A nota fiscal só pode ser emitida depois que o turno for finalizado.");
        }

        Optional<NotaFiscal> existente =
                notaRepo.findByTurnoIdAndPrestadorId(turnoId, prestador);
        if (existente.isPresent()) {
            return new Emissao(montar(existente.get(), solicitanteId), false);
        }

        NotaFiscal nota = montarNota(turno, prestador, solicitanteId);
        NotaFiscal salva = notaRepo.save(nota);

        avisarAsPartes(salva, turno, solicitanteId);
        return new Emissao(montar(salva, solicitanteId), true);
    }

    private NotaFiscal montarNota(Turno turno, Long prestadorId, Long solicitanteId) {
        BigDecimal base = emReais(turno.getValorEstimado());
        BigDecimal iss = base.multiply(issAliquota).setScale(2, RoundingMode.HALF_UP);
        BigDecimal irrf = base.multiply(irrfAliquota).setScale(2, RoundingMode.HALF_UP);

        NotaFiscal n = new NotaFiscal();
        n.setTurnoId(turno.getId());
        n.setPrestadorId(prestadorId);
        n.setTomadorId(turno.getLojistId());
        n.setEmitidaPorId(solicitanteId);
        n.setNumero(proximoNumero(prestadorId));
        n.setSerie(SERIE);
        n.setDescricaoServico(descricaoDoServico(turno));
        n.setValorServico(base);
        n.setIssAliquota(issAliquota);
        n.setIssValor(iss);
        n.setIrrfAliquota(irrfAliquota);
        n.setIrrfValor(irrf);
        n.setValorLiquido(base.subtract(iss).subtract(irrf));
        n.setEmitidaEm(LocalDateTime.now());
        n.setCodigoVerificacao(codigoDeVerificacao(turno.getId(), prestadorId, base));
        return n;
    }

    /**
     * Próximo sequencial do prestador.
     *
     * <p>Lê o máximo e soma um, dentro da transação. Duas emissões realmente
     * simultâneas do mesmo entregador poderiam calcular o mesmo número — o que
     * não gera documento duplicado, porque a unicidade que importa é
     * (turno, prestador) e essa está no banco. Numeração à prova de corrida
     * pede uma sequence por emitente, que é assunto da integração fiscal real.
     */
    private int proximoNumero(Long prestadorId) {
        Integer ultimo = notaRepo.ultimoNumeroDoPrestador(prestadorId);
        return ultimo == null ? 1 : ultimo + 1;
    }

    private String descricaoDoServico(Turno turno) {
        String regiao = turno.getRegiao() == null || turno.getRegiao().isBlank()
                ? "região não informada"
                : turno.getRegiao();
        return "Serviço de entrega em turno agendado — " + turno.getTitulo()
                + " (" + regiao + ").";
    }

    /**
     * Código de verificação derivado dos dados da própria nota: os mesmos
     * dados produzem sempre o mesmo código, e ele não depende do id gerado
     * pelo banco.
     */
    private String codigoDeVerificacao(Long turnoId, Long prestadorId, BigDecimal valor) {
        String semente = turnoId + ":" + prestadorId + ":" + valor.toPlainString();
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest(semente.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 4; i++) {
                sb.append(String.format("%02X", hash[i]));
            }
            return sb.substring(0, 4) + "-" + sb.substring(4, 8);
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 é obrigatório em toda JVM; se faltar, o ambiente está quebrado.
            throw new IllegalStateException("SHA-256 indisponível nesta JVM", e);
        }
    }

    private void avisarAsPartes(NotaFiscal nota, Turno turno, Long solicitanteId) {
        String titulo = "Nota fiscal emitida";
        String mensagem = "A NFS-e nº " + nota.getNumero() + " do turno \""
                + turno.getTitulo() + "\" foi emitida.";
        // Só o outro lado é notificado: quem clicou acabou de ver o resultado.
        Long outro = solicitanteId.equals(nota.getPrestadorId())
                ? nota.getTomadorId()
                : nota.getPrestadorId();
        notificacoes.criar(outro, "nota_fiscal_emitida", titulo, mensagem,
                "nota_fiscal", nota.getId());
    }

    // ── Cancelamento ────────────────────────────────────────────────────────

    /** Só o prestador cancela — é dele o documento. */
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
        List<NotaFiscal> notas = notaRepo.findDoUsuario(usuarioId);
        Map<Long, Usuario> pessoas = carregarPessoas(notas);
        Map<Long, Turno> turnos = carregarTurnos(notas);

        List<NotaFiscalResponse> saida = new ArrayList<>(notas.size());
        for (NotaFiscal n : notas) {
            saida.add(montar(n, usuarioId, pessoas, turnos));
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
     * Turnos finalizados que ainda não geraram nota, do ponto de vista de quem
     * pergunta. O lojista vê um item por entregador de cada turno seu; o
     * entregador vê os turnos em que trabalhou.
     *
     * <p>Três consultas no total, independentemente do número de turnos: os
     * turnos, as inscrições de todos eles e as notas que o usuário já tem.
     * Antes eram duas por turno (a nota e o nome da contraparte).
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
        // "turnoId:prestadorId" das notas que já existem para este usuário —
        // e ele está em todas as que importam aqui, como prestador ou tomador.
        Set<String> jaEmitidas = notaRepo.findDoUsuario(usuarioId).stream()
                .map(n -> n.getTurnoId() + ":" + n.getPrestadorId())
                .collect(Collectors.toSet());

        List<NotaFiscalPendenteResponse> saida = new ArrayList<>();
        Map<Long, String> nomes = nomesDe(turnos, prestadores, ehLojista);

        for (Turno t : turnos) {
            for (Long prestador : prestadores.getOrDefault(t.getId(), List.of())) {
                if (jaEmitidas.contains(t.getId() + ":" + prestador)) continue;

                Long contraparte = ehLojista ? prestador : t.getLojistId();
                saida.add(new NotaFiscalPendenteResponse(
                        t.getId(),
                        prestador,
                        t.getTitulo(),
                        t.getDataInicio(),
                        emReais(t.getValorEstimado()),
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
     * <p>Inscrição CANCELADA fica de fora; ACEITO e FINALIZADO entram. Filtrar
     * só por ACEITO, como era, escondia justamente os turnos que interessam:
     * ao finalizar, a inscrição vira FINALIZADO, e o lojista voltava a ver só o
     * entregador principal do turno.
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

    /**
     * Turnos em que o entregador trabalhou: os que ele tem como principal e os
     * que ocupa por inscrição não cancelada (vaga extra de turno multi-vaga),
     * numa consulta só.
     */
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

    private NotaFiscalResponse montar(NotaFiscal n, Long solicitanteId) {
        return montar(n, solicitanteId,
                carregarPessoas(List.of(n)), carregarTurnos(List.of(n)));
    }

    private NotaFiscalResponse montar(NotaFiscal n, Long solicitanteId,
                                      Map<Long, Usuario> pessoas,
                                      Map<Long, Turno> turnos) {
        Usuario prestador = pessoas.get(n.getPrestadorId());
        Usuario tomador = pessoas.get(n.getTomadorId());
        Turno turno = turnos.get(n.getTurnoId());

        return NotaFiscalResponse.from(n,
                prestador == null ? "Entregador" : prestador.getNome(),
                prestador == null ? null : prestador.getDocumentoFederal(),
                tomador == null ? "Lojista" : tomador.getNome(),
                tomador == null ? null : tomador.getDocumentoFederal(),
                turno == null ? n.getEmitidaEm() : turno.getDataInicio(),
                solicitanteId);
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

    private Map<Long, Turno> carregarTurnos(List<NotaFiscal> notas) {
        Set<Long> ids = new HashSet<>();
        for (NotaFiscal n : notas) {
            ids.add(n.getTurnoId());
        }
        Map<Long, Turno> mapa = new HashMap<>();
        for (Turno t : turnoRepo.findAllById(ids)) {
            mapa.put(t.getId(), t);
        }
        return mapa;
    }

    /**
     * Duas casas decimais, como todo valor que sai daqui para o app. O
     * {@code CarteiraResponse} faz o mesmo com os saldos.
     */
    private BigDecimal emReais(BigDecimal valor) {
        return valor == null
                ? BigDecimal.ZERO.setScale(2)
                : valor.setScale(2, RoundingMode.HALF_UP);
    }

    /** Resultado da emissão: a nota e se ela nasceu agora ou já existia. */
    public record Emissao(NotaFiscalResponse nota, boolean criada) {}
}
