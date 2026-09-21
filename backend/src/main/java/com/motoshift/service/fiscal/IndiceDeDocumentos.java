package com.motoshift.service.fiscal;

import com.motoshift.entity.Cobranca;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CobrancaRepository;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.service.ledger.Movimento;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Para cada lançamento de uma página do extrato: tem documento? de que tipo?
 * já emitido?
 *
 * <p>Duas consultas por página, qualquer que seja o tamanho dela — as notas
 * dos turnos que aparecem e as cobranças dos saques que aparecem. Perguntar
 * lançamento a lançamento seria uma consulta por linha, na tela que mais se
 * abre do app.
 */
@Component
public class IndiceDeDocumentos {

    private final NotaFiscalRepository notaRepo;
    private final CobrancaRepository cobrancaRepo;

    public IndiceDeDocumentos(NotaFiscalRepository notaRepo, CobrancaRepository cobrancaRepo) {
        this.notaRepo = notaRepo;
        this.cobrancaRepo = cobrancaRepo;
    }

    /**
     * O que o extrato mostra sobre o documento de um lançamento.
     *
     * @param disponivel  dá para gerar agora
     * @param tipo        qual documento, quando há
     * @param documentoId id da NFS-e já emitida; nulo para comprovante, que é
     *                    derivado e não tem emissão
     */
    public record Info(boolean disponivel, TipoDocumento tipo, Long documentoId) {
        public static final Info NENHUM = new Info(false, null, null);
    }

    public Map<Long, Info> indexar(Collection<Transacao> lancamentos) {
        Map<Long, StatusCobranca> pix = statusDosSaques(lancamentos);
        Map<String, Long> notas = notasDosTurnos(lancamentos);

        Map<Long, Info> saida = new HashMap<>();
        for (Transacao t : lancamentos) {
            StatusCobranca status = Movimento.cobrancaDoSaque(t.getIdempotencyKey())
                    .map(pix::get).orElse(null);
            Optional<TipoDocumento> tipo = TipoDocumento.para(t, status);
            if (tipo.isEmpty()) {
                saida.put(t.getId(), Info.NENHUM);
                continue;
            }
            Long nota = tipo.get() == TipoDocumento.NFSE
                    ? notas.get(t.getTurnoId() + ":" + prestadorDe(t))
                    : null;
            saida.put(t.getId(), new Info(true, tipo.get(), nota));
        }
        return saida;
    }

    /** O entregador de um pagamento: o dono, se recebido; a contraparte, se enviado. */
    static Long prestadorDe(Transacao t) {
        return t.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO ? t.getUsuarioId() : t.getContraparteId();
    }

    private Map<Long, StatusCobranca> statusDosSaques(Collection<Transacao> lancamentos) {
        Set<Long> ids = new HashSet<>();
        for (Transacao t : lancamentos) {
            if (t.getTipo() == TipoTransacao.SAQUE) {
                Movimento.cobrancaDoSaque(t.getIdempotencyKey()).ifPresent(ids::add);
            }
        }
        Map<Long, StatusCobranca> mapa = new HashMap<>();
        if (ids.isEmpty()) return mapa;
        for (Cobranca c : cobrancaRepo.findAllById(ids)) {
            mapa.put(c.getId(), c.getStatus());
        }
        return mapa;
    }

    private Map<String, Long> notasDosTurnos(Collection<Transacao> lancamentos) {
        Set<Long> turnos = new HashSet<>();
        for (Transacao t : lancamentos) {
            if ((t.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO
                    || t.getTipo() == TipoTransacao.PAGAMENTO_ENVIADO) && t.getTurnoId() != null) {
                turnos.add(t.getTurnoId());
            }
        }
        Map<String, Long> mapa = new HashMap<>();
        if (turnos.isEmpty()) return mapa;
        for (NotaFiscal n : notaRepo.findByTurnoIdIn(turnos)) {
            mapa.put(n.getTurnoId() + ":" + n.getPrestadorId(), n.getId());
        }
        return mapa;
    }
}
