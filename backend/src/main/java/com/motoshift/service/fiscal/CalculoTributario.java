package com.motoshift.service.fiscal;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Os tributos de um serviço de entrega — um lugar só para a conta.
 *
 * <p><b>O problema que isto resolve.</b> A NFS-e descontava ISS e IRRF no valor
 * líquido, mas a liquidação creditava o entregador pelo valor cheio. A nota
 * dizia "você recebeu R$ 187" e o extrato, "você recebeu R$ 200": dois
 * documentos da mesma plataforma contando histórias diferentes sobre o mesmo
 * dinheiro. A conta dos tributos morava na nota e em nenhum outro lugar, e por
 * isso o dinheiro não tinha como segui-la.
 *
 * <p><b>As duas políticas</b>, escolhidas por
 * {@code motoshift.fiscal.reter-na-fonte}:
 * <ul>
 *   <li><b>false (padrão)</b> — nada é retido. A nota mostra os tributos como
 *       <i>valor aproximado dos tributos</i>, informação ao consumidor no
 *       espírito da Lei 12.741/2012, e o valor líquido é o próprio valor do
 *       serviço: bate com o extrato.</li>
 *   <li><b>true</b> — a liquidação retém: o entregador recebe o pagamento
 *       bruto e, na mesma operação, um débito de ISS e um de IRRF. O saldo que
 *       sobra é o líquido da nota, centavo por centavo.</li>
 * </ul>
 *
 * <p>A política vale para o que acontece <b>a partir de agora</b>. A nota não
 * consulta esta chave para saber se houve retenção: ela lê os lançamentos de
 * retenção do extrato. Assim, trocar a configuração não reescreve o passado —
 * um pagamento liquidado com retenção continua com nota de tributos retidos.
 *
 * <p>As alíquotas são exemplos, não apuração fiscal: 5% de ISS é o teto da LC
 * 116/2003 e 1,5% de IRRF a retenção usual sobre serviços. As chaves antigas
 * {@code motoshift.nf.*} continuam valendo como alternativa.
 */
@Component
public class CalculoTributario {

    private final BigDecimal issAliquota;
    private final BigDecimal irrfAliquota;
    private final boolean reterNaFonte;

    public CalculoTributario(
            @Value("${motoshift.fiscal.iss-aliquota:${motoshift.nf.iss-aliquota:0.05}}")
            BigDecimal issAliquota,
            @Value("${motoshift.fiscal.irrf-aliquota:${motoshift.nf.irrf-aliquota:0.015}}")
            BigDecimal irrfAliquota,
            @Value("${motoshift.fiscal.reter-na-fonte:false}")
            boolean reterNaFonte) {
        this.issAliquota = issAliquota;
        this.irrfAliquota = irrfAliquota;
        this.reterNaFonte = reterNaFonte;
    }

    /** Se a liquidação deve reter ISS e IRRF do entregador. */
    public boolean reterNaFonte() {
        return reterNaFonte;
    }

    /** ISS e IRRF sobre uma base, com as alíquotas vigentes. */
    public Tributos calcular(BigDecimal base) {
        BigDecimal b = base.setScale(2, RoundingMode.HALF_UP);
        return new Tributos(
                issAliquota, b.multiply(issAliquota).setScale(2, RoundingMode.HALF_UP),
                irrfAliquota, b.multiply(irrfAliquota).setScale(2, RoundingMode.HALF_UP));
    }

    /**
     * Alíquota efetiva de um valor já retido — para a nota mostrar a alíquota
     * que valeu na liquidação, e não a de hoje.
     */
    public static BigDecimal aliquotaDe(BigDecimal valor, BigDecimal base) {
        if (base == null || base.signum() == 0) return BigDecimal.ZERO;
        return valor.divide(base, 4, RoundingMode.HALF_UP);
    }

    /** Resultado da conta, com alíquota e valor de cada tributo. */
    public record Tributos(BigDecimal issAliquota, BigDecimal iss,
                           BigDecimal irrfAliquota, BigDecimal irrf) {

        public BigDecimal total() {
            return iss.add(irrf);
        }
    }
}
