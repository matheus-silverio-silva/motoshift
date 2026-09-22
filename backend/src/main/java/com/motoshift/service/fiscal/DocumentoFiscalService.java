package com.motoshift.service.fiscal;

import com.motoshift.dto.DocumentoResponse;
import com.motoshift.entity.Cobranca;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CobrancaRepository;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.service.ledger.Movimento;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;

/**
 * O documento de um lançamento do extrato — o "Gerar documento" do app.
 *
 * <p>Um lançamento, um documento, decidido por {@link TipoDocumento}. Para o
 * pagamento de turno é a NFS-e, e a MESMA nos dois lados: o entregador chega
 * a ela pelo pagamento_recebido, o lojista pelo pagamento_enviado da mesma
 * operação, e os dois caem em {@link NotaFiscalService#emitirParaPagamento}.
 * Para o resto é um comprovante, derivado na hora pelo
 * {@link ComprovanteService}.
 *
 * <p><b>Quem pode.</b> Só o dono do lançamento. O extrato é privado — o id de
 * um lançamento alheio não abre nada, nem para a contraparte: o lojista vê a
 * nota pelo lançamento DELE. Terceiro leva 403. Tudo SIMULADO — ver
 * {@code docs/financeiro/FISCAL.md}.
 */
@Service
public class DocumentoFiscalService {

    private final TransacaoRepository transacaoRepo;
    private final CobrancaRepository cobrancaRepo;
    private final NotaFiscalRepository notaRepo;
    private final NotaFiscalService notas;
    private final ComprovanteService comprovantes;

    public DocumentoFiscalService(TransacaoRepository transacaoRepo,
                                  CobrancaRepository cobrancaRepo,
                                  NotaFiscalRepository notaRepo,
                                  NotaFiscalService notas,
                                  ComprovanteService comprovantes) {
        this.transacaoRepo = transacaoRepo;
        this.cobrancaRepo = cobrancaRepo;
        this.notaRepo = notaRepo;
        this.notas = notas;
        this.comprovantes = comprovantes;
    }

    /** O documento e se ele nasceu nesta chamada (só NFS-e nasce; comprovante é derivado). */
    public record Resultado(DocumentoResponse documento, boolean criado) {}

    /**
     * Emite o documento, ou devolve o que já existe. Idempotente: gerar duas
     * vezes devolve o mesmo documento — a mesma nota, o mesmo comprovante.
     */
    @Transactional
    public Resultado emitir(Long transacaoId, Long usuarioId) {
        Transacao t = doDono(transacaoId, usuarioId);
        TipoDocumento tipo = tipoDe(t);

        if (tipo != TipoDocumento.NFSE) {
            return new Resultado(DocumentoResponse.deComprovante(comprovantes.montar(t, tipo)), false);
        }
        NotaFiscalService.Emissao e = notas.emitirParaPagamento(pagamentoRecebido(t), usuarioId);
        return new Resultado(DocumentoResponse.deNota(t.getId(), e.nota()), e.criada());
    }

    /**
     * O documento que já existe, sem emitir nada. Comprovante sempre existe
     * (é derivado); NFS-e só depois de gerada — antes, 404.
     */
    @Transactional(readOnly = true)
    public DocumentoResponse buscar(Long transacaoId, Long usuarioId) {
        Transacao t = doDono(transacaoId, usuarioId);
        TipoDocumento tipo = tipoDe(t);

        if (tipo != TipoDocumento.NFSE) {
            return DocumentoResponse.deComprovante(comprovantes.montar(t, tipo));
        }
        Transacao recebido = pagamentoRecebido(t);
        NotaFiscal nota = notaRepo.findByTransacaoId(recebido.getId())
                .or(() -> recebido.getTurnoId() == null ? Optional.empty()
                        : notaRepo.findByTurnoIdAndPrestadorId(recebido.getTurnoId(),
                                recebido.getUsuarioId()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "A nota fiscal deste pagamento ainda não foi gerada."));
        return DocumentoResponse.deNota(t.getId(), notas.buscar(nota.getId(), usuarioId));
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private Transacao doDono(Long transacaoId, Long usuarioId) {
        Transacao t = transacaoRepo.findById(transacaoId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Lançamento não encontrado."));
        if (!t.getUsuarioId().equals(usuarioId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: este lançamento não é seu.");
        }
        return t;
    }

    private TipoDocumento tipoDe(Transacao t) {
        StatusCobranca pix = t.getTipo() != TipoTransacao.SAQUE ? null
                : Movimento.cobrancaDoSaque(t.getIdempotencyKey())
                        .flatMap(cobrancaRepo::findById)
                        .map(Cobranca::getStatus)
                        .orElse(null);
        return TipoDocumento.para(t, pix).orElseThrow(() -> new ResponseStatusException(
                HttpStatus.CONFLICT, t.getTipo() == TipoTransacao.SAQUE
                        ? "A transferência Pix ainda não foi confirmada pelo banco."
                        : "Este lançamento não foi concluído e não tem documento."));
    }

    /**
     * O pagamento_recebido que a NFS-e documenta, a partir de qualquer um dos
     * dois lados. Pelo lado do lojista, é o lançamento do entregador na mesma
     * operação; lançamento anterior ao ledger, sem operação, cai no turno.
     */
    private Transacao pagamentoRecebido(Transacao t) {
        if (t.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO) return t;

        Long entregador = t.getContraparteId();
        Optional<Transacao> pelaOperacao = t.getOperacaoId() == null || entregador == null
                ? Optional.empty()
                : transacaoRepo.findByOperacaoIdAndUsuarioIdAndTipoIn(t.getOperacaoId(), entregador,
                        List.of(TipoTransacao.PAGAMENTO_RECEBIDO)).stream().findFirst();
        return pelaOperacao
                .or(() -> t.getTurnoId() == null || entregador == null ? Optional.empty()
                        : notas.pagamentoDe(t.getTurnoId(), entregador))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.CONFLICT,
                        "O pagamento correspondente do entregador não está no extrato."));
    }
}
