package com.motoshift.service;

import com.motoshift.dto.RelatorioFinanceiroResponse;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * O relatório apurado pelo extrato, e o que acontece quando a IA cai.
 *
 * <p>As duas coisas que mudaram e precisam ficar presas: o gasto do lojista sai
 * do que foi PAGO (e não do {@code valorEstimado} de cada turno, que erra
 * sempre que o turno tem mais de uma vaga), e uma falha da IA deixa de derrubar
 * a resposta inteira.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class RelatorioServiceTest {

    @Autowired private RelatorioService relatorios;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    /** A IA é uma chamada de rede: nos testes ela é sempre determinística. */
    @MockBean private AnthropicService anthropic;

    private Usuario lojista;
    private Usuario entregador;
    private Turno turno;

    @BeforeEach
    void cenario() {
        lojista = conta("lojista", "Pizzaria do Teste");
        entregador = conta("motoboy", "Entregador de Teste");

        // Um turno de 2 vagas: valorEstimado diz 120, o lojista pagou 240.
        // É exatamente aqui que a apuração antiga errava.
        turno = new Turno();
        turno.setLojistId(lojista.getId());
        turno.setMotoboyId(entregador.getId());
        turno.setTitulo("Turno Dupla");
        turno.setDataInicio(LocalDate.now().minusDays(3).atTime(18, 0));
        turno.setDataFim(LocalDate.now().minusDays(3).atTime(22, 0));
        turno.setValorEstimado(new BigDecimal("120.00"));
        turno.setVagas(2);
        turno.setStatus(StatusTurno.FINALIZADO);
        turno = turnoRepo.save(turno);

        lancamento(lojista.getId(), entregador.getId(), TipoTransacao.PAGAMENTO_ENVIADO, "120.00");
        lancamento(lojista.getId(), entregador.getId(), TipoTransacao.PAGAMENTO_ENVIADO, "120.00");
        lancamento(entregador.getId(), lojista.getId(), TipoTransacao.PAGAMENTO_RECEBIDO, "120.00");
        lancamento(entregador.getId(), lojista.getId(), TipoTransacao.PAGAMENTO_RECEBIDO, "120.00");

        when(anthropic.chamarClaude(any(), any())).thenReturn("Análise gerada pela IA.");
    }

    @Test
    @DisplayName("o gasto do lojista é o que foi pago, não o valorEstimado do turno")
    void lojista_apuraPeloExtrato() {
        RelatorioFinanceiroResponse r = relatorios.doLojista(lojista.getId(), null, null);

        // valorEstimado somaria 120 (um turno); o extrato soma os 240 pagos.
        assertThat(r.numeros().get("gastoTotal")).isEqualTo(new BigDecimal("240.00"));
        assertThat(r.numeros().get("pagamentosFeitos")).isEqualTo(2);
    }

    @Test
    @DisplayName("os ganhos do entregador saem do extrato, com ticket médio e valor por hora")
    void motoboy_apuraPeloExtrato() {
        RelatorioFinanceiroResponse r = relatorios.doMotoboy(entregador.getId(), null, null);

        assertThat(r.numeros().get("ganhosTotais")).isEqualTo(new BigDecimal("240.00"));
        assertThat(r.numeros().get("ticketMedioPorTurno")).isEqualTo(new BigDecimal("120.00"));
        // Dois pagamentos de um turno de 4 horas: 8 horas contabilizadas, R$ 30/h.
        assertThat(r.numeros().get("horasTrabalhadas")).isEqualTo(8.0);
        assertThat(r.numeros().get("valorPorHora")).isEqualTo(new BigDecimal("30.00"));
    }

    @Test
    @DisplayName("a quebra por contraparte usa o nome, não o id")
    void quebraPorContraparte_usaONome() {
        RelatorioFinanceiroResponse r = relatorios.doMotoboy(entregador.getId(), null, null);

        assertThat(r.series().get("porLojista")).singleElement()
                .satisfies(i -> {
                    assertThat(i.rotulo()).isEqualTo("Pizzaria do Teste");
                    assertThat(i.total()).isEqualByComparingTo("240.00");
                    assertThat(i.quantidade()).isEqualTo(2);
                });
    }

    @Test
    @DisplayName("o dia da semana vem do início do turno, não da data do lançamento")
    void quebraPorDia_usaODiaDoTurno() {
        RelatorioFinanceiroResponse r = relatorios.doMotoboy(entregador.getId(), null, null);

        String esperado = switch (turno.getDataInicio().getDayOfWeek()) {
            case MONDAY -> "Segunda";
            case TUESDAY -> "Terça";
            case WEDNESDAY -> "Quarta";
            case THURSDAY -> "Quinta";
            case FRIDAY -> "Sexta";
            case SATURDAY -> "Sábado";
            case SUNDAY -> "Domingo";
        };
        assertThat(r.series().get("porDiaDaSemana")).singleElement()
                .satisfies(i -> assertThat(i.rotulo()).isEqualTo(esperado));
        assertThat(r.series().get("porFaixaDeHorario")).singleElement()
                .satisfies(i -> assertThat(i.rotulo()).isEqualTo("16h - 20h"));
    }

    @Test
    @DisplayName("quando a IA falha, os números continuam e a análise vem null")
    void iaFora_naoDerrubaORelatorio() {
        when(anthropic.chamarClaude(any(), any()))
                .thenThrow(new RuntimeException("timeout na API"));

        RelatorioFinanceiroResponse r = relatorios.doLojista(lojista.getId(), null, null);

        // Antes isto era um 503 e o usuário ficava sem relatório nenhum, apesar
        // de todos os números já estarem apurados.
        assertThat(r.analise()).isNull();
        assertThat(r.numeros().get("gastoTotal")).isEqualTo(new BigDecimal("240.00"));
    }

    @Test
    @DisplayName("a chave 'relatorio' continua trazendo o texto, para o app atual")
    void relatorio_ehAliasDeAnalise() {
        RelatorioFinanceiroResponse r = relatorios.doMotoboy(entregador.getId(), null, null);

        assertThat(r.relatorio()).isEqualTo(r.analise()).isEqualTo("Análise gerada pela IA.");
    }

    @Test
    @DisplayName("período informado recorta a apuração")
    void periodo_recorta() {
        RelatorioFinanceiroResponse r = relatorios.doLojista(lojista.getId(),
                LocalDate.now().minusDays(1), LocalDate.now());

        assertThat(r.numeros().get("gastoTotal")).isEqualTo(new BigDecimal("0.00"));
    }

    // -- Apoio ---------------------------------------------------------------

    private Usuario conta(String tipo, String nome) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(tipo + "-" + UUID.randomUUID() + "@relatorio.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }

    private void lancamento(Long dono, Long contraparte, TipoTransacao tipo, String valor) {
        Transacao t = new Transacao();
        t.setUsuarioId(dono);
        t.setContraparteId(contraparte);
        t.setTurnoId(turno.getId());
        t.setTipo(tipo);
        t.setNatureza(tipo == TipoTransacao.PAGAMENTO_ENVIADO
                ? NaturezaTransacao.DEBITO : NaturezaTransacao.CREDITO);
        t.setValor(new BigDecimal(valor));
        t.setDescricao(tipo.getValor() + ": " + turno.getTitulo());
        t.setStatus(StatusTransacao.CONCLUIDO);
        t.setIdempotencyKey("relatorio-teste:" + UUID.randomUUID());
        t.setCriadoEm(LocalDateTime.now().minusDays(3));
        transacaoRepo.save(t);
    }
}
