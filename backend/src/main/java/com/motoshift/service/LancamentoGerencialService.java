package com.motoshift.service;

import com.motoshift.dto.CategoriaResponse;
import com.motoshift.dto.LancamentoGerencialRequest;
import com.motoshift.dto.LancamentoGerencialResponse;
import com.motoshift.entity.CategoriaLancamento;
import com.motoshift.entity.LancamentoGerencial;
import com.motoshift.entity.Turno;
import com.motoshift.repository.LancamentoGerencialRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * Os custos e as receitas que o usuário informa à mão (RF13 / SCRUM-47).
 *
 * <p><b>Este serviço não conhece o ledger, e é assim que tem de ser.</b> Não
 * há {@code LedgerService} entre as dependências: criar, editar ou apagar um
 * lançamento gerencial não toca em saldo nem em extrato — ver o comentário de
 * {@link LancamentoGerencial}. Há um teste que confere isso
 * ({@code LancamentosGerenciaisForaDoLedgerTest}).
 *
 * <p><b>De quem é.</b> Só o dono vê e mexe. O lançamento de outra pessoa
 * responde 404, igual a um id que não existe: um 403 confirmaria que o
 * lançamento existe e é de alguém.
 *
 * <p><b>O que conta num período.</b> A regra mora em {@link #doPeriodo}, e a
 * DRE a lê daqui: o lançamento avulso conta se a data cai no período; o
 * recorrente, uma vez por ocorrência ({@link Recorrencia}). E nenhum dos dois
 * conta além de hoje — é regime de caixa: a conta que vence no dia 20 ainda
 * não foi paga no dia 7.
 *
 * <p><b>Data de pagamento é até hoje (SCRUM-49).</b> Pelo mesmo regime de
 * caixa, um lançamento não pode nascer com data futura: ele seria salvo e
 * sumiria — a lista só mostra o que já conta, e não havia mais como editá-lo
 * ou excluí-lo. O "até quando" de um recorrente pode ficar no futuro.
 *
 * <p><b>Editar um recorrente sem reescrever o passado (SCRUM-49).</b> Um
 * recorrente é uma regra, não uma linha por mês: trocar o valor do seguro
 * mudava todos os meses anteriores. Com {@code aplicarAPartirDe} no
 * {@code PUT}, a regra antiga é encerrada no dia anterior e nasce uma nova,
 * com os dados novos, na primeira ocorrência a partir dessa data — ver
 * {@link #atualizar}.
 */
@Service
public class LancamentoGerencialService {

    private final LancamentoGerencialRepository repo;
    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;

    public LancamentoGerencialService(LancamentoGerencialRepository repo,
                                      TurnoRepository turnoRepo,
                                      TurnoInscricaoRepository inscricaoRepo) {
        this.repo = repo;
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
    }

    /** Um lançamento e quantas vezes ele aconteceu no período (sempre ≥ 1). */
    public record Ocorrido(LancamentoGerencial lancamento, int vezes) {}

    // ── Leitura ───────────────────────────────────────────────────────────

    /**
     * O que aconteceu em [inicio, fim] — e só até hoje.
     *
     * <p>É a única definição de "lançamento do período". A lista da tela e a
     * DRE saem as duas daqui, e por isso somam o mesmo.
     */
    @Transactional(readOnly = true)
    public List<Ocorrido> doPeriodo(Long usuarioId, LocalDate inicio, LocalDate fim) {
        LocalDate hoje = LocalDate.now();
        LocalDate ate = fim.isAfter(hoje) ? hoje : fim;
        List<Ocorrido> ocorridos = new ArrayList<>();
        if (ate.isBefore(inicio)) return ocorridos;

        for (LancamentoGerencial l : repo.candidatosNoPeriodo(usuarioId, inicio, ate)) {
            // O avulso já veio filtrado pela data; o recorrente está em vigor,
            // mas só conta se o dia do mês cair dentro do período.
            int vezes = l.isRecorrente()
                    ? Recorrencia.vezes(l.getData(), l.getRecorrenteAte(), inicio, ate)
                    : 1;
            if (vezes > 0) ocorridos.add(new Ocorrido(l, vezes));
        }
        return ocorridos;
    }

    /**
     * A lista da tela: o que conta no período e, à frente, o que ainda vai
     * começar.
     *
     * <p>"O que ainda vai começar" são os lançamentos com data depois de hoje:
     * a regra nova de um recorrente editado "a partir deste mês", quando o dia
     * dele ainda não chegou, e o que foi gravado com data futura antes de isso
     * ser recusado. Não contam em período nenhum (zero ocorrências, valor
     * zero no período — a DRE continua somando o mesmo que a lista), mas têm
     * de aparecer em algum lugar para poderem ser conferidos, corrigidos ou
     * excluídos. Entram em todo período que chega até hoje.
     */
    @Transactional(readOnly = true)
    public List<LancamentoGerencialResponse> listar(Long usuarioId, LocalDate inicio, LocalDate fim) {
        Periodo p = Periodo.de(inicio, fim);
        LocalDate hoje = LocalDate.now();
        List<LancamentoGerencialResponse> lista = new ArrayList<>();
        if (!p.dataFim().isBefore(hoje)) {
            for (LancamentoGerencial l : repo.findByUsuarioIdAndDataAfterOrderByDataDescIdDesc(usuarioId, hoje)) {
                lista.add(LancamentoGerencialResponse.de(l, 0));
            }
        }
        for (Ocorrido o : doPeriodo(usuarioId, p.dataInicio(), p.dataFim())) {
            lista.add(LancamentoGerencialResponse.de(o.lancamento(), o.vezes()));
        }
        return lista;
    }

    /** As categorias que o papel pode lançar, na ordem da DRE dele. */
    public List<CategoriaResponse> categorias(String papel) {
        return CategoriaLancamento.doPapel(papel).stream().map(CategoriaResponse::de).toList();
    }

    // ── Escrita ───────────────────────────────────────────────────────────

    @Transactional
    public LancamentoGerencialResponse criar(Long usuarioId, String papel,
                                             LancamentoGerencialRequest req) {
        LancamentoGerencial l = new LancamentoGerencial(usuarioId);
        preencher(l, usuarioId, papel, req);
        return LancamentoGerencialResponse.de(repo.save(l));
    }

    /**
     * Edita um lançamento.
     *
     * <p>Sem {@code aplicarAPartirDe}, a edição corrige o lançamento como ele
     * é — num recorrente, o histórico inteiro.
     *
     * <p>Com {@code aplicarAPartirDe}, num recorrente que já aconteceu antes
     * dessa data, o passado fica como está: o lançamento antigo passa a valer
     * só até o dia anterior ({@code recorrenteAte}) e um novo é criado com os
     * dados da requisição, começando na primeira ocorrência a partir da data.
     * Os dois na mesma transação; a resposta é o novo. Se nada aconteceu antes
     * da data, não há passado a preservar, e a edição é a comum.
     */
    @Transactional
    public LancamentoGerencialResponse atualizar(Long id, Long usuarioId, String papel,
                                                 LancamentoGerencialRequest req) {
        LancamentoGerencial l = doDono(id, usuarioId);
        LocalDate aPartirDe = req.getAplicarAPartirDe();
        if (aPartirDe != null) {
            if (!l.isRecorrente() || !req.isRecorrente()) {
                throw invalido("\"Aplicar a partir de\" só vale para lançamento que se repete todo mês. "
                        + "Para encerrar a recorrência, informe até quando ela vale.");
            }
            if (aPartirDe.isAfter(LocalDate.now())) {
                throw invalido("Informe uma data até hoje para aplicar a mudança.");
            }
            if (aPartirDe.isAfter(l.getData())) {
                return LancamentoGerencialResponse.de(aplicarDaliEmDiante(l, usuarioId, papel, req, aPartirDe));
            }
        }
        preencher(l, usuarioId, papel, req);
        return LancamentoGerencialResponse.de(repo.save(l));
    }

    /**
     * Encerra {@code antigo} na véspera de {@code aPartirDe} e cria o
     * lançamento que vale dali em diante.
     *
     * <p>O novo começa na primeira ocorrência em {@code aPartirDe} ou depois,
     * no dia do mês que a requisição traz. Num mês mais curto que esse dia, a
     * primeira ocorrência cai no último dia do mês — e é esse o dia que a
     * regra nova passa a seguir.
     */
    private LancamentoGerencial aplicarDaliEmDiante(LancamentoGerencial antigo, Long usuarioId,
                                                    String papel, LancamentoGerencialRequest req,
                                                    LocalDate aPartirDe) {
        LancamentoGerencial novo = new LancamentoGerencial(usuarioId);
        preencher(novo, usuarioId, papel, req);

        LocalDate inicio = Recorrencia.primeiraAPartirDe(req.getData().getDayOfMonth(), aPartirDe);
        if (novo.getRecorrenteAte() != null && novo.getRecorrenteAte().isBefore(inicio)) {
            throw invalido("A recorrência termina antes de " + inicio.format(DATA)
                    + ": não há meses seguintes para aplicar a mudança.");
        }
        novo.setData(inicio);

        // Encerrar, nunca estender: se a regra antiga já acabava antes, fica.
        LocalDate vespera = aPartirDe.minusDays(1);
        if (antigo.getRecorrenteAte() == null || antigo.getRecorrenteAte().isAfter(vespera)) {
            antigo.setRecorrenteAte(vespera);
        }
        repo.save(antigo);
        return repo.save(novo);
    }

    @Transactional
    public void excluir(Long id, Long usuarioId) {
        repo.delete(doDono(id, usuarioId));
    }

    private LancamentoGerencial doDono(Long id, Long usuarioId) {
        return repo.findByIdAndUsuarioId(id, usuarioId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Lançamento não encontrado."));
    }

    private void preencher(LancamentoGerencial l, Long usuarioId, String papel,
                           LancamentoGerencialRequest req) {
        CategoriaLancamento categoria = categoriaDoPapel(req.getCategoria(), papel);

        if (req.getValor() == null || req.getValor().signum() <= 0) {
            throw invalido("O valor deve ser maior que zero.");
        }
        if (req.getData() == null) {
            throw invalido("Informe a data.");
        }
        if (req.getData().getYear() < 2000 || req.getData().getYear() > 2100) {
            throw invalido("Data fora do intervalo aceito.");
        }
        if (req.getData().isAfter(LocalDate.now())) {
            throw invalido(DATA_FUTURA);
        }
        if (req.getRecorrenteAte() != null) {
            if (!req.isRecorrente()) {
                throw invalido("\"Até quando\" só vale para lançamento que se repete todo mês.");
            }
            if (req.getRecorrenteAte().isBefore(req.getData())) {
                throw invalido("A recorrência não pode terminar antes de começar.");
            }
        }
        if (req.getKm() != null && req.getKm().signum() <= 0) {
            throw invalido("Os quilômetros devem ser maiores que zero.");
        }
        if (req.getTurnoId() != null) {
            exigirParticipacao(req.getTurnoId(), usuarioId, papel);
        }

        String descricao = req.getDescricao() == null ? null : req.getDescricao().trim();

        l.setCategoria(categoria);
        l.setValor(req.getValor());
        l.setData(req.getData());
        l.setRecorrente(req.isRecorrente());
        l.setRecorrenteAte(req.getRecorrenteAte());
        l.setTurnoId(req.getTurnoId());
        l.setKm(req.getKm());
        l.setDescricao(descricao == null || descricao.isEmpty() ? null : descricao);
    }

    /**
     * A categoria, se existir e for do papel de quem lança. Combustível é de
     * quem roda; taxa de entrega cobrada, de quem vende. Aceitar a troca
     * poria um custo de entregador na DRE de uma loja, numa linha que ela nem
     * tem.
     */
    private static CategoriaLancamento categoriaDoPapel(String valor, String papel) {
        CategoriaLancamento categoria;
        try {
            categoria = CategoriaLancamento.de(valor);
        } catch (IllegalArgumentException e) {
            categoria = null;
        }
        if (categoria == null) {
            throw invalido("Categoria desconhecida.");
        }
        if (!categoria.ehDoPapel(papel)) {
            throw invalido("A categoria \"" + categoria.getRotulo() + "\" não vale para o perfil "
                    + papel + ".");
        }
        return categoria;
    }

    /**
     * O turno tem de ser um de que o usuário participou: o lojista que o
     * publicou, ou o entregador que fez check-in nele. A mensagem é uma só
     * para "não existe" e "não é seu" — pelo mesmo motivo do 404 do
     * lançamento.
     */
    private void exigirParticipacao(Long turnoId, Long usuarioId, String papel) {
        Turno turno = turnoRepo.findById(turnoId).orElse(null);
        boolean participou = turno != null && ("lojista".equals(papel)
                ? usuarioId.equals(turno.getLojistId())
                : inscricaoRepo.findByTurnoIdAndMotoboyId(turnoId, usuarioId)
                        .map(i -> i.getCheckinEm() != null)
                        .orElse(false));
        if (!participou) {
            throw invalido("Informe um turno de que você participou.");
        }
    }

    /** A mensagem do 400 para data de pagamento depois de hoje. */
    public static final String DATA_FUTURA = "No regime de caixa, o lançamento entra no dia em que "
            + "foi pago. Informe uma data até hoje.";

    private static final DateTimeFormatter DATA = DateTimeFormatter.ofPattern("dd/MM/yyyy");

    private static ResponseStatusException invalido(String mensagem) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, mensagem);
    }
}
