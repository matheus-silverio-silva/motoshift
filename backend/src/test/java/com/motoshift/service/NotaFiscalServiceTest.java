package com.motoshift.service;

import com.motoshift.dto.NotaFiscalPendenteResponse;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;

/**
 * A emissão da NFS-e do turno.
 *
 * O que estes testes prendem é a parte da regra que não é óbvia lendo o
 * serviço: que os dois lados emitem o MESMO documento (e não um cada), que a
 * segunda chamada não cria uma segunda nota, e que a conta dos tributos sai do
 * valor do turno — não de um total já líquido.
 *
 * Contexto de verdade, e não mock: as consultas de pendência atravessam turno,
 * inscrição e nota, e é justamente aí que um nome derivado errado passaria
 * despercebido.
 */
@SpringBootTest
@ActiveProfiles("test")
class NotaFiscalServiceTest {

    @Autowired private NotaFiscalService notas;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    // Ids reais, gerados pelo banco no @BeforeEach — o serviço busca nome e
    // documento por eles, então inventar números não serviria.
    private Long lojista;
    private Long motoboy;
    private Long estranho;

    @BeforeEach
    void criarPessoas() {
        lojista = criarUsuario("Loja de Teste", "lojista", "12.345.678/0001-90");
        motoboy = criarUsuario("Entregador de Teste", "motoboy", "123.456.789-00");
        estranho = criarUsuario("Terceiro Curioso", "motoboy", "987.654.321-00");
    }

    @Test
    @DisplayName("a nota sai com o entregador como prestador e o lojista como tomador")
    void partesDaNota() {
        Turno turno = turnoFinalizado(new BigDecimal("120.00"));

        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThat(nota.getPrestadorId()).isEqualTo(motoboy);
        assertThat(nota.getPrestadorNome()).isEqualTo("Entregador de Teste");
        assertThat(nota.getPrestadorDocumento()).isEqualTo("123.456.789-00");
        assertThat(nota.getTomadorId()).isEqualTo(lojista);
        assertThat(nota.getTomadorNome()).isEqualTo("Loja de Teste");
        assertThat(nota.getPapel()).isEqualTo("prestador");
        assertThat(nota.getNumero()).isPositive();
        assertThat(nota.getCodigoVerificacao()).isNotBlank();
    }

    @Test
    @DisplayName("ISS e IRRF saem do valor do turno e o líquido é o que sobra")
    void tributos() {
        Turno turno = turnoFinalizado(new BigDecimal("200.00"));

        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        // 5% de 200 = 10,00 ; 1,5% de 200 = 3,00 ; líquido = 187,00
        assertThat(nota.getValorServico()).isEqualByComparingTo("200.00");
        assertThat(nota.getIssValor()).isEqualByComparingTo("10.00");
        assertThat(nota.getIrrfValor()).isEqualByComparingTo("3.00");
        assertThat(nota.getTotalTributos()).isEqualByComparingTo("13.00");
        assertThat(nota.getValorLiquido()).isEqualByComparingTo("187.00");
    }

    @Test
    @DisplayName("lojista e entregador emitem o mesmo documento, não um cada")
    void osDoisLadosEmitemAMesmaNota() {
        Turno turno = turnoFinalizado(new BigDecimal("90.00"));

        NotaFiscalService.Emissao pelaLoja = notas.emitir(turno.getId(), motoboy, lojista);
        NotaFiscalService.Emissao peloEntregador = notas.emitir(turno.getId(), motoboy, motoboy);

        assertThat(pelaLoja.criada()).isTrue();
        assertThat(peloEntregador.criada()).isFalse();
        assertThat(peloEntregador.nota().getId()).isEqualTo(pelaLoja.nota().getId());

        // O papel muda com quem pergunta; o documento, não.
        assertThat(pelaLoja.nota().getPapel()).isEqualTo("tomador");
        assertThat(peloEntregador.nota().getPapel()).isEqualTo("prestador");
    }

    @Test
    @DisplayName("turno que ainda não terminou não gera nota")
    void turnoNaoFinalizado() {
        Turno turno = turno(new BigDecimal("80.00"), StatusTurno.ACEITO);

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.emitir(turno.getId(), motoboy, motoboy))
                .withMessageContaining("finalizado");
    }

    @Test
    @DisplayName("quem não participou do turno não emite nem lê a nota")
    void estranhoNaoPassa() {
        Turno turno = turnoFinalizado(new BigDecimal("70.00"));
        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.emitir(turno.getId(), motoboy, estranho));

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.buscar(nota.getId(), estranho))
                .withMessageContaining("não é sua");
    }

    @Test
    @DisplayName("o turno sai das pendências assim que a nota é emitida")
    void pendenciaSomeDepoisDeEmitir() {
        Turno turno = turnoFinalizado(new BigDecimal("110.00"));

        assertThat(idsPendentes(motoboy, false)).contains(turno.getId());
        assertThat(idsPendentes(lojista, true)).contains(turno.getId());

        notas.emitir(turno.getId(), motoboy, motoboy);

        assertThat(idsPendentes(motoboy, false)).doesNotContain(turno.getId());
        assertThat(idsPendentes(lojista, true)).doesNotContain(turno.getId());
    }

    @Test
    @DisplayName("só o prestador cancela a própria nota")
    void cancelamento() {
        Turno turno = turnoFinalizado(new BigDecimal("60.00"));
        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThatExceptionOfType(ResponseStatusException.class)
                .isThrownBy(() -> notas.cancelar(nota.getId(), "engano", lojista))
                .withMessageContaining("prestador");

        NotaFiscalResponse cancelada = notas.cancelar(nota.getId(), "engano", motoboy);
        assertThat(cancelada.isCancelada()).isTrue();
        assertThat(cancelada.getMotivoCancelamento()).isEqualTo("engano");
    }

    @Test
    @DisplayName("a nota aparece na lista dos dois participantes, e só deles")
    void listaDosDoisLados() {
        Turno turno = turnoFinalizado(new BigDecimal("130.00"));
        NotaFiscalResponse nota = notas.emitir(turno.getId(), motoboy, motoboy).nota();

        assertThat(notas.listarDoUsuario(motoboy))
                .extracting(NotaFiscalResponse::getId).contains(nota.getId());
        assertThat(notas.listarDoUsuario(lojista))
                .extracting(NotaFiscalResponse::getId).contains(nota.getId());
        assertThat(notas.listarDoUsuario(estranho))
                .extracting(NotaFiscalResponse::getId).doesNotContain(nota.getId());
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    private List<Long> idsPendentes(Long usuarioId, boolean ehLojista) {
        return notas.pendentes(usuarioId, ehLojista).stream()
                .map(NotaFiscalPendenteResponse::getTurnoId)
                .toList();
    }

    private Turno turnoFinalizado(BigDecimal valor) {
        return turno(valor, StatusTurno.FINALIZADO);
    }

    private Turno turno(BigDecimal valor, StatusTurno status) {
        Turno t = new Turno();
        t.setLojistId(lojista);
        t.setMotoboyId(motoboy);
        t.setTitulo("Turno de teste");
        t.setRegiao("Centro, Curitiba");
        t.setDataInicio(LocalDateTime.now().minusDays(1));
        t.setDataFim(LocalDateTime.now().minusDays(1).plusHours(4));
        t.setValorEstimado(valor);
        t.setRaioEntregaKm(8.0);
        t.setStatus(status);
        Turno salvo = turnoRepo.save(t);

        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(salvo.getId());
        ins.setMotoboyId(motoboy);
        ins.setStatus(StatusInscricao.ACEITO);
        inscricaoRepo.save(ins);

        return salvo;
    }

    private Long criarUsuario(String nome, String tipo, String documento) {
        Usuario u = new Usuario();
        u.setNome(nome);
        // E-mail único por execução: a coluna tem restrição de unicidade e o
        // @BeforeEach roda uma vez por teste.
        // Fora do sufixo da massa de demonstracao, que o reset apagaria.
        u.setEmail("nf-" + System.nanoTime() + "@notafiscal.test");
        u.setSenha("nao-usado-neste-teste");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        u.setDocumentoFederal(documento);
        return usuarioRepo.save(u).getId();
    }
}
