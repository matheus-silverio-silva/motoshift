package com.motoshift.service;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.GanhoMensal;
import com.motoshift.repository.TransacaoRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * O CarteiraService nao tinha teste nenhum — e e o codigo que mexe em dinheiro.
 */
@ExtendWith(MockitoExtension.class)
class CarteiraServiceTest {

    @Mock
    private CarteiraRepository carteiraRepo;

    @Mock
    private TransacaoRepository transacaoRepo;

    @InjectMocks
    private CarteiraService service;

    @Mock
    private CobrancaService cobrancas;

    private Carteira carteiraCom(BigDecimal disponivel, String pix) {
        Carteira c = new Carteira();
        c.setUsuarioId(7L);
        c.setSaldoDisponivel(disponivel);
        c.setChavePix(pix);
        return c;
    }

    // ── ganhosDoMes ──────────────────────────────────────────────────────────

    @Test
    @DisplayName("ganhosDoMes so soma o que ja foi liquidado — pendente nao e ganho")
    void ganhosDoMes_filtraPorStatus() {
        ArgumentCaptor<StatusTransacao> status = ArgumentCaptor.forClass(StatusTransacao.class);

        when(transacaoRepo.somarPorTipoDesde(eq(7L), eq(TipoTransacao.PAGAMENTO_RECEBIDO),
                status.capture(), any()))
                .thenReturn(new BigDecimal("220.00"));

        BigDecimal ganhos = service.ganhosDoMes(7L);

        // O bug: o pagamento de turno nasce PENDENTE na finalizacao do turno,
        // muito antes de ser pago. Somar sem filtrar status mostrava ao
        // entregador dinheiro que ele ainda nao recebeu — R$ 120 de "ganhos do
        // mes" com o saldo em R$ 0.
        assertThat(status.getValue()).isEqualTo(StatusTransacao.CONCLUIDO);
        assertThat(ganhos).isEqualByComparingTo("220.00");
    }

    @Test
    @DisplayName("ganhosDoMes conta a partir do dia 1 do mes corrente")
    void ganhosDoMes_recortaNoInicioDoMes() {
        ArgumentCaptor<LocalDateTime> desde = ArgumentCaptor.forClass(LocalDateTime.class);
        when(transacaoRepo.somarPorTipoDesde(anyLong(), any(), any(), desde.capture()))
                .thenReturn(BigDecimal.TEN);

        service.ganhosDoMes(7L);

        assertThat(desde.getValue().getDayOfMonth()).isEqualTo(1);
        assertThat(desde.getValue().toLocalTime()).isEqualTo(java.time.LocalTime.MIDNIGHT);
    }

    @Test
    @DisplayName("ganhosDoMes devolve ZERO, nao null, quando nao ha lancamento")
    void ganhosDoMes_semLancamentos() {
        when(transacaoRepo.somarPorTipoDesde(anyLong(), any(), any(), any()))
                .thenReturn(null);

        assertThat(service.ganhosDoMes(7L)).isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    @DisplayName("ganhosDoMes sai sempre com 2 casas decimais")
    void ganhosDoMes_escalaDeSaida() {
        when(transacaoRepo.somarPorTipoDesde(anyLong(), any(), any(), any()))
                .thenReturn(new BigDecimal("100.5"));

        assertThat(service.ganhosDoMes(7L).scale()).isEqualTo(2);
    }


    // ── saque ────────────────────────────────────────────────────────────────
    //
    // Os testes de saque saíram daqui: o saque deixou de ser lógica deste
    // serviço. Ele agora fala com o gateway, trata a recusa e estorna, e mora
    // no CobrancaService — com cobertura no CobrancaServiceTest, contra um
    // banco de verdade. O que sobrou aqui é um invólucro de compatibilidade
    // que só reembala a resposta no formato que o app antigo espera.
    // ── grafico ──────────────────────────────────────────────────────────────

    @Test
    @DisplayName("grafico devolve uma entrada por mes pedido, com zero onde o banco nao somou nada")
    void grafico_preencheOsMeses() {
        LocalDate hoje = LocalDate.now();
        when(transacaoRepo.somarPorMesDesde(eq(7L), any(), any(), any()))
                .thenReturn(List.of(new GanhoMensal(
                        hoje.getYear(), hoje.getMonthValue(), new BigDecimal("220.00"))));

        List<Map<String, Object>> serie = service.grafico(7L, 3);

        assertThat(serie).hasSize(3);
        // O ultimo item e o mes corrente, o unico que o banco devolveu.
        assertThat(serie.get(2).get("ganhos")).isEqualTo(new BigDecimal("220.00"));
        assertThat((BigDecimal) serie.get(0).get("ganhos"))
                .isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    @DisplayName("grafico usa o mesmo corte de tipo e status do ganhosDoMes, desde o 1o mes pedido")
    void grafico_mesmoCorte() {
        ArgumentCaptor<LocalDateTime> desde = ArgumentCaptor.forClass(LocalDateTime.class);
        when(transacaoRepo.somarPorMesDesde(eq(7L), eq(CarteiraService.TIPO_GANHO),
                eq(CarteiraService.STATUS_LIQUIDADO), desde.capture()))
                .thenReturn(List.of());

        service.grafico(7L, 6);

        // O grafico e a serie historica do mesmo numero do dashboard: se um
        // filtrar pendente e o outro nao, as duas leituras discordam.
        LocalDate esperado = LocalDate.now().minusMonths(5).withDayOfMonth(1);
        assertThat(desde.getValue()).isEqualTo(esperado.atStartOfDay());
    }

    // ── obterOuCriar / buscar ────────────────────────────────────────────────

    @Test
    @DisplayName("obterOuCriar cria a carteira com usuarioId, nunca com motoboyId")
    void obterOuCriar_criaComUsuarioId() {
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.empty());
        when(carteiraRepo.save(any(Carteira.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        Carteira criada = service.obterOuCriar(7L);

        assertThat(criada.getUsuarioId()).isEqualTo(7L);
        assertThat(criada.getSaldoDisponivel()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(criada.getSaldoBloqueado()).isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    @DisplayName("o DTO nunca devolve motoboyId nulo — o app le como int nao-nulavel")
    @SuppressWarnings("deprecation")
    void buscar_espelhaMotoboyId() {
        Carteira c = carteiraCom(new BigDecimal("10.00"), null);
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.of(c));
        when(transacaoRepo.somarPorTipoDesde(anyLong(), any(), any(), any()))
                .thenReturn(BigDecimal.ZERO);
        when(transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(7L))
                .thenReturn(List.of());

        CarteiraResponse resp = service.buscar(7L);

        // `null as int` lanca TypeError em Dart: a tela de carteira nao abre.
        // A carteira aqui nunca teve motoboyId preenchido — e o caso do
        // usuario novo, que nasce so com usuario_id.
        assertThat(resp.getMotoboyId()).isEqualTo(7L);
        assertThat(resp.getUsuarioId()).isEqualTo(7L);
        assertThat(resp.getSaldoAtual()).isEqualByComparingTo("10.00");
    }
}
