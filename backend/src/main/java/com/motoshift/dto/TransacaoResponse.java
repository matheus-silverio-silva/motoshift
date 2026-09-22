package com.motoshift.dto;

import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.service.fiscal.IndiceDeDocumentos;
import com.motoshift.service.fiscal.TipoDocumento;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

public class TransacaoResponse {

    private Long id;
    private Long usuarioId;
    private Long contraparteId;
    private Long turnoId;
    private TipoTransacao tipo;

    /**
     * Se entra ou sai — lido do lançamento, nunca deduzido do tipo.
     *
     * O app decidia o sinal por uma lista de tipos conhecidos, então um tipo
     * que a versão instalada não conhecesse virava crédito por omissão: uma
     * reserva de R$ 360 aparecia no extrato com sinal de mais.
     */
    private NaturezaTransacao natureza;

    private BigDecimal valor;
    private String descricao;
    private StatusTransacao status;

    /** Une os dois lados de uma transferência — ver {@code Transacao.operacaoId}. */
    private UUID operacaoId;

    /** Saldo logo depois deste lançamento. Null nas linhas anteriores à V12. */
    private BigDecimal saldoDisponivelApos;
    private BigDecimal saldoBloqueadoApos;

    private LocalDateTime criadoEm;

    /**
     * @deprecated Espelha usuarioId. Mantido para o app antigo, que le este
     * campo como `int` NAO-NULAVEL (transacao.dart) — e uma transacao com
     * motoboy_id nulo no meio do extrato quebraria a tela de carteira inteira,
     * de forma permanente para aquele usuario.
     */
    @Deprecated
    private Long motoboyId;

    /**
     * Se o lançamento tem documento (NFS-e ou comprovante) que dá para gerar
     * agora. Falso para o que não concluiu e para saque com Pix pendente.
     */
    private boolean documentoDisponivel;

    /** NFSE, RECIBO_RECARGA, COMPROVANTE_PIX ou COMPROVANTE_MOVIMENTACAO. */
    private TipoDocumento tipoDocumento;

    /**
     * Id da NFS-e, quando já emitida. Comprovante não tem: é derivado do
     * lançamento a cada pedido, então não há "emitido" a registrar.
     */
    private Long documentoId;

    /** Preenche o que o extrato mostra sobre o documento — ver IndiceDeDocumentos. */
    public TransacaoResponse comDocumento(IndiceDeDocumentos.Info info) {
        if (info != null) {
            this.documentoDisponivel = info.disponivel();
            this.tipoDocumento = info.tipo();
            this.documentoId = info.documentoId();
        }
        return this;
    }

    @SuppressWarnings("deprecation")
    public static TransacaoResponse from(Transacao t) {
        TransacaoResponse r = new TransacaoResponse();
        r.id = t.getId();
        r.usuarioId = t.getUsuarioId();
        r.contraparteId = t.getContraparteId();
        r.motoboyId = t.getUsuarioId();
        r.turnoId = t.getTurnoId();
        r.tipo = t.getTipo();
        r.natureza = t.getNatureza();
        r.valor = CarteiraResponse.emReais(t.getValor());
        r.descricao = t.getDescricao();
        r.status = t.getStatus();
        r.operacaoId = t.getOperacaoId();
        r.saldoDisponivelApos = CarteiraResponse.emReais(t.getSaldoDisponivelApos());
        r.saldoBloqueadoApos = CarteiraResponse.emReais(t.getSaldoBloqueadoApos());
        r.criadoEm = t.getCriadoEm();
        return r;
    }

    public Long getId() { return id; }
    public boolean isDocumentoDisponivel() { return documentoDisponivel; }
    public TipoDocumento getTipoDocumento() { return tipoDocumento; }
    public Long getDocumentoId() { return documentoId; }
    public Long getUsuarioId() { return usuarioId; }
    public Long getContraparteId() { return contraparteId; }
    public Long getTurnoId() { return turnoId; }
    public TipoTransacao getTipo() { return tipo; }
    public NaturezaTransacao getNatureza() { return natureza; }
    public BigDecimal getValor() { return valor; }
    public String getDescricao() { return descricao; }
    public StatusTransacao getStatus() { return status; }
    public UUID getOperacaoId() { return operacaoId; }
    public BigDecimal getSaldoDisponivelApos() { return saldoDisponivelApos; }
    public BigDecimal getSaldoBloqueadoApos() { return saldoBloqueadoApos; }
    public LocalDateTime getCriadoEm() { return criadoEm; }

    /** @deprecated use {@link #getUsuarioId()}. */
    @Deprecated
    public Long getMotoboyId() { return motoboyId; }
}
