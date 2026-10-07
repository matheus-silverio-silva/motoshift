package com.motoshift.service;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.support.PostgresDeTeste;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

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
 * A última vaga não pode ser de dois (SCRUM-27).
 *
 * <p>{@code TurnoService.aceitar} conta as inscrições e grava em seguida. Sem
 * trava, oito entregadores que tocassem "Aceitar" na mesma vaga ao mesmo tempo
 * liam os oito "0 de 1 ocupada" e entravam os oito: a unicidade da inscrição é
 * por (turno, entregador), então não barrava nada, e o turno não tinha
 * {@code @Version}. A correção é a linha do turno travada durante o aceite
 * ({@code TurnoRepository.buscarTravandoAsVagas}).
 *
 * <p><b>Em PostgreSQL, e não no H2 dos outros testes.</b> A trava é um
 * {@code SELECT ... FOR UPDATE}, e o que importa é como o banco de produção se
 * comporta com ele: quem esperou a trava relê a linha já commitada (READ
 * COMMITTED) e encontra o turno lotado. É esse detalhe que faz o segundo
 * aceite virar 409, e ele é do PostgreSQL.
 *
 * <p><b>Sem {@code @Transactional} na classe</b>, pelo mesmo motivo do
 * {@code ConcorrenciaDoLedgerTest}: uma transação compartilhada pelas threads
 * não disputa nada. Cada aceite abre a sua, como cada requisição HTTP.
 */
@SpringBootTest
@ActiveProfiles("test")
class AceiteConcorrentePostgresTest {

    private static final int ENTREGADORES = 8;

    @DynamicPropertySource
    static void postgres(DynamicPropertyRegistry props) {
        String url = PostgresDeTeste.bancoNovo("aceite_concorrente");
        props.add("spring.datasource.url", () -> url);
        props.add("spring.datasource.username", () -> "postgres");
        props.add("spring.datasource.password", () -> "");
        props.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        props.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.PostgreSQLDialect");
        props.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
        props.add("spring.flyway.enabled", () -> "true");
        props.add("spring.flyway.locations", () -> "classpath:db/migration");
    }

    @Autowired private TurnoService turnos;
    @Autowired private CobrancaService cobrancas;
    @Autowired private TransactionTemplate transacoes;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private UsuarioRepository usuarioRepo;

    @Test
    @DisplayName("8 entregadores aceitam a mesma vaga ao mesmo tempo: 1 entra, 7 recebem 409")
    void ultimaVaga_eDeUmSo() throws Exception {
        Usuario lojista = transacoes.execute(s -> conta("lojista"));
        transacoes.executeWithoutResult(s -> recarregar(lojista, "500.00"));
        Long turnoId = transacoes.execute(s -> publicarDeUmaVaga(lojista));
        List<Usuario> entregadores = new ArrayList<>();
        for (int i = 0; i < ENTREGADORES; i++) {
            entregadores.add(transacoes.execute(s -> conta("motoboy")));
        }

        // Todas as threads soltas ao mesmo tempo: sem a largada simultânea
        // elas se enfileirariam sozinhas e o teste não disputaria nada.
        ExecutorService pool = Executors.newFixedThreadPool(ENTREGADORES);
        CountDownLatch largada = new CountDownLatch(1);
        AtomicInteger aceitos = new AtomicInteger();
        AtomicInteger recusados409 = new AtomicInteger();

        List<Future<?>> execucoes = new ArrayList<>();
        for (Usuario e : entregadores) {
            execucoes.add(pool.submit(() -> {
                largada.await();
                try {
                    turnos.aceitar(turnoId, e.getId());
                    aceitos.incrementAndGet();
                } catch (ResponseStatusException recusa) {
                    // Só o 409 é resposta esperada para quem perdeu a vaga.
                    // Qualquer outra coisa (um 500 de unicidade, um erro de
                    // trava) sobe pelo Future e derruba o teste.
                    if (recusa.getStatusCode().value() != 409) throw recusa;
                    recusados409.incrementAndGet();
                }
                return null;
            }));
        }
        largada.countDown();

        for (Future<?> f : execucoes) {
            f.get(30, TimeUnit.SECONDS);
        }
        pool.shutdown();
        assertThat(pool.awaitTermination(10, TimeUnit.SECONDS)).isTrue();

        assertThat(aceitos.get()).as("quem entrou").isEqualTo(1);
        assertThat(recusados409.get()).as("quem recebeu 409").isEqualTo(ENTREGADORES - 1);

        transacoes.executeWithoutResult(s -> {
            // Uma inscrição, e não oito: é o que o lojista reservou e vai pagar.
            assertThat(inscricaoRepo.findByTurnoId(turnoId))
                    .singleElement()
                    .satisfies(i -> assertThat(i.getStatus()).isEqualTo(StatusInscricao.ACEITO));

            Turno turno = turnoRepo.findById(turnoId).orElseThrow();
            assertThat(turno.getStatus()).isEqualTo(StatusTurno.ACEITO);
            // O "principal" é quem ficou com a vaga, e mais ninguém.
            assertThat(turno.getMotoboyId())
                    .isEqualTo(inscricaoRepo.findByTurnoId(turnoId).get(0).getMotoboyId());
        });
    }

    @Test
    @DisplayName("turno de 3 vagas disputado por 8: entram exatamente 3")
    void variasVagas_naoPassamDoLimite() throws Exception {
        Usuario lojista = transacoes.execute(s -> conta("lojista"));
        transacoes.executeWithoutResult(s -> recarregar(lojista, "500.00"));
        Long turnoId = transacoes.execute(s -> publicar(lojista, 3));
        List<Usuario> entregadores = new ArrayList<>();
        for (int i = 0; i < ENTREGADORES; i++) {
            entregadores.add(transacoes.execute(s -> conta("motoboy")));
        }

        ExecutorService pool = Executors.newFixedThreadPool(ENTREGADORES);
        CountDownLatch largada = new CountDownLatch(1);
        AtomicInteger aceitos = new AtomicInteger();
        List<Future<?>> execucoes = new ArrayList<>();
        for (Usuario e : entregadores) {
            execucoes.add(pool.submit(() -> {
                largada.await();
                try {
                    turnos.aceitar(turnoId, e.getId());
                    aceitos.incrementAndGet();
                } catch (ResponseStatusException recusa) {
                    if (recusa.getStatusCode().value() != 409) throw recusa;
                }
                return null;
            }));
        }
        largada.countDown();
        for (Future<?> f : execucoes) {
            f.get(30, TimeUnit.SECONDS);
        }
        pool.shutdown();
        assertThat(pool.awaitTermination(10, TimeUnit.SECONDS)).isTrue();

        assertThat(aceitos.get()).isEqualTo(3);
        transacoes.executeWithoutResult(s -> {
            assertThat(inscricaoRepo.countByTurnoIdAndStatus(turnoId, StatusInscricao.ACEITO))
                    .isEqualTo(3);
            assertThat(turnoRepo.findById(turnoId).orElseThrow().getStatus())
                    .isEqualTo(StatusTurno.ACEITO);
        });
    }

    // -- Apoio ---------------------------------------------------------------

    private Usuario conta(String tipo) {
        Usuario u = new Usuario();
        u.setNome("Conta " + tipo);
        u.setEmail(tipo + "-" + UUID.randomUUID() + "@aceite.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        return usuarioRepo.save(u);
    }

    private void recarregar(Usuario u, String valor) {
        Long cobranca = cobrancas.criarRecarga(u.getId(), new BigDecimal(valor), null).getId();
        cobrancas.confirmarRecarga(u.getId(), cobranca);
    }

    private Long publicarDeUmaVaga(Usuario lojista) {
        return publicar(lojista, 1);
    }

    private Long publicar(Usuario lojista, int vagas) {
        TurnoRequest req = new TurnoRequest();
        req.setTitulo("Turno disputado");
        req.setDataInicio(LocalDateTime.now().plusHours(3));
        req.setDataFim(LocalDateTime.now().plusHours(7));
        req.setValorEstimado(new BigDecimal("100.00"));
        req.setVagas(vagas);
        return turnos.criar(req, lojista.getId()).getId();
    }
}
