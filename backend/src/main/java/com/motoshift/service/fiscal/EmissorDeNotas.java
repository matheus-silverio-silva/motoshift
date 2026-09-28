package com.motoshift.service.fiscal;

import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.Usuario;

/**
 * Quem dá número e autenticidade a uma NFS-e — a fronteira com o Sistema
 * Nacional NFS-e (ou com a prefeitura).
 *
 * <p>Hoje a única implementação é {@link EmissorSimulado}: número sequencial
 * por prestador, chave de acesso de 50 dígitos no formato nacional e código de
 * verificação derivado dos dados da nota, tudo dentro da plataforma. É a mesma
 * ideia do {@code GatewayPagamento} do ledger: o resto do sistema fala com
 * esta interface e não sabe se do outro lado há uma simulação ou um provedor
 * de verdade.
 *
 * <p><b>Como seria a integração real.</b> Uma implementação que monta a DPS
 * (Declaração de Prestação de Serviço) a partir do rascunho, assina com o
 * certificado A1 do prestador, envia ao Sistema Nacional NFS-e (ou ao
 * webservice do município, padrão ABRASF), e devolve o número e a chave de
 * acesso que ele atribuiu — ver {@code docs/financeiro/FISCAL.md}.
 */
public interface EmissorDeNotas {

    /**
     * Numera e autentica uma nota prestes a ser gravada.
     *
     * @param rascunho  a nota com partes, valores, competência e emissão preenchidos
     * @param prestador o cadastro de quem presta — inscrição federal e município
     *                  entram na chave de acesso; nulo se a conta sumiu
     */
    Autorizacao autorizar(NotaFiscal rascunho, Usuario prestador);

    /** O que a autoridade (aqui, a simulação) devolve para a nota valer. */
    record Autorizacao(int numero, String serie, String codigoVerificacao, String chaveAcesso) {}
}
