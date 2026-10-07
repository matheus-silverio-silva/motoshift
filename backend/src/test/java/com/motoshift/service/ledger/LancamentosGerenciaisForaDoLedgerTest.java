package com.motoshift.service.ledger;

import com.motoshift.dto.LancamentoGerencialRequest;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.CobrancaRepository;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.service.DreService;
import com.motoshift.service.LancamentoGerencialService;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * O lançamento gerencial não é dinheiro da plataforma: criar, editar e excluir
 * não mexe em saldo nem em extrato (RF13 / SCRUM-47).
 *
 * <p>Vizinho do {@code InvarianteTest} de propósito. As três invariantes do
 * ledger valem porque cada linha do extrato tem um movimento de saldo do outro
 * lado; o custo que o usuário digita não tem. Este teste é o que impede alguém
 * de, um dia, "aproveitar" o {@code LedgerService} para registrar combustível.
 *
 * <p>O dinheiro do cenário é de verdade — recarga, publicação com reserva,
 * finalização com pagamento —, para haver saldo e extrato a comparar.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class LancamentosGerenciaisForaDoLedgerTest {

    @Autowired private CenarioFinanceiro cenario;
    @Autowired private LancamentoGerencialService gerenciais;
    @Autowired private DreService dre;
    @Autowired private ConsistenciaService consistencia;
    @Autowired private CarteiraRepository carteiraRepo;
    @Autowired private TransacaoRepository transacaoRepo;
    @Autowired private CobrancaRepository cobrancaRepo;
    @Autowired private NotaFiscalRepository notaRepo;

    /** O que o ledger sabe: saldos das duas contas e o tamanho das três tabelas dele. */
    private record Retrato(BigDecimal disponivelDaLoja, BigDecimal bloqueadoDaLoja,
                           BigDecimal disponivelDoEntregador, BigDecimal bloqueadoDoEntregador,
                           long transacoes, long cobrancas, long notas) {}

    @Test
    @DisplayName("criar, editar e excluir lançamentos gerenciais não altera saldo, extrato nem as invariantes")
    void foraDoLedger() {
        Usuario loja = cenario.conta("lojista", "Loja do ledger", "12345678000190");
        Usuario entregador = cenario.conta("motoboy", "Entregador do ledger", "12345678900");
        Turno turno = cenario.turnoPago(loja.getId(), "120.00", entregador.getId());
        // Sobra uma reserva aberta, para haver saldo bloqueado a conferir.
        cenario.recarregar(loja.getId(), "300.00");
        cenario.publicar(loja.getId(), "100.00", 2);

        Retrato antes = retrato(loja, entregador);
        assertThat(antes.disponivelDoEntregador()).isEqualByComparingTo("120.00");
        assertThat(antes.bloqueadoDaLoja()).isEqualByComparingTo("200.00");
        List<Long> contas = List.of(loja.getId(), entregador.getId());
        consistencia.verificarConsistencia(contas).exigirConsistente();

        // Criar — inclusive um valor maior do que qualquer saldo: não é débito.
        Long gasolina = gerenciais.criar(entregador.getId(), "motoboy",
                pedido("combustivel", "45.00", turno.getId())).id();
        Long manutencao = gerenciais.criar(entregador.getId(), "motoboy",
                pedido("manutencao", "9999.00", null)).id();
        Long taxa = gerenciais.criar(loja.getId(), "lojista",
                pedido("taxa_de_entrega_cobrada", "50000.00", turno.getId())).id();
        assertThat(retrato(loja, entregador)).isEqualTo(antes);

        // A DRE os enxerga — é para isso que existem.
        assertThat(dre.dre(entregador.getId(), "motoboy", LocalDate.now(), LocalDate.now())
                .resultado()).isEqualByComparingTo("-9924.00");
        assertThat(retrato(loja, entregador)).isEqualTo(antes);

        // Editar.
        gerenciais.atualizar(manutencao, entregador.getId(), "motoboy",
                pedido("manutencao", "80.00", null));
        gerenciais.atualizar(taxa, loja.getId(), "lojista",
                pedido("taxa_de_entrega_cobrada", "208.00", turno.getId()));
        assertThat(retrato(loja, entregador)).isEqualTo(antes);

        // Excluir.
        gerenciais.excluir(gasolina, entregador.getId());
        gerenciais.excluir(manutencao, entregador.getId());
        gerenciais.excluir(taxa, loja.getId());
        assertThat(retrato(loja, entregador)).isEqualTo(antes);

        // E o ledger fecha como fechava: carteira = extrato, nada criado nem
        // destruído. (Só as duas contas do cenário: o banco de teste é dividido
        // com outras classes, como no InvarianteTest.)
        consistencia.verificarConsistencia(contas).exigirConsistente();
    }

    private Retrato retrato(Usuario loja, Usuario entregador) {
        Carteira daLoja = carteiraRepo.findByUsuarioId(loja.getId()).orElseThrow();
        Carteira doEntregador = carteiraRepo.findByUsuarioId(entregador.getId()).orElseThrow();
        return new Retrato(
                daLoja.getSaldoDisponivel(), daLoja.getSaldoBloqueado(),
                doEntregador.getSaldoDisponivel(), doEntregador.getSaldoBloqueado(),
                transacaoRepo.count(), cobrancaRepo.count(), notaRepo.count());
    }

    private static LancamentoGerencialRequest pedido(String categoria, String valor, Long turnoId) {
        LancamentoGerencialRequest req = new LancamentoGerencialRequest();
        req.setCategoria(categoria);
        req.setValor(new BigDecimal(valor));
        req.setData(LocalDate.now());
        req.setTurnoId(turnoId);
        return req;
    }
}
