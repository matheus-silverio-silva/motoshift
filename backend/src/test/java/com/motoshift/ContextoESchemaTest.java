package com.motoshift;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.service.CarteiraService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * O unico teste que sobe o contexto inteiro do Spring.
 *
 * Cobre o que teste de unidade com mock nao alcanca:
 *   - todos os beans se conectam (inclusive o @RestControllerAdvice novo);
 *   - as consultas derivadas e as @Query sao validas — o Spring Data resolve
 *     os nomes na criacao dos beans, entao um metodo mal nomeado derruba o
 *     contexto aqui em vez de so em producao;
 *   - o filtro de status do ganhosDoMes funciona contra um banco de verdade,
 *     nao contra um mock que devolve o que mandaram.
 *
 * O QUE ESTE TESTE **NAO** COBRE, e continua sendo o buraco apontado na
 * auditoria: as migracoes Flyway. As migracoes V1..V4 sao SQL PostgreSQL
 * (blocos `DO $$`, consultas a `pg_constraint`, `ALTER COLUMN ... SET NOT
 * NULL`) e o H2 nao as executa nem em modo de compatibilidade. Rodar Flyway de
 * verdade contra o schema exige um PostgreSQL — Testcontainers (precisa de
 * Docker) ou um banco de CI. Enquanto isso nao existir, a primeira validacao
 * do `ddl-auto=validate` contra o SQL continua sendo o boot de producao.
 */
@SpringBootTest
@ActiveProfiles("test")
class ContextoESchemaTest {

    /// Id alto de proposito: o DataInitializer semeia ids baixos.
    private static final Long USUARIO = 999_001L;

    @Autowired
    private CarteiraService carteiraService;

    @Autowired
    private CarteiraRepository carteiraRepo;

    @Autowired
    private TransacaoRepository transacaoRepo;

    @Test
    @DisplayName("o contexto sobe e as consultas do extrato sao validas")
    void contextoSobe() {
        assertThat(carteiraService).isNotNull();

        // Executa as duas consultas que mudaram. Nao interessa o resultado:
        // interessa que o JPQL e o nome derivado compilam contra o schema.
        assertThat(transacaoRepo.somarPorTipoDesde(
                USUARIO,
                CarteiraService.TIPOS_GANHO,
                CarteiraService.STATUS_LIQUIDADO,
                LocalDateTime.now().minusYears(1)))
                .isNotNull();

        assertThat(transacaoRepo.findByUsuarioIdAndTipoInAndStatusInOrderByCriadoEmDesc(
                USUARIO, CarteiraService.TIPOS_GANHO, CarteiraService.STATUS_LIQUIDADO))
                .isNotNull();
    }

    @Test
    @DisplayName("ganhos do mes ignoram a transacao pendente, contra o banco de verdade")
    void ganhosDoMesIgnoramPendente() {
        Long usuario = USUARIO + 1;
        carteiraService.obterOuCriar(usuario);

        salvar(usuario, "turno", "concluido", "100.00");
        salvar(usuario, "turno", "pendente", "125.00");

        // O turno pendente foi finalizado mas ainda nao foi pago. Antes do
        // filtro de status ele entrava na conta, e o entregador via R$ 225 de
        // "ganhos do mes" com R$ 0 de saldo.
        assertThat(carteiraService.ganhosDoMes(usuario))
                .isEqualByComparingTo("100.00");
    }

    @Test
    @DisplayName("o grafico usa o mesmo corte — as duas leituras nao podem discordar")
    void graficoConcordaComGanhosDoMes() {
        Long usuario = USUARIO + 2;
        carteiraService.obterOuCriar(usuario);

        salvar(usuario, "pagamento_recebido", "concluido", "90.00");
        salvar(usuario, "pagamento_recebido", "pendente", "40.00");

        BigDecimal doMes = carteiraService.ganhosDoMes(usuario);
        List<java.util.Map<String, Object>> serie = carteiraService.grafico(usuario, 1);

        assertThat(doMes).isEqualByComparingTo("90.00");
        assertThat((BigDecimal) serie.get(0).get("ganhos")).isEqualByComparingTo(doMes);
    }

    @Test
    @DisplayName("carteira nova responde com motoboyId preenchido, nunca nulo")
    @SuppressWarnings("deprecation")
    void carteiraNovaNaoQuebraOApp() {
        Long usuario = USUARIO + 3;

        // Usuario novo: a carteira nasce so com usuario_id. A coluna legada
        // motoboy_id fica nula, e o app le `motoboyId` como int NAO-nulavel.
        CarteiraResponse resp = carteiraService.buscar(usuario);

        Carteira gravada = carteiraRepo.findByUsuarioId(usuario).orElseThrow();
        assertThat(gravada.getMotoboyId())
                .as("a coluna legada segue nula — o espelho e no DTO, nao no banco")
                .isNull();

        assertThat(resp.getMotoboyId()).isEqualTo(usuario);
        assertThat(resp.getSaldoAtual()).isNotNull();
        assertThat(resp.getGanhosMensais()).isNotNull();
    }

    private void salvar(Long usuario, String tipo, String status, String valor) {
        Transacao t = new Transacao();
        t.setUsuarioId(usuario);
        t.setTipo(tipo);
        t.setStatus(status);
        t.setValor(new BigDecimal(valor));
        transacaoRepo.save(t);

        // criadoEm vem do @PrePersist (agora). Se o teste rodar no dia 1 antes
        // da meia-noite... nao ha esse caso: o recorte e o inicio do mes, e
        // "agora" esta sempre dentro dele.
        assertThat(t.getCriadoEm())
                .isAfterOrEqualTo(LocalDate.now().withDayOfMonth(1).atStartOfDay());
    }
}
