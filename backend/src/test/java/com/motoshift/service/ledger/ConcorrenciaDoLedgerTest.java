package com.motoshift.service.ledger;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.TurnoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Duas liquidações ao mesmo tempo na mesma carteira.
 *
 * <p>Este é o cenário que o {@code @Version} da {@link Carteira} existe para
 * cobrir, e que nenhum teste do projeto exercitava: dois turnos do mesmo
 * lojista sendo finalizados no mesmo instante leem o mesmo saldo, e sem a trava
 * um sobrescreveria o outro — o segundo pagamento sairia de graça e o dinheiro
 * apareceria do nada na carteira do entregador.
 *
 * <p><b>Sem {@code @Transactional} na classe, de propósito.</b> Uma transação
 * compartilhada pelas threads não reproduz concorrência nenhuma: cada execução
 * precisa abrir a sua, commitar, e disputar a versão da carteira de verdade.
 * Por isso o cenário é montado e conferido por {@link TransactionTemplate}, e
 * os dados ficam no banco ao fim do teste — são consistentes, que é o ponto.
 *
 * <p>O retry é o mesmo de produção ({@link RetentativaOtimista}), aplicado onde
 * ele é aplicado lá: em volta de quem abre a transação.
 */
@SpringBootTest
@ActiveProfiles("test")
class ConcorrenciaDoLedgerTest {

    // Tres finalizacoes ao mesmo tempo na mesma carteira: acima do que o
    // briefing pede (duas) e dentro do que a politica de retry promete cobrir.
    // Ver RetentativaOtimista — disputa pontual, nao pressao sustentada.
    private static final int TURNOS = 3;

    @Autowired private TurnoService turnos;
    @Autowired private CobrancaService cobrancas;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private RetentativaOtimista retentativa;
    @Autowired private TransactionTemplate transacoes;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    @Test
    @DisplayName("turnos do mesmo lojista finalizados em paralelo terminam consistentes")
    void liquidacoesSimultaneas_terminamConsistentes() throws Exception {
        Usuario lojista = transacoes.execute(s -> conta("lojista"));
        Usuario entregador = transacoes.execute(s -> conta("motoboy"));
        transacoes.executeWithoutResult(s -> recarregar(lojista, "5000.00"));

        List<Long> ids = new ArrayList<>();
        for (int i = 0; i < TURNOS; i++) {
            ids.add(transacoes.execute(s -> publicarComInscrito(lojista, entregador)));
        }

        // Todas as threads soltas ao mesmo tempo: sem a largada simultânea,
        // elas se enfileirariam e o teste não testaria nada.
        ExecutorService pool = Executors.newFixedThreadPool(TURNOS);
        CountDownLatch largada = new CountDownLatch(1);
        AtomicInteger sucessos = new AtomicInteger();

        List<Future<?>> execucoes = new ArrayList<>();
        for (Long id : ids) {
            execucoes.add(pool.submit(() -> {
                largada.await();
                retentativa.executar("finalizar turno " + id,
                        () -> turnos.finalizar(id, lojista.getId()));
                sucessos.incrementAndGet();
                return null;
            }));
        }
        largada.countDown();

        for (Future<?> f : execucoes) {
            f.get(30, TimeUnit.SECONDS);
        }
        pool.shutdown();
        assertThat(pool.awaitTermination(10, TimeUnit.SECONDS)).isTrue();

        assertThat(sucessos.get()).isEqualTo(TURNOS);

        transacoes.executeWithoutResult(s -> {
            Carteira doLojista = carteiraRepo.findByUsuarioId(lojista.getId()).orElseThrow();
            Carteira doEntregador = carteiraRepo.findByUsuarioId(entregador.getId()).orElseThrow();

            // 3 turnos x R$ 120: nem um centavo a mais, nem a menos.
            assertThat(doEntregador.getSaldoDisponivel()).isEqualByComparingTo("360.00");
            assertThat(doLojista.getSaldoDisponivel()).isEqualByComparingTo("4640.00");
            assertThat(doLojista.getSaldoBloqueado()).isEqualByComparingTo("0.00");

            // Um pagamento por turno, e não dois por causa de um retry.
            long pagamentos = transacaoRepo
                    .findByUsuarioIdOrderByCriadoEmDesc(entregador.getId()).stream()
                    .filter(t -> t.getTipo() == TipoTransacao.PAGAMENTO_RECEBIDO)
                    .count();
            assertThat(pagamentos).isEqualTo(TURNOS);

            // As duas contas deste teste, e so elas: o banco de teste e
            // compartilhado, e conferir tudo tornaria o verde refem da ordem
            // das classes.
            consistencia.verificarConsistencia(
                    List.of(lojista.getId(), entregador.getId())).exigirConsistente();
        });
    }

    // -- Apoio ---------------------------------------------------------------

    private Usuario conta(String tipo) {
        Usuario u = new Usuario();
        u.setNome("Conta " + tipo);
        u.setEmail(tipo + "-" + UUID.randomUUID() + "@concorrencia.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }

    private void recarregar(Usuario u, String valor) {
        Long cobranca = cobrancas.criarRecarga(u.getId(), new BigDecimal(valor), null).getId();
        cobrancas.confirmarRecarga(u.getId(), cobranca);
    }

    private Long publicarComInscrito(Usuario lojista, Usuario entregador) {
        com.motoshift.dto.TurnoRequest req = new com.motoshift.dto.TurnoRequest();
        req.setTitulo("Turno concorrente");
        req.setDataInicio(LocalDateTime.now().plusHours(3));
        req.setDataFim(LocalDateTime.now().plusHours(7));
        req.setValorEstimado(new BigDecimal("120.00"));
        req.setVagas(1);

        Long id = turnos.criar(req, lojista.getId()).getId();

        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(id);
        ins.setMotoboyId(entregador.getId());
        ins.setStatus(StatusInscricao.ACEITO);
        inscricaoRepo.save(ins);

        Turno t = turnoRepo.findById(id).orElseThrow();
        t.setMotoboyId(entregador.getId());
        turnoRepo.save(t);
        return id;
    }
}
