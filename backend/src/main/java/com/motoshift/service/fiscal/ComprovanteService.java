package com.motoshift.service.fiscal;

import com.motoshift.dto.ComprovanteResponse;
import com.motoshift.dto.ComprovanteResponse.Linha;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

/**
 * Recibos e comprovantes dos lançamentos que não são serviço prestado.
 *
 * <p><b>Sem tabela, de propósito.</b> O comprovante não acrescenta informação
 * ao lançamento — ele é o lançamento apresentado como documento. Guardá-lo
 * seria guardar uma cópia que pode divergir do original. Por isso ele é
 * derivado toda vez que é pedido, e sai sempre igual:
 * <ul>
 *   <li><b>número</b>: prefixo do tipo + id do lançamento ({@code RC-00000123}).
 *       O id já é único e crescente; uma numeração separada precisaria de
 *       tabela só para guardar contador;</li>
 *   <li><b>código de autenticação</b>: HMAC-SHA256 dos campos do lançamento com
 *       a chave {@code motoshift.fiscal.chave-autenticacao}. O mesmo lançamento
 *       gera sempre o mesmo código; um lançamento adulterado no banco geraria
 *       outro; e sem a chave não se fabrica um código que a plataforma
 *       reconheça.</li>
 * </ul>
 *
 * <p>Trocar a chave muda o código de todos os comprovantes — é o que se quer
 * se ela vazar, e é por isso que ela fica em variável de ambiente em produção.
 */
@Service
public class ComprovanteService {

    private final byte[] chave;
    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;

    public ComprovanteService(@Value("${motoshift.fiscal.chave-autenticacao:}") String chave,
                              UsuarioRepository usuarioRepo,
                              TurnoRepository turnoRepo) {
        if (chave == null || chave.isBlank()) {
            // Sem chave, o código de autenticação seria um hash que qualquer um
            // reproduz — e o comprovante afirmaria uma autenticidade que não tem.
            throw new IllegalStateException(
                    "motoshift.fiscal.chave-autenticacao não configurada "
                            + "(em produção: variável MOTOSHIFT_FISCAL_CHAVE).");
        }
        this.chave = chave.getBytes(StandardCharsets.UTF_8);
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
    }

    public ComprovanteResponse montar(Transacao t, TipoDocumento tipo) {
        if (tipo == TipoDocumento.NFSE) {
            throw new IllegalArgumentException("NFS-e não é comprovante — ver NotaFiscalService.");
        }
        Usuario titular = usuarioRepo.findById(t.getUsuarioId()).orElse(null);
        DocumentoDaParte doc = DocumentoDaParte.de(titular);
        Turno turno = t.getTurnoId() == null ? null : turnoRepo.findById(t.getTurnoId()).orElse(null);

        return new ComprovanteResponse(
                tipo,
                titulo(tipo),
                numero(tipo, t.getId()),
                codigoDeAutenticacao(t),
                t.getId(),
                t.getOperacaoId(),
                t.getTipo(),
                t.getNatureza(),
                emReais(t.getValor()),
                t.getDescricao(),
                t.getCriadoEm(),
                titular == null ? "—" : titular.getNome(),
                doc.tipo(),
                doc.numero(),
                cidade(titular),
                emReais(t.getSaldoDisponivelApos()),
                emReais(t.getSaldoBloqueadoApos()),
                detalhes(t, tipo, turno));
    }

    static String titulo(TipoDocumento tipo) {
        return switch (tipo) {
            case RECIBO_RECARGA -> "Recibo de recarga";
            case COMPROVANTE_PIX -> "Comprovante de transferência Pix";
            case COMPROVANTE_MOVIMENTACAO -> "Comprovante de movimentação";
            case NFSE -> "Nota fiscal de serviço";
        };
    }

    static String numero(TipoDocumento tipo, Long transacaoId) {
        String prefixo = switch (tipo) {
            case RECIBO_RECARGA -> "RC";
            case COMPROVANTE_PIX -> "PIX";
            case COMPROVANTE_MOVIMENTACAO -> "MOV";
            case NFSE -> "NFSE";
        };
        return prefixo + "-" + String.format("%08d", transacaoId);
    }

    /**
     * HMAC-SHA256 dos campos que definem o lançamento, em 16 hexadecimais
     * agrupados de 4 em 4. Os campos são os que não mudam depois de gravado —
     * o saldo depois do lançamento fica de fora porque é foto, não fato.
     */
    String codigoDeAutenticacao(Transacao t) {
        String campos = String.join("|",
                String.valueOf(t.getId()),
                String.valueOf(t.getUsuarioId()),
                t.getTipo().getValor(),
                t.getValor().setScale(2, RoundingMode.HALF_UP).toPlainString(),
                String.valueOf(t.getCriadoEm()),
                String.valueOf(t.getOperacaoId()),
                String.valueOf(t.getIdempotencyKey()));
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(chave, "HmacSHA256"));
            String hex = HexFormat.of().withUpperCase()
                    .formatHex(mac.doFinal(campos.getBytes(StandardCharsets.UTF_8)));
            return hex.substring(0, 4) + "-" + hex.substring(4, 8) + "-"
                    + hex.substring(8, 12) + "-" + hex.substring(12, 16);
        } catch (GeneralSecurityException e) {
            // HmacSHA256 é obrigatório em toda JVM; se faltar, o ambiente está quebrado.
            throw new IllegalStateException("HmacSHA256 indisponível nesta JVM", e);
        }
    }

    private static List<Linha> detalhes(Transacao t, TipoDocumento tipo, Turno turno) {
        List<Linha> l = new ArrayList<>();
        String doTurno = turno == null ? null : turno.getTitulo();
        switch (t.getTipo()) {
            case RECARGA -> {
                l.add(new Linha("Forma de pagamento", "Pix"));
                l.add(new Linha("Situação", "Pagamento confirmado"));
                l.add(new Linha("Crédito em", "Saldo disponível"));
            }
            case SAQUE -> {
                l.add(new Linha("Chave Pix de destino", mascararChavePix(chaveDoSaque(t))));
                l.add(new Linha("Situação", tipo == TipoDocumento.COMPROVANTE_PIX
                        ? "Transferência concluída"
                        : "Transferência recusada pelo banco — o valor foi estornado"));
            }
            case RESERVA -> {
                if (doTurno != null) l.add(new Linha("Turno", doTurno));
                l.add(new Linha("Movimento", "Do saldo disponível para o bloqueado"));
                l.add(new Linha("Natureza", "Reserva de valor — não é pagamento nem serviço"));
            }
            case LIBERACAO_RESERVA -> {
                if (doTurno != null) l.add(new Linha("Turno", doTurno));
                l.add(new Linha("Movimento", "Do saldo bloqueado para o disponível"));
                l.add(new Linha("Natureza", "Devolução de reserva — não é pagamento nem serviço"));
            }
            case ESTORNO -> {
                l.add(new Linha("Movimento", "Devolução ao saldo disponível"));
                l.add(new Linha("Referente a", "Transferência Pix recusada"));
            }
            case RETENCAO_ISS, RETENCAO_IRRF -> {
                l.add(new Linha("Tributo", t.getTipo() == TipoTransacao.RETENCAO_ISS ? "ISS" : "IRRF"));
                if (doTurno != null) l.add(new Linha("Turno", doTurno));
                l.add(new Linha("Movimento", "Retido na fonte sobre o pagamento do turno"));
            }
            case BONUS -> l.add(new Linha("Movimento", "Crédito de bônus"));
            case PAGAMENTO_RECEBIDO, PAGAMENTO_ENVIADO -> {
                // Pagamento de turno tem NFS-e, não comprovante.
            }
        }
        return l;
    }

    /** A chave vem na descrição do saque ("Transferência Pix — chave"). */
    private static String chaveDoSaque(Transacao t) {
        String d = t.getDescricao();
        if (d == null) return null;
        int i = d.indexOf(" — ");
        return i < 0 ? null : d.substring(i + 3).trim();
    }

    /**
     * Chave Pix mascarada: o suficiente para a pessoa reconhecer a própria
     * chave, sem o documento virar cópia dela.
     */
    static String mascararChavePix(String chave) {
        if (chave == null || chave.isBlank()) return "—";
        if (chave.contains("@")) {
            int arroba = chave.indexOf('@');
            return chave.charAt(0) + "***" + chave.substring(arroba);
        }
        String digitos = chave.replaceAll("[^0-9]", "");
        if (digitos.length() == 11 && digitos.length() == chave.replaceAll("[.\\-\\s()]", "").length()) {
            return "***." + digitos.substring(3, 6) + "." + digitos.substring(6, 9) + "-**";
        }
        if (chave.length() <= 6) return "***";
        return chave.substring(0, 3) + "****" + chave.substring(chave.length() - 2);
    }

    /** Duas casas, como todo valor que sai para o app; nulo continua nulo (saldo antigo sem foto). */
    private static java.math.BigDecimal emReais(java.math.BigDecimal v) {
        return v == null ? null : v.setScale(2, RoundingMode.HALF_UP);
    }

    private static String cidade(Usuario u) {
        if (u == null || u.getCidade() == null || u.getCidade().isBlank()) return null;
        return u.getEstado() == null || u.getEstado().isBlank()
                ? u.getCidade()
                : u.getCidade() + "/" + u.getEstado();
    }
}
