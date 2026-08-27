package com.motoshift.service;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
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
import java.time.LocalDateTime;
import java.util.Collection;
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

    private Carteira carteiraCom(BigDecimal disponivel, String pix) {
        Carteira c = new Carteira();
        c.setUsuarioId(7L);
        c.setSaldoDisponivel(disponivel);
        c.setChavePix(pix);
        return c;
    }

    private Transacao transacao(String tipo, String status, String valor,
                                LocalDateTime quando) {
        Transacao t = new Transacao();
        t.setUsuarioId(7L);
        t.setTipo(tipo);
        t.setStatus(status);
        t.setValor(new BigDecimal(valor));
        // criadoEm so e preenchido no @PrePersist; nos testes vai na mao.
        org.springframework.test.util.ReflectionTestUtils
                .setField(t, "criadoEm", quando);
        return t;
    }

    // ── ganhosDoMes ──────────────────────────────────────────────────────────

    @Test
    @DisplayName("ganhosDoMes so soma o que ja foi liquidado — pendente nao e ganho")
    void ganhosDoMes_filtraPorStatus() {
        ArgumentCaptor<Collection<String>> status = statusCaptor();

        when(transacaoRepo.somarPorTipoDesde(eq(7L), any(), status.capture(), any()))
                .thenReturn(new BigDecimal("220.00"));

        BigDecimal ganhos = service.ganhosDoMes(7L);

        // O bug: a transacao de tipo "turno" nasce PENDENTE na finalizacao do
        // turno, muito antes do pagamento. Somar sem filtrar status mostrava ao
        // entregador dinheiro que ele ainda nao recebeu — R$ 120 de "ganhos do
        // mes" com o saldo em R$ 0.
        assertThat(status.getValue())
                .containsExactlyInAnyOrder("processado", "concluido")
                .doesNotContain("pendente");
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

    @Test
    @DisplayName("saque debita o disponivel e registra a transacao")
    void saque_caminhoFeliz() {
        Carteira c = carteiraCom(new BigDecimal("320.00"), "ricardo@pix.com");
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.of(c));

        Map<String, Object> resp = service.saque(7L, new BigDecimal("100.00"));

        assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("220.00");
        assertThat(resp.get("novoSaldo")).isEqualTo(new BigDecimal("220.00"));

        ArgumentCaptor<Transacao> tx = ArgumentCaptor.forClass(Transacao.class);
        verify(transacaoRepo).save(tx.capture());
        assertThat(tx.getValue().getTipo()).isEqualTo("saque");
        assertThat(tx.getValue().getStatus()).isEqualTo("concluido");
        assertThat(tx.getValue().getUsuarioId()).isEqualTo(7L);
    }

    @Test
    @DisplayName("saque de exatamente R$ 20,00 passa — o minimo e inclusivo")
    void saque_noLimiteMinimo() {
        // compareTo e nao equals: new BigDecimal("20.0").equals(new
        // BigDecimal("20.00")) e false por causa da escala, e o limite passaria
        // a rejeitar um valor valido.
        Carteira c = carteiraCom(new BigDecimal("50.00"), "pix@x.com");
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.of(c));

        assertThatNoException()
                .isThrownBy(() -> service.saque(7L, new BigDecimal("20.000")));
    }

    @Test
    @DisplayName("saque abaixo do minimo e recusado")
    void saque_abaixoDoMinimo() {
        assertThatThrownBy(() -> service.saque(7L, new BigDecimal("19.99")))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("mínimo");

        verifyNoInteractions(carteiraRepo);
    }

    @Test
    @DisplayName("saque sem chave Pix e recusado antes de mexer no saldo")
    void saque_semChavePix() {
        Carteira c = carteiraCom(new BigDecimal("500.00"), null);
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.of(c));

        assertThatThrownBy(() -> service.saque(7L, new BigDecimal("100.00")))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("Pix");

        assertThat(c.getSaldoDisponivel()).isEqualByComparingTo("500.00");
        verify(transacaoRepo, never()).save(any());
    }

    @Test
    @DisplayName("saque nao alcanca o saldo bloqueado — ele esta preso em turnos")
    void saque_naoTocaNoBloqueado() {
        Carteira c = carteiraCom(new BigDecimal("50.00"), "pix@x.com");
        c.setSaldoBloqueado(new BigDecimal("500.00"));
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.of(c));

        // Patrimonio total 550, disponivel 50: sacar 100 tem que falhar.
        assertThatThrownBy(() -> service.saque(7L, new BigDecimal("100.00")))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("insuficiente");

        assertThat(c.getSaldoBloqueado()).isEqualByComparingTo("500.00");
        verify(transacaoRepo, never()).save(any());
    }

    @Test
    @DisplayName("saque em carteira inexistente da 404, nao NullPointerException")
    void saque_carteiraInexistente() {
        when(carteiraRepo.findByUsuarioId(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.saque(7L, new BigDecimal("100.00")))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    @DisplayName("saque sem valor da 400")
    void saque_valorNulo() {
        assertThatThrownBy(() -> service.saque(7L, null))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // ── grafico ──────────────────────────────────────────────────────────────

    @Test
    @DisplayName("grafico agrupa por mes e devolve uma entrada por mes pedido")
    void grafico_agrupaPorMes() {
        LocalDateTime agora = LocalDateTime.now();
        when(transacaoRepo.findByUsuarioIdAndTipoInAndStatusInOrderByCriadoEmDesc(
                eq(7L), any(), any()))
                .thenReturn(List.of(
                        transacao("turno", "concluido", "120.00", agora),
                        transacao("turno", "concluido", "100.00", agora)));

        List<Map<String, Object>> serie = service.grafico(7L, 3);

        assertThat(serie).hasSize(3);
        // O ultimo item e o mes corrente, onde estao as duas transacoes.
        assertThat(serie.get(2).get("ganhos")).isEqualTo(new BigDecimal("220.00"));
        assertThat((BigDecimal) serie.get(0).get("ganhos"))
                .isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    @DisplayName("grafico usa o mesmo corte de status do ganhosDoMes")
    void grafico_filtraPorStatus() {
        ArgumentCaptor<Collection<String>> status = statusCaptor();
        when(transacaoRepo.findByUsuarioIdAndTipoInAndStatusInOrderByCriadoEmDesc(
                eq(7L), any(), status.capture()))
                .thenReturn(List.of());

        service.grafico(7L, 6);

        // O grafico e a serie historica do mesmo numero do dashboard: se um
        // filtrar pendente e o outro nao, as duas leituras discordam.
        assertThat(status.getValue())
                .containsExactlyInAnyOrderElementsOf(CarteiraService.STATUS_LIQUIDADO);
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

    @SuppressWarnings("unchecked")
    private ArgumentCaptor<Collection<String>> statusCaptor() {
        return ArgumentCaptor.forClass((Class<Collection<String>>) (Class<?>) Collection.class);
    }
}
