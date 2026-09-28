package com.motoshift.service;

import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/** Cada selo nasce no limite e não antes dele. */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class SelosTest {

    @Autowired private Selos selos;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private AvaliacaoRepository avaliacaoRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private DashboardService dashboard;
    @Autowired private AuthService auth;

    private final LocalDateTime agora = LocalDateTime.now();
    private Usuario loja;
    private Usuario ricardo;

    @BeforeEach
    void contas() {
        loja = usuario("lojista", "Cláudia Oliveira");
        ricardo = usuario("motoboy", "Ricardo Souza");
    }

    @Nested
    @DisplayName("Entregador")
    class Entregador {

        @Test
        @DisplayName("20 turnos concluídos: com 20 sim, com 19 não")
        void turnosConcluidos() {
            for (int i = 0; i < 19; i++) concluir(agora.minusDays(2 + i), null);
            assertThat(codigos(ricardo)).doesNotContain("turnos_concluidos");
            concluir(agora.minusDays(1), null);
            assertThat(codigos(ricardo)).contains("turnos_concluidos");
        }

        @Test
        @DisplayName("30 dias sem cancelar: conta só o que ELE cancelou, e pede histórico mais velho que a janela")
        void semCancelar() {
            concluir(agora.minusDays(10), null);
            assertThat(codigos(ricardo)).as("começou há 10 dias")
                    .doesNotContain("sem_cancelar");

            concluir(agora.minusDays(40), null);
            assertThat(codigos(ricardo)).contains("sem_cancelar");

            cancelado(loja, agora.minusDays(3));
            assertThat(codigos(ricardo)).as("a loja cancelou, não ele").contains("sem_cancelar");

            cancelado(ricardo, agora.minusDays(3));
            assertThat(codigos(ricardo)).doesNotContain("sem_cancelar");
        }

        @Test
        @DisplayName("nota acima de 4,8: precisa de 10 avaliações, e 4,8 exato não é acima")
        void nota() {
            ricardo.setMediaAvaliacao(4.9);
            usuarioRepo.save(ricardo);
            for (int i = 0; i < 9; i++) avaliar(ricardo);
            assertThat(codigos(ricardo)).doesNotContain("nota_alta");
            avaliar(ricardo);
            assertThat(codigos(ricardo)).contains("nota_alta");

            ricardo.setMediaAvaliacao(4.8);
            usuarioRepo.save(ricardo);
            assertThat(codigos(ricardo)).doesNotContain("nota_alta");
        }

        @Test
        @DisplayName("pontual: 90% ou mais em 10 check-ins ou mais")
        void pontual() {
            for (int i = 0; i < 9; i++) concluir(agora.minusDays(1 + i), 5);
            assertThat(codigos(ricardo)).as("9 check-ins").doesNotContain("pontual");
            concluir(agora.minusDays(11), 25); // atrasado: 9 de 10 = 90%
            assertThat(codigos(ricardo)).contains("pontual");
            concluir(agora.minusDays(12), 30); // 9 de 11 = 81%
            assertThat(codigos(ricardo)).doesNotContain("pontual");
        }

        @Test
        @DisplayName("entregador novo não tem selo nenhum")
        void novo() {
            assertThat(selos.de(ricardo, agora)).isEmpty();
        }
    }

    @Nested
    @DisplayName("Loja")
    class Loja {

        @Test
        @DisplayName("paga gorjeta: 3 gorjetas em turnos dos últimos 90 dias")
        void pagaGorjeta() {
            gorjeta(agora.minusDays(5));
            gorjeta(agora.minusDays(20));
            gorjeta(agora.minusDays(120)); // fora da janela
            assertThat(codigos(loja)).doesNotContain("paga_gorjeta");
            gorjeta(agora.minusDays(60));
            assertThat(codigos(loja)).contains("paga_gorjeta");
        }

        @Test
        @DisplayName("contrata toda semana: um turno concluído em cada uma das últimas 4 semanas")
        void todaSemana() {
            concluirDaLoja(agora.minusDays(2));
            concluirDaLoja(agora.minusDays(9));
            concluirDaLoja(agora.minusDays(23));
            assertThat(codigos(loja)).as("falta a terceira semana").doesNotContain("toda_semana");
            concluirDaLoja(agora.minusDays(16));
            assertThat(codigos(loja)).contains("toda_semana");
        }

        @Test
        @DisplayName("a loja não recebe selo de entregador")
        void soOsDela() {
            loja.setMediaAvaliacao(4.95);
            usuarioRepo.save(loja);
            for (int i = 0; i < 10; i++) avaliar(loja);
            assertThat(codigos(loja)).containsExactly("nota_alta");
        }
    }

    @Test
    @DisplayName("cada selo leva título e critério por extenso")
    void criterio() {
        concluir(agora.minusDays(40), null);
        Selos.Selo s = selos.de(ricardo, agora).get(0);
        assertThat(s.titulo()).isEqualTo("30 dias sem cancelar");
        assertThat(s.criterio()).contains("30 dias");
    }

    @Test
    @DisplayName("os selos e a meta chegam ao painel e ao perfil público")
    void chegamAsTelas() {
        concluir(agora.minusDays(40), null);
        ricardo.setMetaMensal(new BigDecimal("2000.00"));
        usuarioRepo.save(ricardo);

        var painel = dashboard.doMotoboy(ricardo.getId());
        assertThat(painel.get("metaMensal")).isEqualTo(new BigDecimal("2000.00"));
        assertThat((List<?>) painel.get("selos")).hasSize(1);
        assertThat(auth.buscarPerfilPublico(ricardo.getId()).getSelos())
                .extracting(Selos.Selo::codigo).containsExactly("sem_cancelar");
        assertThat((List<?>) dashboard.doLojista(loja.getId()).get("selos")).isEmpty();
    }

    // ── apoio ───────────────────────────────────────────────────────────────

    private List<String> codigos(Usuario u) {
        Usuario atual = usuarioRepo.findById(u.getId()).orElseThrow();
        return selos.de(atual, agora).stream().map(Selos.Selo::codigo).toList();
    }

    private Usuario usuario(String tipo, String nome) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(tipo + "-" + System.nanoTime() + "@selos.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }

    private Turno turno(LocalDateTime inicio, StatusTurno status) {
        Turno t = new Turno();
        t.setLojistId(loja.getId());
        t.setMotoboyId(ricardo.getId());
        t.setTitulo("Turno");
        t.setRegiao("Batel");
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        t.setValorEstimado(new BigDecimal("100.00"));
        t.setStatus(status);
        return turnoRepo.save(t);
    }

    /** Turno concluído pelo Ricardo; {@code minutosDepois} é a chegada, se houve check-in. */
    private void concluir(LocalDateTime inicio, Integer minutosDepois) {
        Turno t = turno(inicio, StatusTurno.FINALIZADO);
        TurnoInscricao i = new TurnoInscricao();
        i.setTurnoId(t.getId());
        i.setMotoboyId(ricardo.getId());
        i.setStatus(StatusInscricao.FINALIZADO);
        if (minutosDepois != null) i.setCheckinEm(inicio.plusMinutes(minutosDepois));
        inscricaoRepo.save(i);
    }

    private void concluirDaLoja(LocalDateTime inicio) {
        turno(inicio, StatusTurno.FINALIZADO);
    }

    private void cancelado(Usuario quem, LocalDateTime quando) {
        Turno t = turno(quando.plusDays(1), StatusTurno.CANCELADO);
        t.setCanceladoPorId(quem.getId());
        t.setCanceladoEm(quando);
        turnoRepo.save(t);
    }

    private void avaliar(Usuario avaliado) {
        Avaliacao a = new Avaliacao();
        a.setTurnoId(turno(agora.minusDays(1), StatusTurno.FINALIZADO).getId());
        a.setAvaliadorId(avaliado.getId().equals(loja.getId()) ? ricardo.getId() : loja.getId());
        a.setAvaliadoId(avaliado.getId());
        a.setNota(5);
        avaliacaoRepo.save(a);
    }

    private void gorjeta(LocalDateTime inicioDoTurno) {
        Turno t = turno(inicioDoTurno, StatusTurno.FINALIZADO);
        Transacao g = new Transacao();
        g.setUsuarioId(loja.getId());
        g.setContraparteId(ricardo.getId());
        g.setTurnoId(t.getId());
        g.setTipo(TipoTransacao.BONUS_ENVIADO);
        g.setNatureza(NaturezaTransacao.DEBITO);
        g.setValor(new BigDecimal("10.00"));
        g.setStatus(StatusTransacao.CONCLUIDO);
        g.setOperacaoId(UUID.randomUUID());
        g.setIdempotencyKey("gorjeta:turno:" + t.getId() + ":entregador:" + ricardo.getId() + ":debito");
        transacaoRepo.save(g);
    }
}
