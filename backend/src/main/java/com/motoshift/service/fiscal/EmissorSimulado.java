package com.motoshift.service.fiscal;

import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotaFiscalRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * Emissor de NFS-e simulado: nada sai da plataforma.
 *
 * <p>Número sequencial por prestador, chave de acesso no formato do padrão
 * nacional ({@link ChaveDeAcessoNfse}) e código de verificação derivado dos
 * dados da própria nota — os mesmos dados produzem sempre o mesmo código e a
 * mesma chave, e nenhum dos dois depende do id que o banco gerar. Nada disso
 * tem valor fiscal, e o documento diz isso na cara ("DOCUMENTO SIMULADO — SEM
 * VALOR FISCAL").
 */
@Component
public class EmissorSimulado implements EmissorDeNotas {

    private final NotaFiscalRepository notaRepo;
    private final String serie;

    public EmissorSimulado(NotaFiscalRepository notaRepo,
                           @Value("${motoshift.fiscal.nfse-serie:A1}") String serie) {
        this.notaRepo = notaRepo;
        this.serie = serie;
    }

    @Override
    public Autorizacao autorizar(NotaFiscal rascunho, Usuario prestador) {
        int numero = proximoNumero(rascunho.getPrestadorId());
        return new Autorizacao(
                numero,
                serie,
                codigoDeVerificacao(rascunho),
                chaveDeAcesso(rascunho, numero, prestador));
    }

    /**
     * A chave de uma nota já numerada — a das notas anteriores à V20, que
     * nasceram sem chave, sai daqui pela mesma regra.
     */
    static String chaveDeAcesso(NotaFiscal n, Usuario prestador) {
        return chaveDeAcesso(n, n.getNumero(), prestador);
    }

    private static String chaveDeAcesso(NotaFiscal n, int numero, Usuario prestador) {
        boolean cnpj = prestador != null && "lojista".equalsIgnoreCase(prestador.getTipo());
        return ChaveDeAcessoNfse.gerar(
                prestador == null ? MunicipioIbge.DESCONHECIDO
                        : MunicipioIbge.codigoOuDesconhecido(prestador.getCidade(), prestador.getEstado()),
                cnpj ? ChaveDeAcessoNfse.INSCRICAO_CNPJ : ChaveDeAcessoNfse.INSCRICAO_CPF,
                // O entregador não tem CPF no cadastro: zeros, e não a CNH.
                cnpj ? prestador.getDocumentoFederal() : null,
                numero,
                n.getEmitidaEm(),
                semente(n) + ":" + numero);
    }

    /**
     * Próximo sequencial do prestador.
     *
     * <p>Lê o máximo e soma um, dentro da transação. Duas emissões realmente
     * simultâneas do mesmo entregador poderiam calcular o mesmo número — o que
     * não gera documento duplicado, porque a unicidade que importa é a do
     * pagamento, e essa está no banco. Numeração à prova de corrida pede uma
     * sequence por emitente, e na integração real quem numera é o Sistema
     * Nacional.
     */
    private int proximoNumero(Long prestadorId) {
        Integer ultimo = notaRepo.ultimoNumeroDoPrestador(prestadorId);
        return ultimo == null ? 1 : ultimo + 1;
    }

    private static String semente(NotaFiscal n) {
        return n.getTurnoId() + ":" + n.getPrestadorId() + ":"
                + n.getTransacaoId() + ":" + n.getValorServico().toPlainString();
    }

    private static String codigoDeVerificacao(NotaFiscal n) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest(semente(n).getBytes(StandardCharsets.UTF_8));
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
}
