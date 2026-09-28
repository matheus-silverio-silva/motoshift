package com.motoshift.service.fiscal;

import com.motoshift.dto.DanfseResponse;
import com.motoshift.dto.DanfseResponse.Campo;
import com.motoshift.dto.DanfseResponse.Quadro;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.Usuario;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A NFS-e no leiaute do DANFSe v2.0 (NT SE/CGNFS-e nº 008/2026).
 *
 * O que estes testes prendem: os blocos na ordem do modelo oficial, os
 * rótulos como o modelo os escreve, e as três decisões fiscais que o leiaute
 * torna visíveis — quem recolhe o ISSQN, se houve retenção federal, e se IBS
 * e CBS se aplicam na competência. Em todas, o valor líquido é o do extrato.
 */
class LeiauteDanfseTest {

    @Test
    @DisplayName("os blocos vêm na ordem do DANFSe oficial")
    void ordemDosBlocos() {
        DanfseResponse d = LeiauteDanfse.montar(nota(false, 2026), entregador(), loja());

        assertThat(d.versao()).isEqualTo("DANFSe v2.0");
        assertThat(d.norma()).contains("008/2026");
        assertThat(d.quadros()).extracting(Quadro::id).containsExactly(
                "prestador", "tomador", "destinatario", "intermediario", "servico",
                "issqn", "federal", "ibscbs", "totais", "complementares");
        assertThat(quadro(d, "intermediario").observacao())
                .isEqualTo("INTERMEDIÁRIO DO SERVIÇO NÃO IDENTIFICADO NA NFS-e");
    }

    @Test
    @DisplayName("identificação: chave de 50 dígitos com o município do prestador, DPS e QR Code")
    void identificacao() {
        NotaFiscal n = nota(false, 2026);
        DanfseResponse d = LeiauteDanfse.montar(n, entregador(), loja());

        assertThat(d.chaveAcesso()).isEqualTo(n.getChaveAcesso());
        assertThat(d.codigoMunicipio()).isEqualTo("4106902");
        assertThat(d.municipioEmissor()).isEqualTo("Curitiba - PR");
        assertThat(d.numeroDps()).isEqualTo(12);
        assertThat(d.serieDps()).isEqualTo("A1");
        // O QR Code não leva ao portal do governo: repete a chave e diz que é simulação.
        assertThat(d.conteudoQrCode()).contains("SIMULADO").contains(d.chaveAcesso())
                .doesNotContain("gov.br");
    }

    @Test
    @DisplayName("prestador e tomador com os campos do modelo; o que o cadastro não tem sai com \"-\"")
    void partes() {
        DanfseResponse d = LeiauteDanfse.montar(nota(false, 2026), entregador(), loja());

        Quadro prestador = quadro(d, "prestador");
        assertThat(valor(prestador, "CNPJ / CPF / NIF")).isEqualTo("CPF não informado no cadastro");
        assertThat(valor(prestador, "Nome / Nome Empresarial")).isEqualTo("Ricardo Souza");
        assertThat(valor(prestador, "Município")).isEqualTo("Curitiba - PR");
        assertThat(valor(prestador, "Inscrição Municipal")).isEqualTo("-");
        assertThat(valor(prestador, "Simples Nacional na Data de Competência")).isEqualTo("Não optante");

        Quadro tomador = quadro(d, "tomador");
        assertThat(valor(tomador, "CNPJ / CPF / NIF")).isEqualTo("CNPJ **.345.678/0001-**");
        assertThat(valor(tomador, "Nome / Nome Empresarial")).isEqualTo("Hamburgueria da Cláudia");
        assertThat(valor(tomador, "Endereço")).startsWith("Av. Água Verde, 1200");
    }

    @Test
    @DisplayName("serviço: item 26.01 da LC 116, código nacional 26.01.01 e NBS 1.0702.00.00")
    void servico() {
        Quadro s = quadro(LeiauteDanfse.montar(nota(false, 2026), entregador(), loja()), "servico");

        assertThat(valor(s, "Código de Tributação Nacional")).startsWith("26.01.01 - Serviços de coleta");
        assertThat(valor(s, "Código NBS")).isEqualTo("1.0702.00.00");
        assertThat(valor(s, "Local da Prestação")).isEqualTo("Curitiba - PR");
        assertThat(valor(s, "Descrição do Serviço")).startsWith("Serviço de entrega em turno agendado");
    }

    @Test
    @DisplayName("sem retenção: ISSQN apurado pelo prestador, nada federal retido, líquido = serviço")
    void semRetencao() {
        DanfseResponse d = LeiauteDanfse.montar(nota(false, 2025), entregador(), loja());

        Quadro issqn = quadro(d, "issqn");
        assertThat(valor(issqn, "Retenção do ISSQN")).isEqualTo("Não Retido");
        assertThat(valor(issqn, "Alíquota Aplicada")).isEqualTo("5,00%");
        assertThat(valor(issqn, "ISSQN Apurado")).isEqualTo("R$ 10,00");
        assertThat(valor(quadro(d, "federal"), "IRRF")).isEqualTo("-");

        Quadro totais = quadro(d, "totais");
        assertThat(valor(totais, "ISSQN Retido")).isEqualTo("-");
        assertThat(valor(totais, "Total das Retenções Federais")).isEqualTo("-");
        Campo liquido = campo(totais, "Valor Líquido da NFS-e");
        assertThat(liquido.valor()).isEqualTo("R$ 200,00");
        // Sem IBS/CBS, o líquido é o valor final — e é ele que vai sombreado.
        assertThat(liquido.destaque()).isTrue();
    }

    @Test
    @DisplayName("com retenção: ISSQN retido pelo tomador, IRRF federal, líquido = serviço − retenções")
    void comRetencao() {
        DanfseResponse d = LeiauteDanfse.montar(nota(true, 2025), entregador(), loja());

        assertThat(valor(quadro(d, "issqn"), "Retenção do ISSQN")).isEqualTo("Retido pelo Tomador");
        assertThat(valor(quadro(d, "federal"), "IRRF")).isEqualTo("R$ 3,00 (1,50%)");
        Quadro totais = quadro(d, "totais");
        assertThat(valor(totais, "ISSQN Retido")).isEqualTo("R$ 10,00");
        assertThat(valor(totais, "Total das Retenções Federais")).isEqualTo("R$ 3,00");
        assertThat(valor(totais, "Valor Líquido da NFS-e")).isEqualTo("R$ 187,00");
    }

    @Test
    @DisplayName("2026: IBS 0,1% e CBS 0,9% sobre a base sem o ISSQN, destacados e sem recolhimento")
    void ibsCbsNoAnoDeTeste() {
        DanfseResponse d = LeiauteDanfse.montar(nota(false, 2026), entregador(), loja());

        Quadro ibsCbs = quadro(d, "ibscbs");
        // Base: 200,00 − 10,00 de ISSQN = 190,00.
        assertThat(valor(ibsCbs, "Base de Cálculo IBS/CBS")).isEqualTo("R$ 190,00");
        assertThat(valor(ibsCbs, "Alíquota CBS")).isEqualTo("0,90%");
        assertThat(valor(ibsCbs, "Valor CBS")).isEqualTo("R$ 1,71");
        assertThat(valor(ibsCbs, "Alíquota IBS UF")).isEqualTo("0,10%");
        assertThat(valor(ibsCbs, "Valor IBS UF")).isEqualTo("R$ 0,19");
        assertThat(valor(ibsCbs, "Valor IBS Mun.")).isEqualTo("R$ 0,00");

        Quadro totais = quadro(d, "totais");
        assertThat(valor(totais, "Valor Líquido da NFS-e")).isEqualTo("R$ 200,00");
        assertThat(valor(totais, "Total IBS/CBS")).isEqualTo("R$ 1,90");
        Campo comIbsCbs = campo(totais, "Valor Líquido da NFS-e + IBS/CBS");
        assertThat(comIbsCbs.valor()).isEqualTo("R$ 201,90");
        assertThat(comIbsCbs.destaque()).isTrue();
        assertThat(campo(totais, "Valor Líquido da NFS-e").destaque()).isFalse();
        // O valor pago continua sendo o líquido — o do extrato.
        assertThat(totais.observacao()).contains("art. 348");
    }

    @Test
    @DisplayName("antes de 2026 IBS e CBS não existiam; depois, a simulação não inventa alíquota")
    void ibsCbsForaDoAnoDeTeste() {
        Quadro antes = quadro(LeiauteDanfse.montar(nota(false, 2025), entregador(), loja()), "ibscbs");
        assertThat(antes.campos()).isEmpty();
        assertThat(antes.observacao()).startsWith("Não se aplica");

        Quadro depois = quadro(LeiauteDanfse.montar(nota(false, 2027), entregador(), loja()), "ibscbs");
        assertThat(depois.campos()).isEmpty();
        assertThat(depois.observacao()).contains("2027");
    }

    @Test
    @DisplayName("nota anterior à V20, sem chave gravada, ganha uma chave válida pela mesma regra")
    void notaSemChave() {
        NotaFiscal antiga = nota(false, 2025);
        antiga.setChaveAcesso(null);

        DanfseResponse d = LeiauteDanfse.montar(antiga, entregador(), loja());

        assertThat(ChaveDeAcessoNfse.valida(d.chaveAcesso())).isTrue();
        assertThat(d.chaveAcesso()).startsWith("4106902");
        assertThat(LeiauteDanfse.montar(antiga, entregador(), loja()).chaveAcesso())
                .isEqualTo(d.chaveAcesso());
    }

    @Test
    @DisplayName("o município emissor é o da chave gravada: mudar a cidade no perfil não muda a nota")
    void municipioPresoAChave() {
        NotaFiscal n = nota(false, 2026); // chave gravada com Curitiba
        Usuario mudou = entregador();
        mudou.setCidade("São Paulo");
        mudou.setEstado("SP");

        DanfseResponse d = LeiauteDanfse.montar(n, mudou, loja());

        assertThat(d.codigoMunicipio()).isEqualTo("4106902");
        assertThat(d.municipioEmissor()).isEqualTo("Curitiba - PR");
        assertThat(valor(quadro(d, "prestador"), "Município")).isEqualTo("Curitiba - PR");
    }

    @Test
    @DisplayName("cidade fora da tabela IBGE: código zerado e o documento diz por quê")
    void cidadeForaDaTabela() {
        Usuario e = entregador();
        e.setCidade("Cidade Inventada");
        NotaFiscal n = nota(false, 2026);
        n.setChaveAcesso(null);

        DanfseResponse d = LeiauteDanfse.montar(n, e, loja());

        assertThat(d.codigoMunicipio()).isEqualTo("0000000");
        assertThat(d.municipioEmissor()).contains("fora da tabela IBGE");
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private static NotaFiscal nota(boolean retidos, int anoCompetencia) {
        BigDecimal base = new BigDecimal("200.00");
        NotaFiscal n = new NotaFiscal();
        n.setTurnoId(202L);
        n.setPrestadorId(1L);
        n.setTomadorId(2L);
        n.setEmitidaPorId(2L);
        n.setNumero(12);
        n.setSerie("A1");
        n.setCodigoVerificacao("A1B2-C3D4");
        n.setDescricaoServico("Serviço de entrega em turno agendado — Turno Noite.");
        n.setValorServico(base);
        n.setIssAliquota(new BigDecimal("0.0500"));
        n.setIssValor(new BigDecimal("10.00"));
        n.setIrrfAliquota(new BigDecimal("0.0150"));
        n.setIrrfValor(new BigDecimal("3.00"));
        n.setTributosRetidos(retidos);
        n.setValorLiquido(retidos ? new BigDecimal("187.00") : base);
        n.setTransacaoId(92L);
        n.setOperacaoId(UUID.fromString("2f1c9c30-0000-4000-8000-000000000001"));
        n.setCompetencia(LocalDateTime.of(anoCompetencia, 8, 14, 18, 0));
        n.setEmitidaEm(LocalDateTime.of(anoCompetencia, 8, 15, 9, 30));
        n.setChaveAcesso(EmissorSimulado.chaveDeAcesso(n, entregador()));
        return n;
    }

    private static Usuario entregador() {
        Usuario u = new Usuario();
        u.setNome("Ricardo Souza");
        u.setTipo("motoboy");
        // A CNH, que não pode aparecer no campo do CPF.
        u.setDocumentoFederal("12345678900");
        u.setCidade("Curitiba");
        u.setEstado("PR");
        return u;
    }

    private static Usuario loja() {
        Usuario u = new Usuario();
        u.setNome("Cláudia Oliveira");
        u.setNomeFantasia("Hamburgueria da Cláudia");
        u.setTipo("lojista");
        u.setDocumentoFederal("12.345.678/0001-90");
        u.setCidade("Curitiba");
        u.setEstado("PR");
        u.setEnderecoComercial("Av. Água Verde, 1200 — Água Verde, Curitiba/PR");
        return u;
    }

    private static Quadro quadro(DanfseResponse d, String id) {
        return d.quadros().stream().filter(q -> q.id().equals(id)).findFirst().orElseThrow();
    }

    private static Campo campo(Quadro q, String rotulo) {
        return q.campos().stream().filter(c -> c.rotulo().equals(rotulo)).findFirst()
                .orElseThrow(() -> new AssertionError("sem o campo \"" + rotulo + "\" em " + q.id()));
    }

    private static String valor(Quadro q, String rotulo) {
        return campo(q, rotulo).valor();
    }
}
