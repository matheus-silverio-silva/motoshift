package com.motoshift.repository;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Executa o SQL da V5 de verdade, lido do próprio arquivo de migração.
 *
 * O Flyway fica desligado em dev e em teste (as migrações são SQL PostgreSQL e o
 * H2 não executa `DO $$`, `pg_constraint` e afins), então nenhuma migração deste
 * projeto tem cobertura automática — a primeira execução real é sempre o deploy.
 * A V5 é a exceção que dá para cobrir: é INSERT ... SELECT com CASE e NOT
 * EXISTS, ANSI puro, que o H2 entende igual.
 *
 * E é a que mais precisa: um backfill errado não dá erro, ele produz dado
 * errado — e o dado aqui é quem recebeu quanto.
 *
 * O teste lê o arquivo em vez de repetir o SQL: uma cópia colada envelheceria
 * em silêncio no primeiro ajuste da migração.
 */
@DataJpaTest
@ActiveProfiles("test")
class BackfillV5Test {

    private static final String MIGRACAO = "db/migration/V5__backfill_inscricoes_legado.sql";

    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private EntityManager em;

    /**
     * Reconstroi o mundo PRE-V6 e PRE-V13.
     *
     * <p>O schema de teste nasce das entidades, ou seja, do presente — e a V5
     * roda no passado. Duas migracoes posteriores ja apagaram o que ela le e
     * escreve: a V6 tirou lojista_confirmou_em/motoboy_confirmou_em de
     * {@code turnos} (origem da copia) e a V13 as tirou de
     * {@code turno_inscricoes} (destino), quando a dupla confirmacao deixou de
     * existir.
     *
     * <p>Recriar as quatro colunas aqui nao e contornar o teste: e o que faz
     * ele exercitar a V5 que vai rodar de verdade, contra o schema que existia
     * quando ela roda. Sem isso, so restaria uma copia do SQL — que envelhece
     * em silencio — ou nenhum teste.
     */
    @BeforeEach
    void recriarColunasLegadas() {
        for (String tabela : List.of("turnos", "turno_inscricoes")) {
            em.createNativeQuery("ALTER TABLE " + tabela + " ADD COLUMN IF NOT EXISTS "
                    + "lojista_confirmou_em TIMESTAMP").executeUpdate();
            em.createNativeQuery("ALTER TABLE " + tabela + " ADD COLUMN IF NOT EXISTS "
                    + "motoboy_confirmou_em TIMESTAMP").executeUpdate();
        }
    }

    @Test
    @DisplayName("cria uma inscrição para cada turno legado, copiando pagamento e confirmações")
    void backfill_criaInscricaoParaTurnoLegado() {
        LocalDateTime confirmado = LocalDateTime.of(2026, 5, 10, 20, 0);

        Turno legado = turno(970_001L, StatusTurno.FINALIZADO, StatusPagamento.PENDENTE, confirmado);
        Turno semMotoboy = turno(null, StatusTurno.ABERTO, null, null);

        rodarV5();

        List<TurnoInscricao> doLegado = inscricaoRepo.findByTurnoId(legado.getId());
        assertThat(doLegado).hasSize(1);

        TurnoInscricao ins = doLegado.get(0);
        assertThat(ins.getMotoboyId()).isEqualTo(970_001L);
        assertThat(ins.getStatus()).isEqualTo(StatusInscricao.FINALIZADO);
        assertThat(ins.getPagamentoStatus()).isEqualTo(StatusPagamento.PENDENTE);

        // As confirmacoes sao lidas por consulta nativa: a V13 tirou as colunas
        // da entidade, e o que se confere aqui e o que a V5 gravou no banco
        // daquela epoca, nao o que a entidade de hoje sabe ler.
        Object[] confirmacoes = (Object[]) em.createNativeQuery(
                        "SELECT lojista_confirmou_em, motoboy_confirmou_em "
                        + "FROM turno_inscricoes WHERE id = :id")
                .setParameter("id", ins.getId())
                .getSingleResult();
        assertThat(confirmacoes[0]).isEqualTo(java.sql.Timestamp.valueOf(confirmado));
        assertThat(confirmacoes[1]).isNull();

        // Turno sem entregador não gera inscrição: não há quem inscrever.
        assertThat(inscricaoRepo.findByTurnoId(semMotoboy.getId())).isEmpty();
    }

    @Test
    @DisplayName("traduz o status do turno para os três valores que a inscrição aceita")
    void backfill_traduzOStatus() {
        Turno cancelado = turno(970_010L, StatusTurno.CANCELADO, null, null);
        Turno expirado  = turno(970_011L, StatusTurno.EXPIRADO, null, null);
        Turno andando   = turno(970_012L, StatusTurno.EM_ANDAMENTO, null, null);

        rodarV5();

        // Copiar cru gravaria "expirado"/"em_andamento" na inscrição, e a leitura
        // estouraria no converter — que é o erro que o CASE da V5 evita.
        assertThat(statusDaInscricaoDe(cancelado)).isEqualTo(StatusInscricao.CANCELADO);
        assertThat(statusDaInscricaoDe(expirado)).isEqualTo(StatusInscricao.ACEITO);
        assertThat(statusDaInscricaoDe(andando)).isEqualTo(StatusInscricao.ACEITO);
    }

    @Test
    @DisplayName("rodar duas vezes não duplica, e não mexe em quem já tinha inscrição")
    void backfill_eIdempotente() {
        Turno legado = turno(970_020L, StatusTurno.FINALIZADO, StatusPagamento.PAGO, null);

        Turno jaMigrado = turno(970_021L, StatusTurno.FINALIZADO, StatusPagamento.PENDENTE, null);
        TurnoInscricao existente = new TurnoInscricao();
        existente.setTurnoId(jaMigrado.getId());
        existente.setMotoboyId(970_021L);
        existente.setStatus(StatusInscricao.FINALIZADO);
        existente.setPagamentoStatus(StatusPagamento.PAGO); // diverge do turno de propósito
        inscricaoRepo.saveAndFlush(existente);

        rodarV5();
        rodarV5();

        assertThat(inscricaoRepo.findByTurnoId(legado.getId())).hasSize(1);

        // A linha que já existia fica como está — o NOT EXISTS a protege.
        List<TurnoInscricao> doMigrado = inscricaoRepo.findByTurnoId(jaMigrado.getId());
        assertThat(doMigrado).hasSize(1);
        assertThat(doMigrado.get(0).getPagamentoStatus()).isEqualTo(StatusPagamento.PAGO);
    }

    @Test
    @DisplayName("depois do backfill, a consulta de conferência da V5 devolve zero")
    void backfill_conferenciaZera() {
        turno(970_030L, StatusTurno.FINALIZADO, StatusPagamento.PENDENTE, null);
        turno(970_031L, StatusTurno.ACEITO, null, null);

        rodarV5();

        Number restantes = (Number) em.createNativeQuery(
                        "SELECT COUNT(*) FROM turnos t "
                        + "WHERE t.motoboy_id IS NOT NULL "
                        + "AND NOT EXISTS (SELECT 1 FROM turno_inscricoes i WHERE i.turno_id = t.id)")
                .getSingleResult();

        assertThat(restantes.longValue()).isZero();
    }

    // ── Apoio ────────────────────────────────────────────────

    /** Roda o INSERT da V5 — o arquivo real, não uma cópia. */
    private void rodarV5() {
        em.flush();
        em.createNativeQuery(sqlDaMigracao()).executeUpdate();
        em.flush();
        em.clear();
    }

    /**
     * O arquivo tem um comando só (o INSERT) e, depois dele, a consulta de
     * conferência comentada. O driver executa um comando por chamada, então o
     * texto é cortado no primeiro ponto e vírgula — mas só depois de tirar os
     * comentários, porque o cabeçalho da migração tem um ";" no meio de uma
     * frase e cortar por ele deixava o SQL inteiro para trás.
     */
    private String sqlDaMigracao() {
        try {
            String conteudo = new String(
                    new ClassPathResource(MIGRACAO).getInputStream().readAllBytes(),
                    StandardCharsets.UTF_8);

            String semComentarios = conteudo.lines()
                    .map(linha -> {
                        int comentario = linha.indexOf("--");
                        return comentario >= 0 ? linha.substring(0, comentario) : linha;
                    })
                    .collect(Collectors.joining(System.lineSeparator()));

            int fim = semComentarios.indexOf(';');
            assertThat(fim).as("a V5 precisa ter ao menos um comando").isPositive();
            return semComentarios.substring(0, fim);
        } catch (Exception e) {
            throw new IllegalStateException("Nao consegui ler " + MIGRACAO, e);
        }
    }

    private StatusInscricao statusDaInscricaoDe(Turno t) {
        List<TurnoInscricao> lista = inscricaoRepo.findByTurnoId(t.getId());
        assertThat(lista).as("inscricao do turno " + t.getId()).hasSize(1);
        return lista.get(0).getStatus();
    }

    private Turno turno(Long motoboyId, StatusTurno status,
                        StatusPagamento pagamento, LocalDateTime lojistaConfirmou) {
        Turno t = new Turno();
        t.setLojistId(970_000L);
        t.setMotoboyId(motoboyId);
        t.setTitulo("Turno legado " + motoboyId);
        t.setDataInicio(LocalDateTime.of(2026, 5, 10, 18, 0));
        t.setDataFim(LocalDateTime.of(2026, 5, 10, 22, 0));
        t.setValorEstimado(new BigDecimal("120.00"));
        t.setStatus(status);
        t.setPagamentoStatus(pagamento);
        Turno salvo = turnoRepo.saveAndFlush(t);

        // Confirmacao entra por SQL direto: a entidade nao tem mais o campo, e o
        // que se quer simular aqui e justamente a linha antiga do banco.
        if (lojistaConfirmou != null) {
            em.createNativeQuery(
                            "UPDATE turnos SET lojista_confirmou_em = :quando WHERE id = :id")
                    .setParameter("quando", lojistaConfirmou)
                    .setParameter("id", salvo.getId())
                    .executeUpdate();
        }
        return salvo;
    }
}
