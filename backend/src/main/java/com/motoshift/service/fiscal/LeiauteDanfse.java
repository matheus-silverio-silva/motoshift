package com.motoshift.service.fiscal;

import com.motoshift.dto.DanfseResponse;
import com.motoshift.dto.DanfseResponse.Campo;
import com.motoshift.dto.DanfseResponse.Quadro;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.Usuario;
import com.motoshift.util.Reais;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Monta a NFS-e no leiaute do DANFSe v2.0 — o Documento Auxiliar da NFS-e do
 * padrão nacional, como a Nota Técnica SE/CGNFS-e nº 008/2026 o define.
 * SIMULADO: a estrutura e os rótulos são os do modelo oficial; nada foi
 * transmitido ao Sistema Nacional NFS-e.
 *
 * <p><b>Ordem dos blocos</b>, a da NT: identificação da NFS-e (chave de acesso,
 * número, competência, emissão, DPS e QR Code), emitente/prestador, tomador,
 * destinatário, intermediário, serviço prestado, tributação municipal (ISSQN),
 * tributação federal, tributação IBS/CBS, valor total e informações
 * complementares. Campo que a nota não informa sai com "-", como no documento
 * oficial.
 *
 * <p><b>As decisões fiscais que o leiaute torna visíveis</b>, todas de exemplo:
 * <ul>
 *   <li><b>Serviço</b>: item 26.01 da lista da LC 116/2003 — coleta, remessa
 *       ou entrega de objetos, bens ou valores —, código de tributação
 *       nacional 26.01.01 e NBS 1.0702.00.00. É onde a entrega por motoboy se
 *       enquadra.</li>
 *   <li><b>Regime</b>: "Não optante" do Simples. As alíquotas da simulação (ISS
 *       5%, IRRF 1,5%) supõem o regime normal; um MEI pagaria o ISS no DAS e
 *       não teria IRRF retido — ver {@code docs/financeiro/FISCAL.md}.</li>
 *   <li><b>Retenções</b>: com {@link NotaFiscal#isTributosRetidos()}, o ISSQN
 *       sai como "Retido pelo tomador" e o IRRF como retenção federal; sem ela,
 *       o ISSQN é apurado pelo próprio prestador e não há retenção federal. Em
 *       qualquer caso o valor líquido é o da nota — o mesmo que o extrato
 *       creditou.</li>
 *   <li><b>IBS e CBS</b>: 2026 é o ano de teste da reforma (LC 214/2025): CBS
 *       de 0,9% (art. 346) e IBS estadual de 0,1% (art. 343), destacados e
 *       dispensados de recolhimento para quem cumpre as obrigações acessórias
 *       (art. 348, §1º). A base exclui o ISSQN (art. 12, §2º). Antes de 2026 os
 *       tributos não existiam; depois, as alíquotas da transição ainda não
 *       estão nesta simulação, e o bloco diz isso.</li>
 * </ul>
 *
 * <p><b>O QR Code não aponta para o portal oficial.</b> No DANFSe real ele
 * leva à consulta pública da nota no Portal Nacional da NFS-e. Uma chave
 * simulada lá daria "não encontrada" — e um link para o governo num documento
 * que não é do governo é justamente o que a marca de simulação existe para
 * impedir. Aqui o QR Code repete a chave e diz que é simulação.
 */
public final class LeiauteDanfse {

    public static final String VERSAO = "DANFSe v2.0";
    public static final String NORMA = "Nota Técnica SE/CGNFS-e nº 008/2026";

    public static final String CODIGO_TRIBUTACAO_NACIONAL = "26.01.01";
    public static final String DESCRICAO_TRIBUTACAO_NACIONAL =
            "Serviços de coleta, remessa ou entrega de correspondências, documentos, objetos, "
                    + "bens ou valores, inclusive pelos correios e suas agências franqueadas; "
                    + "courrier e congêneres.";
    public static final String CODIGO_NBS = "1.0702.00.00";

    /** O que o campo não informado mostra, como no DANFSe oficial. */
    static final String VAZIO = "-";

    private LeiauteDanfse() {}

    public static DanfseResponse montar(NotaFiscal n, Usuario prestador, Usuario tomador) {
        String chave = chaveDe(n, prestador);
        String codigoMunicipio = ChaveDeAcessoNfse.codigoMunicipio(chave);
        // O município do prestador é o da chave, gravada na emissão: mudar a
        // cidade no perfil depois não muda um documento já emitido.
        String municipioPrestador = MunicipioIbge.nome(codigoMunicipio).orElse(municipio(prestador));
        String municipioTomador = municipio(tomador);
        IbsCbs ibsCbs = IbsCbs.para(n.getCompetencia(), n.getValorServico(), n.getIssValor());

        List<Quadro> quadros = List.of(
                prestador(prestador, municipioPrestador),
                tomador(tomador, municipioTomador),
                new Quadro("destinatario", "DESTINATÁRIO DA OPERAÇÃO", List.of(),
                        "O destinatário da operação é o próprio tomador do serviço."),
                new Quadro("intermediario", "INTERMEDIÁRIO DO SERVIÇO", List.of(),
                        "INTERMEDIÁRIO DO SERVIÇO NÃO IDENTIFICADO NA NFS-e"),
                servico(n, municipioTomador),
                issqn(n, municipioPrestador),
                federal(n),
                ibsCbs.quadro(),
                totais(n, ibsCbs),
                complementares(n));

        return new DanfseResponse(
                VERSAO,
                NORMA,
                chave,
                municipioPrestador,
                codigoMunicipio,
                n.getNumero(),
                n.getSerie(),
                "DOCUMENTO SIMULADO - SEM VALOR FISCAL | MotoShift | NFS-e chave " + chave,
                "Na NFS-e real, a autenticidade é verificada lendo este QR Code ou consultando a "
                        + "chave de acesso no Portal Nacional da NFS-e. Aqui ele só repete a chave "
                        + "simulada — esta nota não existe no portal.",
                quadros);
    }

    /**
     * A chave gravada na emissão; nota anterior à V20 não tem, e ganha uma
     * derivada dos mesmos dados, pela mesma regra do {@link EmissorSimulado}.
     */
    static String chaveDe(NotaFiscal n, Usuario prestador) {
        if (n.getChaveAcesso() != null) return n.getChaveAcesso();
        return EmissorSimulado.chaveDeAcesso(n, prestador);
    }

    // ── Partes ──────────────────────────────────────────────────────────────

    private static Quadro prestador(Usuario u, String municipio) {
        DocumentoDaParte doc = DocumentoDaParte.de(u);
        return new Quadro("prestador", "EMITENTE DA NFS-e — PRESTADOR DO SERVIÇO", List.of(
                Campo.de("CNPJ / CPF / NIF", documento(doc)),
                Campo.de("Inscrição Municipal", VAZIO),
                Campo.de("Telefone", VAZIO),
                Campo.largo("Nome / Nome Empresarial", u == null ? "Entregador" : u.getNome()),
                Campo.de("E-mail", VAZIO),
                Campo.largo("Endereço", endereco(u)),
                Campo.de("Município", municipio),
                Campo.de("CEP", VAZIO),
                Campo.de("Simples Nacional na Data de Competência", "Não optante"),
                Campo.de("Regime de Apuração Tributária pelo SN", VAZIO)),
                null);
    }

    private static Quadro tomador(Usuario u, String municipio) {
        DocumentoDaParte doc = DocumentoDaParte.de(u);
        String nome = u == null ? "Lojista"
                : (u.getNomeFantasia() != null && !u.getNomeFantasia().isBlank()
                        ? u.getNomeFantasia() : u.getNome());
        return new Quadro("tomador", "TOMADOR DO SERVIÇO", List.of(
                Campo.de("CNPJ / CPF / NIF", documento(doc)),
                Campo.de("Inscrição Municipal", VAZIO),
                Campo.de("Telefone", VAZIO),
                Campo.largo("Nome / Nome Empresarial", nome),
                Campo.de("E-mail", VAZIO),
                Campo.largo("Endereço", endereco(u)),
                Campo.de("Município", municipio),
                Campo.de("CEP", VAZIO)),
                null);
    }

    // ── Serviço e tributos ─────────────────────────────────────────────────

    private static Quadro servico(NotaFiscal n, String localDaPrestacao) {
        return new Quadro("servico", "SERVIÇO PRESTADO", List.of(
                Campo.largo("Código de Tributação Nacional",
                        CODIGO_TRIBUTACAO_NACIONAL + " - " + DESCRICAO_TRIBUTACAO_NACIONAL),
                Campo.de("Código de Tributação Municipal", VAZIO),
                Campo.de("Código NBS", CODIGO_NBS),
                Campo.de("Local da Prestação", localDaPrestacao),
                Campo.de("País da Prestação", "Brasil"),
                Campo.largo("Descrição do Serviço", n.getDescricaoServico())),
                null);
    }

    /**
     * O ISSQN é devido nos dois casos — o que muda é quem recolhe. Retido: o
     * tomador descontou do pagamento. Não retido: o próprio prestador apura e
     * paga, e o valor líquido é o valor do serviço.
     */
    private static Quadro issqn(NotaFiscal n, String municipioDeIncidencia) {
        BigDecimal base = n.getValorServico();
        return new Quadro("issqn", "TRIBUTAÇÃO MUNICIPAL (ISSQN)", List.of(
                Campo.de("Tributação do ISSQN", "Operação Tributável"),
                Campo.de("Município de Incidência do ISSQN", municipioDeIncidencia),
                Campo.de("Regime Especial de Tributação", "Nenhum"),
                Campo.de("Tipo de Imunidade", VAZIO),
                Campo.de("Suspensão da Exigibilidade do ISSQN", "Não"),
                Campo.de("Benefício Municipal", VAZIO),
                Campo.de("Valor do Serviço", Reais.formatar(base)),
                Campo.de("Desconto Incondicionado", VAZIO),
                Campo.de("Total Deduções/Reduções", VAZIO),
                Campo.de("BC ISSQN", Reais.formatar(base)),
                Campo.de("Alíquota Aplicada", Reais.percentual(n.getIssAliquota())),
                Campo.de("Retenção do ISSQN", n.isTributosRetidos() ? "Retido pelo Tomador" : "Não Retido"),
                Campo.de("ISSQN Apurado", Reais.formatar(n.getIssValor()))),
                null);
    }

    private static Quadro federal(NotaFiscal n) {
        String irrf = n.isTributosRetidos()
                ? Reais.formatar(n.getIrrfValor()) + " (" + Reais.percentual(n.getIrrfAliquota()) + ")"
                : VAZIO;
        return new Quadro("federal", "TRIBUTAÇÃO FEDERAL", List.of(
                Campo.de("IRRF", irrf),
                Campo.de("Contribuição Previdenciária - Retida", VAZIO),
                Campo.de("Contribuições Sociais - Retidas", VAZIO),
                Campo.de("PIS - Débito Apuração Própria", VAZIO),
                Campo.de("COFINS - Débito Apuração Própria", VAZIO)),
                n.isTributosRetidos() ? null : "Não houve retenção de tributos federais nesta nota.");
    }

    /**
     * Os totais do documento. O valor líquido é o que o extrato mostra: o
     * serviço inteiro sem retenção, ou o serviço menos ISSQN e IRRF retidos.
     * A NT 008 manda sombrear o valor final — o líquido + IBS/CBS quando há
     * IBS/CBS, o líquido quando não há.
     */
    private static Quadro totais(NotaFiscal n, IbsCbs ibsCbs) {
        boolean retidos = n.isTributosRetidos();
        List<Campo> campos = new ArrayList<>(List.of(
                Campo.de("Valor do Serviço", Reais.formatar(n.getValorServico())),
                Campo.de("Desconto Condicionado", Reais.formatar(BigDecimal.ZERO)),
                Campo.de("Desconto Incondicionado", Reais.formatar(BigDecimal.ZERO)),
                Campo.de("ISSQN Retido", retidos ? Reais.formatar(n.getIssValor()) : VAZIO),
                Campo.de("Total das Retenções Federais", retidos ? Reais.formatar(n.getIrrfValor()) : VAZIO),
                Campo.de("PIS/COFINS - Débito Apur. Própria", VAZIO)));
        if (ibsCbs.aplica()) {
            campos.add(Campo.de("Valor Líquido da NFS-e", Reais.formatar(n.getValorLiquido())));
            campos.add(Campo.de("Total IBS/CBS", Reais.formatar(ibsCbs.total())));
            campos.add(Campo.destacado("Valor Líquido da NFS-e + IBS/CBS",
                    Reais.formatar(n.getValorLiquido().add(ibsCbs.total()))));
        } else {
            campos.add(Campo.destacado("Valor Líquido da NFS-e", Reais.formatar(n.getValorLiquido())));
        }
        return new Quadro("totais", "VALOR TOTAL DA NFS-e", campos,
                ibsCbs.aplica()
                        ? "Em 2026 o IBS e a CBS são destacados sem recolhimento (LC 214/2025, art. 348, "
                                + "§1º): o valor pago ao prestador é o Valor Líquido da NFS-e."
                        : null);
    }

    /**
     * Informações complementares: os tributos aproximados que a Lei
     * 12.741/2012 manda informar, e o que liga a nota ao extrato.
     */
    private static Quadro complementares(NotaFiscal n) {
        List<Campo> campos = new ArrayList<>(List.of(
                Campo.de("Tributos aproximados — Federais", Reais.formatar(n.getIrrfValor())),
                Campo.de("Tributos aproximados — Estaduais", Reais.formatar(BigDecimal.ZERO)),
                Campo.de("Tributos aproximados — Municipais", Reais.formatar(n.getIssValor())),
                Campo.de("Código de verificação", n.getCodigoVerificacao())));
        if (n.getOperacaoId() != null) {
            campos.add(Campo.largo("Operação no extrato", n.getOperacaoId().toString()));
        }
        return new Quadro("complementares", "INFORMAÇÕES COMPLEMENTARES", campos,
                "Totais aproximados dos tributos conforme a Lei 12.741/2012. Nota emitida pela "
                        + "plataforma por conta do prestador, a pedido do tomador. Alíquotas de exemplo.");
    }

    // ── IBS e CBS ───────────────────────────────────────────────────────────

    /**
     * IBS e CBS de uma competência. 2026 é o único ano com alíquota definida
     * aqui: é o ano de teste, com alíquotas fixadas na própria LC 214/2025.
     */
    record IbsCbs(Integer ano, BigDecimal base, BigDecimal ibsUf, BigDecimal ibsMun, BigDecimal cbs) {

        static final BigDecimal ALIQUOTA_IBS_UF_2026 = new BigDecimal("0.001");
        static final BigDecimal ALIQUOTA_IBS_MUN_2026 = BigDecimal.ZERO;
        static final BigDecimal ALIQUOTA_CBS_2026 = new BigDecimal("0.009");

        static IbsCbs para(LocalDateTime competencia, BigDecimal valorServico, BigDecimal iss) {
            Integer ano = competencia == null ? null : competencia.getYear();
            if (ano == null || ano != 2026) return new IbsCbs(ano, null, null, null, null);
            // Na transição, o ISSQN não integra a base (LC 214/2025, art. 12, §2º).
            BigDecimal base = valorServico.subtract(iss).setScale(2, RoundingMode.HALF_UP);
            return new IbsCbs(ano, base,
                    base.multiply(ALIQUOTA_IBS_UF_2026).setScale(2, RoundingMode.HALF_UP),
                    base.multiply(ALIQUOTA_IBS_MUN_2026).setScale(2, RoundingMode.HALF_UP),
                    base.multiply(ALIQUOTA_CBS_2026).setScale(2, RoundingMode.HALF_UP));
        }

        boolean aplica() {
            return base != null;
        }

        BigDecimal total() {
            return aplica() ? ibsUf.add(ibsMun).add(cbs) : BigDecimal.ZERO;
        }

        Quadro quadro() {
            if (!aplica()) {
                return new Quadro("ibscbs", "TRIBUTAÇÃO IBS / CBS", List.of(),
                        ano != null && ano < 2026
                                ? "Não se aplica: IBS e CBS valem para fatos geradores a partir de "
                                        + "2026 (LC 214/2025)."
                                : "As alíquotas de IBS e CBS da transição a partir de 2027 ainda não "
                                        + "estão nesta simulação.");
            }
            return new Quadro("ibscbs", "TRIBUTAÇÃO IBS / CBS", List.of(
                    Campo.de("CST", "000 - Tributação integral"),
                    Campo.de("Classificação Tributária", "000001"),
                    Campo.de("Base de Cálculo IBS/CBS", Reais.formatar(base)),
                    Campo.de("Alíquota IBS UF", Reais.percentual(ALIQUOTA_IBS_UF_2026)),
                    Campo.de("Valor IBS UF", Reais.formatar(ibsUf)),
                    Campo.de("Alíquota IBS Mun.", Reais.percentual(ALIQUOTA_IBS_MUN_2026)),
                    Campo.de("Valor IBS Mun.", Reais.formatar(ibsMun)),
                    Campo.de("Alíquota CBS", Reais.percentual(ALIQUOTA_CBS_2026)),
                    Campo.de("Valor CBS", Reais.formatar(cbs))),
                    "Ano de teste da reforma tributária: CBS de 0,9% (LC 214/2025, art. 346) e IBS "
                            + "de 0,1% (art. 343), sobre a base sem o ISSQN (art. 12, §2º).");
        }
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private static String documento(DocumentoDaParte doc) {
        return doc.numero() == null
                ? doc.tipo() + " não informado no cadastro"
                : doc.tipo() + " " + doc.numero();
    }

    /** O endereço comercial do lojista; o entregador não tem endereço no cadastro. */
    private static String endereco(Usuario u) {
        if (u == null || u.getEnderecoComercial() == null || u.getEnderecoComercial().isBlank()) {
            return VAZIO;
        }
        return u.getEnderecoComercial();
    }

    /** "Curitiba - PR", como o DANFSe escreve o município; "-" sem cidade. */
    static String municipio(Usuario u) {
        if (u == null || u.getCidade() == null || u.getCidade().isBlank()) return VAZIO;
        String uf = u.getEstado() == null || u.getEstado().isBlank() ? null : u.getEstado().trim().toUpperCase();
        String nome = uf == null ? u.getCidade().trim() : u.getCidade().trim() + " - " + uf;
        return MunicipioIbge.codigo(u.getCidade(), uf).isPresent()
                ? nome
                : nome + " (fora da tabela IBGE da simulação)";
    }

}
