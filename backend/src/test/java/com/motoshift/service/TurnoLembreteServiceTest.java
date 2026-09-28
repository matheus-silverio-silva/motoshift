package com.motoshift.service;

import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** O lembrete de 1 hora: quem recebe, com que texto, e uma vez só. */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class TurnoLembreteServiceTest {

    @Autowired private TurnoLembreteService lembretes;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;

    // Um "agora" bem longe do relógio de verdade: nenhum turno de outro teste
    // cai nesta janela.
    private final LocalDateTime agora = LocalDateTime.of(2031, 3, 14, 17, 15);

    private Usuario loja;
    private Usuario ricardo;
    private Usuario lucas;

    @BeforeEach
    void contas() {
        loja = usuario("lojista", "Cláudia Oliveira", "Hamburgueria da Cláudia");
        ricardo = usuario("motoboy", "Ricardo Souza", null);
        lucas = usuario("motoboy", "Lucas Mendes", null);
    }

    @Test
    @DisplayName("turno aceito que começa em 45 min: o entregador e a loja são lembrados")
    void lembraOsDois() {
        Turno t = turno(agora.plusMinutes(45), StatusTurno.ACEITO);
        inscrever(t, ricardo, null);

        lembretes.lembrar(agora);

        assertThat(de(ricardo)).extracting(Notificacao::getMensagem).containsExactly(
                "\"Turno Noite\" na Hamburgueria da Cláudia começa às 18:00 — daqui a 45 min.");
        assertThat(de(loja)).extracting(Notificacao::getMensagem).containsExactly(
                "\"Turno Noite\" começa às 18:00, com Ricardo.");
        assertThat(de(ricardo).get(0).getReferenciaTipo()).isEqualTo("turno");
        assertThat(de(ricardo).get(0).getReferenciaId()).isEqualTo(t.getId());
    }

    @Test
    @DisplayName("rodar de novo não duplica — nem 5 minutos depois")
    void naoDuplica() {
        Turno t = turno(agora.plusMinutes(45), StatusTurno.ACEITO);
        inscrever(t, ricardo, null);

        lembretes.lembrar(agora);
        lembretes.lembrar(agora.plusMinutes(5));
        lembretes.lembrar(agora.plusMinutes(10));

        assertThat(de(ricardo)).hasSize(1);
        assertThat(de(loja)).hasSize(1);
    }

    @Test
    @DisplayName("multi-vaga: cada entregador recebe o seu; a loja, um só com a equipe")
    void multiVaga() {
        Turno t = turno(agora.plusMinutes(30), StatusTurno.ABERTO);
        inscrever(t, ricardo, null);
        inscrever(t, lucas, null);

        lembretes.lembrar(agora);

        assertThat(de(ricardo)).hasSize(1);
        assertThat(de(lucas)).hasSize(1);
        assertThat(de(loja)).extracting(Notificacao::getMensagem)
                .containsExactly("\"Turno Noite\" começa às 17:45, com Ricardo e mais 1.");
    }

    @Test
    @DisplayName("fora da janela, sem inscrito, ou com check-in feito: nada")
    void quemNaoELembrado() {
        Turno longe = turno(agora.plusHours(2), StatusTurno.ACEITO);
        inscrever(longe, ricardo, null);
        turno(agora.plusMinutes(40), StatusTurno.ABERTO); // ninguém inscrito
        Turno chegou = turno(agora.plusMinutes(20), StatusTurno.EM_ANDAMENTO);
        inscrever(chegou, lucas, agora.minusMinutes(5));

        assertThat(lembretes.lembrar(agora)).isZero();
        assertThat(de(ricardo)).isEmpty();
        assertThat(de(lucas)).isEmpty();
        assertThat(de(loja)).isEmpty();
    }

    @Test
    @DisplayName("turno cancelado ou finalizado não é lembrado")
    void soTurnoValendo() {
        Turno cancelado = turno(agora.plusMinutes(30), StatusTurno.CANCELADO);
        inscrever(cancelado, ricardo, null);

        assertThat(lembretes.lembrar(agora)).isZero();
    }

    private List<Notificacao> de(Usuario u) {
        return notificacaoRepo.findTop50ByUsuarioIdOrderByCriadoEmDesc(u.getId()).stream()
                .filter(n -> TurnoLembreteService.TIPO.equals(n.getTipo()))
                .toList();
    }

    private Usuario usuario(String tipo, String nome, String fantasia) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(tipo + "-" + System.nanoTime() + "@lembrete.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        u.setNomeFantasia(fantasia);
        return usuarioRepo.save(u);
    }

    private Turno turno(LocalDateTime inicio, StatusTurno status) {
        Turno t = new Turno();
        t.setLojistId(loja.getId());
        t.setTitulo("Turno Noite");
        t.setRegiao("Água Verde, Curitiba");
        t.setDataInicio(inicio);
        t.setDataFim(inicio.plusHours(4));
        t.setValorEstimado(new BigDecimal("130.00"));
        t.setVagas(3);
        t.setStatus(status);
        return turnoRepo.save(t);
    }

    private void inscrever(Turno t, Usuario entregador, LocalDateTime checkin) {
        TurnoInscricao i = new TurnoInscricao();
        i.setTurnoId(t.getId());
        i.setMotoboyId(entregador.getId());
        i.setStatus(StatusInscricao.ACEITO);
        i.setCheckinEm(checkin);
        inscricaoRepo.save(i);
    }
}
