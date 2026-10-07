package com.motoshift.service;

import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.repository.TransacaoRepository;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * Os lançamentos CONCLUÍDOS de um tipo num período, cada um com o turno de
 * onde veio — e as duas contas que saem deles.
 *
 * <p>Nasceu dentro do {@code RelatorioService}. Veio para cá quando a DRE
 * ({@code DreService}) passou a precisar das mesmas horas trabalhadas: o
 * "lucro por hora" de uma tela e o "valor por hora" da outra têm de dividir
 * pelo mesmo número, e a única forma de garantir isso é a regra existir uma
 * vez só.
 */
@Component
public class LancamentosDoExtrato {

    private final TransacaoRepository transacaoRepo;

    public LancamentosDoExtrato(TransacaoRepository transacaoRepo) {
        this.transacaoRepo = transacaoRepo;
    }

    /** Um lançamento e o turno de onde ele veio — o turno pode faltar. */
    public record Lancamento(Transacao transacao, Turno turno) {}

    public List<Lancamento> doPeriodo(Long usuarioId, TipoTransacao tipo, Periodo p) {
        List<Lancamento> lista = new ArrayList<>();
        for (Object[] linha : transacaoRepo.lancamentosComTurno(
                usuarioId, tipo, p.inicio(), p.fim())) {
            lista.add(new Lancamento((Transacao) linha[0], (Turno) linha[1]));
        }
        return lista;
    }

    public static BigDecimal soma(List<Lancamento> lancamentos) {
        return lancamentos.stream()
                .map(l -> l.transacao().getValor())
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    /**
     * Horas efetivamente trabalhadas: a duração dos turnos que geraram
     * pagamento. Turno sem data (lançamento órfão) fica de fora da conta em
     * vez de entrar como zero hora, o que inflaria o valor por hora.
     */
    public static double horasTrabalhadas(List<Lancamento> lancamentos) {
        return lancamentos.stream()
                .filter(l -> l.turno() != null
                        && l.turno().getDataInicio() != null && l.turno().getDataFim() != null)
                .mapToDouble(l -> Duration.between(
                        l.turno().getDataInicio(), l.turno().getDataFim()).toMinutes() / 60.0)
                .sum();
    }

    /** Em quantos turnos diferentes houve lançamento — os órfãos não contam. */
    public static long turnosDistintos(List<Lancamento> lancamentos) {
        return lancamentos.stream()
                .map(l -> l.transacao().getTurnoId())
                .filter(Objects::nonNull)
                .distinct()
                .count();
    }
}
