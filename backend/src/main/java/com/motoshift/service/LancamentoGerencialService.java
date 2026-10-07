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

    @Transactional(readOnly = true)
    public List<LancamentoGerencialResponse> listar(Long usuarioId, LocalDate inicio, LocalDate fim) {
        Periodo p = Periodo.de(inicio, fim);
        return doPeriodo(usuarioId, p.dataInicio(), p.dataFim()).stream()
                .map(o -> LancamentoGerencialResponse.de(o.lancamento(), o.vezes()))
                .toList();
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

    @Transactional
    public LancamentoGerencialResponse atualizar(Long id, Long usuarioId, String papel,
                                                 LancamentoGerencialRequest req) {
        LancamentoGerencial l = doDono(id, usuarioId);
        preencher(l, usuarioId, papel, req);
        return LancamentoGerencialResponse.de(repo.save(l));
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

    private static ResponseStatusException invalido(String mensagem) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, mensagem);
    }
}
