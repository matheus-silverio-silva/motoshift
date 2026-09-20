package com.motoshift.service.ledger;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.CarteiraService;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.TurnoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Dezenas de operações sorteadas, e as três invariantes no fim.
 *
 * <p><b>Por que um teste aleatório, num projeto cheio de testes específicos.</b>
 * Os outros testes verificam cenários que alguém pensou. Este verifica os que
 * ninguém pensou: a ordem em que publicar, finalizar, cancelar, recarregar e
 * sacar se intercalam é grande demais para ser enumerada à mão, e bugs de
 * dinheiro costumam morar justamente numa sequência que não ocorreu a ninguém —
 * cancelar um turno já liquidado, sacar entre duas publicações, finalizar um
 * turno sem inscritos.
 *
 * <p><b>Semente fixa.</b> Um teste que sorteia sem semente falha um dia e passa
 * no outro, e o relatório da falha não permite reproduzi-la. Com semente, a
 * sequência é sempre a mesma; trocar o número gera outra bateria, e é assim que
 * se procura um caso novo.
 *
 * <p>Erros de REGRA são esperados e ignorados: publicar sem saldo, sacar abaixo
 * do mínimo, finalizar um turno já encerrado. O que o teste afirma é que
 * nenhuma sequência — nem as que dão certo, nem as que são recusadas — deixa o
 * ledger inconsistente.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class InvarianteTest {

    private static final int OPERACOES = 120;
    private static final long SEMENTE = 20260920L;

    @Autowired private TurnoService turnos;
    @Autowired private CobrancaService cobrancas;
    @Autowired private CarteiraService carteiras;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private LedgerService ledger;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    private final Random sorteio = new Random(SEMENTE);

    @Test
    @DisplayName("apos 120 operacoes sorteadas, (a), (b) e (c) continuam valendo")
    void operacoesAleatorias_mantemAsInvariantes() {
        List<Usuario> lojistas = List.of(conta("lojista"), conta("lojista"));
        List<Usuario> entregadores = List.of(conta("motoboy"), conta("motoboy"), conta("motoboy"));
        entregadores.forEach(e -> carteiras.atualizarPix(e.getId(), e.getEmail()));

        List<Long> abertos = new ArrayList<>();
        int aplicadas = 0;
        int recusadas = 0;

        for (int i = 0; i < OPERACOES; i++) {
            Usuario lojista = umDe(lojistas);
            Usuario entregador = umDe(entregadores);
            try {
                switch (sorteio.nextInt(6)) {
                    case 0 -> recarregar(lojista, 200 + sorteio.nextInt(800));
                    case 1 -> recarregar(entregador, 20 + sorteio.nextInt(100));
                    case 2 -> abertos.add(publicar(lojista, entregador));
                    case 3 -> finalizar(abertos, lojista);
                    case 4 -> cancelar(abertos, lojista);
                    default -> sacar(entregador, 20 + sorteio.nextInt(150));
                }
                aplicadas++;
            } catch (ResponseStatusException e) {
                // Recusa de regra: saldo insuficiente, mínimo de saque, turno já
                // encerrado. Faz parte do sorteio e não invalida nada — o que
                // importa é que uma recusa também não deixa rastro no saldo.
                recusadas++;
            }
        }

        // Se quase tudo foi recusado, o teste não exercitou o ledger: seria um
        // verde vazio. Este piso garante que houve movimento de verdade.
        assertThat(aplicadas).isGreaterThan(OPERACOES / 2);
        assertThat(recusadas).isLessThan(OPERACOES);

        consistencia.verificarConsistencia().exigirConsistente();

        // E a conferência explícita, escrita aqui de novo: a invariante não
        // pode depender só do método que ela deveria estar verificando.
        conferirNaMao(lojistas, entregadores);
    }

    /**
     * As três invariantes recalculadas do zero, sem usar o ConsistenciaService.
     *
     * <p>Se as duas conferências compartilhassem o código, elas concordariam
     * mesmo estando as duas erradas.
     */
    private void conferirNaMao(List<Usuario> lojistas, List<Usuario> entregadores) {
        List<Usuario> todos = new ArrayList<>(lojistas);
        todos.addAll(entregadores);

        BigDecimal somaDasCarteiras = BigDecimal.ZERO;
        for (Usuario u : todos) {
            Carteira c = carteiraRepo.findByUsuarioId(u.getId()).orElse(null);
            if (c == null) continue;

            // (a) nenhum saldo negativo
            assertThat(c.getSaldoDisponivel().signum())
                    .as("disponivel de %s", u.getEmail()).isNotNegative();
            assertThat(c.getSaldoBloqueado().signum())
                    .as("bloqueado de %s", u.getEmail()).isNotNegative();

            // (b) carteira = soma dos deltas do extrato
            BigDecimal disponivel = BigDecimal.ZERO;
            BigDecimal bloqueado = BigDecimal.ZERO;
            for (Transacao t : transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(u.getId())) {
                BigDecimal v = t.getValor();
                switch (t.getTipo()) {
                    case RECARGA, PAGAMENTO_RECEBIDO, ESTORNO, BONUS -> disponivel = disponivel.add(v);
                    case SAQUE -> disponivel = disponivel.subtract(v);
                    case RESERVA -> {
                        disponivel = disponivel.subtract(v);
                        bloqueado = bloqueado.add(v);
                    }
                    case LIBERACAO_RESERVA -> {
                        disponivel = disponivel.add(v);
                        bloqueado = bloqueado.subtract(v);
                    }
                    case PAGAMENTO_ENVIADO -> bloqueado = bloqueado.subtract(v);
                }
            }
            assertThat(c.getSaldoDisponivel())
                    .as("disponivel de %s bate com o extrato", u.getEmail())
                    .isEqualByComparingTo(disponivel);
            assertThat(c.getSaldoBloqueado())
                    .as("bloqueado de %s bate com o extrato", u.getEmail())
                    .isEqualByComparingTo(bloqueado);

            somaDasCarteiras = somaDasCarteiras.add(c.getSaldoTotal());
        }

        // (c) a plataforma não cria nem destrói dinheiro
        BigDecimal entrou = BigDecimal.ZERO;
        BigDecimal saiu = BigDecimal.ZERO;
        for (Usuario u : todos) {
            for (Transacao t : transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(u.getId())) {
                if (t.getTipo() == TipoTransacao.RECARGA || t.getTipo() == TipoTransacao.ESTORNO) {
                    entrou = entrou.add(t.getValor());
                } else if (t.getTipo() == TipoTransacao.SAQUE) {
                    saiu = saiu.add(t.getValor());
                }
            }
        }
        assertThat(somaDasCarteiras)
                .as("recargas + estornos - saques")
                .isEqualByComparingTo(entrou.subtract(saiu));
    }

    // -- Operações sorteadas -------------------------------------------------

    private void recarregar(Usuario u, int valor) {
        Long id = cobrancas.criarRecarga(u.getId(), new BigDecimal(valor), null).getId();
        // Nem toda cobrança é paga: uma recarga pendente não pode virar saldo,
        // e isso também precisa ser sorteado.
        if (sorteio.nextInt(4) > 0) {
            cobrancas.confirmarRecarga(u.getId(), id);
        }
    }

    private Long publicar(Usuario lojista, Usuario entregador) {
        TurnoRequest req = new TurnoRequest();
        req.setTitulo("Turno sorteado");
        req.setDataInicio(LocalDateTime.now().plusHours(3));
        req.setDataFim(LocalDateTime.now().plusHours(7));
        req.setValorEstimado(new BigDecimal(60 + sorteio.nextInt(120)));
        req.setVagas(1 + sorteio.nextInt(3));

        Long id = turnos.criar(req, lojista.getId()).getId();

        // Nem todo turno é preenchido: vaga vazia é o caso que gera a sobra.
        if (sorteio.nextBoolean()) {
            TurnoInscricao ins = new TurnoInscricao();
            ins.setTurnoId(id);
            ins.setMotoboyId(entregador.getId());
            ins.setStatus(StatusInscricao.ACEITO);
            inscricaoRepo.save(ins);

            Turno t = turnoRepo.findById(id).orElseThrow();
            t.setMotoboyId(entregador.getId());
            turnoRepo.save(t);
        }
        return id;
    }

    private void finalizar(List<Long> abertos, Usuario lojista) {
        Long id = retirarUm(abertos);
        if (id == null) return;
        Turno t = turnoRepo.findById(id).orElseThrow();
        if (t.getMotoboyId() == null) {
            // Turno sem entregador não finaliza; devolve para a lista, porque
            // ainda pode ser cancelado ou expirar mais adiante.
            abertos.add(id);
            return;
        }
        turnos.finalizar(id, lojista.getId());
    }

    private void cancelar(List<Long> abertos, Usuario lojista) {
        Long id = retirarUm(abertos);
        if (id == null) return;
        Turno t = turnoRepo.findById(id).orElseThrow();
        if (t.getStatus() == StatusTurno.FINALIZADO || t.getStatus() == StatusTurno.CANCELADO) {
            return;
        }
        turnos.cancelar(id, lojista.getId());
    }

    private void sacar(Usuario u, int valor) {
        cobrancas.sacar(u.getId(), new BigDecimal(valor), null);
    }

    // -- Apoio ---------------------------------------------------------------

    private <T> T umDe(List<T> lista) {
        return lista.get(sorteio.nextInt(lista.size()));
    }

    private Long retirarUm(List<Long> lista) {
        if (lista.isEmpty()) return null;
        return lista.remove(sorteio.nextInt(lista.size()));
    }

    private Usuario conta(String tipo) {
        Usuario u = new Usuario();
        u.setNome("Conta " + tipo);
        u.setEmail(tipo + "-" + UUID.randomUUID() + "@invariante.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }
}
