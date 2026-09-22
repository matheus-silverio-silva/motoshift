package com.motoshift.service.fiscal;

import com.motoshift.entity.NotaFiscal;

/**
 * Quem dá número e autenticidade a uma NFS-e — a fronteira com a prefeitura.
 *
 * <p>Hoje a única implementação é {@link EmissorSimulado}: número sequencial
 * por prestador e código de verificação derivado dos dados da nota, tudo
 * dentro da plataforma. É a mesma ideia do {@code GatewayPagamento} do ledger:
 * o resto do sistema fala com esta interface e não sabe se do outro lado há
 * uma simulação ou um provedor de verdade.
 *
 * <p><b>Como seria a integração real.</b> Uma implementação que monta o RPS
 * (Recibo Provisório de Serviços) a partir do rascunho, assina com o
 * certificado A1 do prestador, envia ao webservice do município (padrão ABRASF)
 * ou ao Ambiente Nacional da NFS-e, e devolve o número e o código de
 * verificação que a prefeitura atribuiu. Nenhuma coluna de
 * {@code notas_fiscais} muda — ver {@code docs/financeiro/FISCAL.md}.
 */
public interface EmissorDeNotas {

    /**
     * Numera e autentica uma nota prestes a ser gravada.
     *
     * @param rascunho a nota com partes, valores e competência preenchidos
     */
    Autorizacao autorizar(NotaFiscal rascunho);

    /** O que a autoridade (aqui, a simulação) devolve para a nota valer. */
    record Autorizacao(int numero, String serie, String codigoVerificacao) {}
}
