package com.motoshift.support;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.TurnoService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestComponent;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Monta, pelo caminho real, o dinheiro de um turno: conta, recarga, publicação
 * com reserva, inscrição e finalização com liquidação.
 *
 * <p>Os testes fiscais precisam de pagamentos de verdade no extrato — a NFS-e
 * documenta um {@code pagamento_recebido}, e um turno gravado direto como
 * FINALIZADO não tem pagamento nenhum. Forjar o lançamento no ledger seria
 * mais curto e testaria outra coisa: a nota tem de concordar com o que a
 * liquidação de fato gravou, inclusive a retenção.
 *
 * <p>Uso: {@code @Import(CenarioFinanceiro.class)} e {@code @Autowired}.
 */
@TestComponent
public class CenarioFinanceiro {

    /** Espaça os turnos no tempo, para dois deles nunca colidirem de horário. */
    private static final AtomicInteger SEQUENCIA = new AtomicInteger();

    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private CobrancaService cobrancas;
    @Autowired private TurnoService turnos;
    @Autowired private TurnoRepository turnoRepo;
    @Autowired private TurnoInscricaoRepository inscricaoRepo;
    @Autowired private TransacaoRepository transacaoRepo;

    public Usuario conta(String tipo, String nome, String documento) {
        Usuario u = new Usuario();
        u.setNome(nome);
        // Fora do sufixo da massa de demonstração, que o reset apagaria.
        u.setEmail(tipo + "-" + System.nanoTime() + "@fiscal.test");
        u.setSenha("x");
        u.setTelefone("41999990000");
        u.setTipo(tipo);
        u.setDocumentoFederal(documento);
        u.setCidade("Curitiba");
        u.setEstado("PR");
        return usuarioRepo.save(u);
    }

    /** Recarga pelo caminho real — cobrança criada e confirmada. */
    public void recarregar(Long usuarioId, String valor) {
        Long cobranca = cobrancas.criarRecarga(usuarioId, new BigDecimal(valor), null).getId();
        cobrancas.confirmarRecarga(usuarioId, cobranca);
    }

    /** Publica (e portanto reserva) um turno. O lojista precisa ter saldo. */
    public Turno publicar(Long lojistaId, String valorPorEntregador, int vagas) {
        int n = SEQUENCIA.incrementAndGet();
        LocalDateTime inicio = LocalDateTime.now().plusHours(3).plusDays(n);
        TurnoRequest req = new TurnoRequest();
        req.setTitulo("Turno fiscal " + n);
        req.setRegiao("Batel, Curitiba");
        req.setDataInicio(inicio);
        req.setDataFim(inicio.plusHours(4));
        req.setValorEstimado(new BigDecimal(valorPorEntregador));
        req.setVagas(vagas);
        return turnoRepo.findById(turnos.criar(req, lojistaId).getId()).orElseThrow();
    }

    /**
     * Inscrição direta no repositório, como o ReservaELiquidacaoTest faz: o
     * que está em teste aqui é o dinheiro e o documento, não as regras de
     * aceite (conflito de horário, capacidade), que têm testes próprios.
     */
    public void inscrever(Turno t, Long motoboyId) {
        TurnoInscricao ins = new TurnoInscricao();
        ins.setTurnoId(t.getId());
        ins.setMotoboyId(motoboyId);
        ins.setStatus(StatusInscricao.ACEITO);
        inscricaoRepo.save(ins);
        Turno atual = turnoRepo.findById(t.getId()).orElseThrow();
        if (atual.getMotoboyId() == null) {
            atual.setMotoboyId(motoboyId);
            turnoRepo.save(atual);
        }
    }

    public Turno finalizar(Turno t, Long quem) {
        turnos.finalizar(t.getId(), quem);
        return turnoRepo.findById(t.getId()).orElseThrow();
    }

    /**
     * Turno publicado, preenchido e finalizado pelo lojista: cada entregador
     * recebe {@code valor}. Recarrega o suficiente antes.
     */
    public Turno turnoPago(Long lojistaId, String valor, Long... entregadores) {
        BigDecimal custo = new BigDecimal(valor).multiply(BigDecimal.valueOf(entregadores.length));
        recarregar(lojistaId, custo.toPlainString());
        Turno t = publicar(lojistaId, valor, entregadores.length);
        for (Long e : entregadores) inscrever(t, e);
        return finalizar(t, lojistaId);
    }

    public Transacao pagamentoRecebido(Turno t, Long entregadorId) {
        return doTurno(t, entregadorId, TipoTransacao.PAGAMENTO_RECEBIDO);
    }

    public Transacao pagamentoEnviado(Turno t, Long lojistaId, Long entregadorId) {
        return transacaoRepo.findByTurnoId(t.getId()).stream()
                .filter(x -> x.getTipo() == TipoTransacao.PAGAMENTO_ENVIADO)
                .filter(x -> x.getUsuarioId().equals(lojistaId))
                .filter(x -> entregadorId.equals(x.getContraparteId()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("sem pagamento_enviado para " + entregadorId));
    }

    public Transacao doTurno(Turno t, Long usuarioId, TipoTransacao tipo) {
        return transacaoRepo.findByTurnoId(t.getId()).stream()
                .filter(x -> x.getTipo() == tipo && x.getUsuarioId().equals(usuarioId))
                .filter(x -> x.getStatus() == StatusTransacao.CONCLUIDO)
                .findFirst()
                .orElseThrow(() -> new AssertionError("sem " + tipo.getValor() + " de " + usuarioId));
    }
}
