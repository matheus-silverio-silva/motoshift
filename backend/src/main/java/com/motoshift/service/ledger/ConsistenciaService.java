package com.motoshift.service.ledger;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Confere, lendo o banco inteiro, que a plataforma nao perdeu nem inventou
 * dinheiro.
 *
 * <p>Sao tres perguntas que um sistema financeiro tem de conseguir responder a
 * qualquer momento, e que ate aqui ninguem no projeto conseguia:
 *
 * <ol>
 *   <li><b>Nenhum saldo negativo.</b> Garantida na escrita pelo
 *       {@link LedgerService}; conferida aqui porque uma garantia que so existe
 *       no caminho feliz nao e garantia.</li>
 *   <li><b>Carteira = extrato.</b> Para cada usuario, o saldo disponivel e o
 *       bloqueado tem de ser exatamente a soma dos deltas dos lancamentos
 *       concluidos dele. Se divergir, a carteira e o extrato estao contando
 *       historias diferentes — e o extrato e quem tem razao, porque e o
 *       registro do que aconteceu.</li>
 *   <li><b>A plataforma nao cria dinheiro.</b> A soma de TODAS as carteiras tem
 *       de ser recargas concluidas menos saques concluidos mais estornos, menos
 *       o que foi retido na fonte (quando a retencao esta ligada). Toda
 *       transferencia interna — reserva, liberacao, pagamento de turno — e soma
 *       zero no conjunto: o que sai de um entra em outro. Se este numero
 *       desequilibrar, algum caminho esta creditando sem debitar, que era
 *       exatamente o defeito que este trabalho veio corrigir.</li>
 * </ol>
 *
 * <p><b>Por que so em perfil dev.</b> Isto varre carteiras e lancamentos
 * inteiros: e uma ferramenta de conferencia e de teste, nao um endpoint de
 * producao. O {@code ConsistenciaController} que a expoe e {@code @Profile("dev")}.
 * Os testes a chamam direto, sem HTTP.
 *
 * <p><b>Lancamentos nao concluidos ficam de fora.</b> Sobraram no banco
 * lancamentos {@code pendente} de antes da liquidacao automatica — divida
 * reconhecida que a dupla confirmacao nunca chegou a quitar. Eles nao entram em
 * nenhuma soma porque nao mexeram em saldo nenhum; ignora-los e o que mantem a
 * invariante (b) verdadeira sem reescrever o passado.
 */
@Service
public class ConsistenciaService {

    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;

    public ConsistenciaService(CarteiraRepository carteiraRepo, TransacaoRepository transacaoRepo) {
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
    }

    /** O resultado da conferencia: passou, ou passou a lista do que nao fecha. */
    public record Resultado(boolean consistente, List<String> problemas,
                            Map<String, Object> totais) {

        /** Para usar em teste: falha com a lista inteira, nao com "esperava true". */
        public void exigirConsistente() {
            if (!consistente) {
                throw new IllegalStateException(
                        "Ledger inconsistente:\n  - " + String.join("\n  - ", problemas));
            }
        }
    }

    @Transactional(readOnly = true)
    public Resultado verificarConsistencia() {
        List<String> problemas = new ArrayList<>();

        List<Carteira> carteiras = carteiraRepo.findAll();
        List<Transacao> lancamentos = transacaoRepo.findAll().stream()
                .filter(t -> t.getStatus() == StatusTransacao.CONCLUIDO)
                .toList();

        // (a) nenhum saldo negativo
        for (Carteira c : carteiras) {
            if (c.getSaldoDisponivel().signum() < 0) {
                problemas.add("(a) usuario " + c.getUsuarioId()
                        + " com disponivel negativo: " + c.getSaldoDisponivel());
            }
            if (c.getSaldoBloqueado().signum() < 0) {
                problemas.add("(a) usuario " + c.getUsuarioId()
                        + " com bloqueado negativo: " + c.getSaldoBloqueado());
            }
        }

        // (b) carteira = soma dos deltas do extrato daquele usuario
        Map<Long, BigDecimal[]> esperado = new HashMap<>();
        for (Transacao t : lancamentos) {
            BigDecimal[] acc = esperado.computeIfAbsent(t.getUsuarioId(),
                    k -> new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
            acc[0] = acc[0].add(deltaDisponivel(t));
            acc[1] = acc[1].add(deltaBloqueado(t));
        }

        for (Carteira c : carteiras) {
            BigDecimal[] acc = esperado.getOrDefault(c.getUsuarioId(),
                    new BigDecimal[] {BigDecimal.ZERO, BigDecimal.ZERO});
            if (c.getSaldoDisponivel().compareTo(acc[0]) != 0) {
                problemas.add("(b) usuario " + c.getUsuarioId() + " com disponivel "
                        + c.getSaldoDisponivel() + " e extrato somando " + acc[0]);
            }
            if (c.getSaldoBloqueado().compareTo(acc[1]) != 0) {
                problemas.add("(b) usuario " + c.getUsuarioId() + " com bloqueado "
                        + c.getSaldoBloqueado() + " e extrato somando " + acc[1]);
            }
        }

        // Usuario com lancamento e sem carteira e o mesmo defeito visto do outro lado.
        for (Map.Entry<Long, BigDecimal[]> e : esperado.entrySet()) {
            boolean temCarteira = carteiras.stream()
                    .anyMatch(c -> c.getUsuarioId().equals(e.getKey()));
            if (!temCarteira && (e.getValue()[0].signum() != 0 || e.getValue()[1].signum() != 0)) {
                problemas.add("(b) usuario " + e.getKey()
                        + " tem lancamentos somando " + e.getValue()[0] + " e nenhuma carteira");
            }
        }

        // (c) a plataforma nao cria nem destroi dinheiro
        BigDecimal totalCarteiras = carteiras.stream()
                .map(Carteira::getSaldoTotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal recargas = somaDoTipo(lancamentos, TipoTransacao.RECARGA);
        BigDecimal saques = somaDoTipo(lancamentos, TipoTransacao.SAQUE);
        BigDecimal estornos = somaDoTipo(lancamentos, TipoTransacao.ESTORNO);
        BigDecimal bonus = somaDoTipo(lancamentos, TipoTransacao.BONUS);
        // Retencao na fonte e dinheiro que sai para o fisco (simulado), como o
        // saque sai para a chave Pix: diminui o total, e so por esse caminho.
        BigDecimal retencoes = somaDoTipo(lancamentos, TipoTransacao.RETENCAO_ISS)
                .add(somaDoTipo(lancamentos, TipoTransacao.RETENCAO_IRRF));
        BigDecimal esperadoTotal = recargas.subtract(saques).add(estornos).add(bonus)
                .subtract(retencoes);

        if (totalCarteiras.compareTo(esperadoTotal) != 0) {
            problemas.add("(c) carteiras somam " + totalCarteiras
                    + " e recargas - saques + estornos - retencoes dao " + esperadoTotal
                    + " (diferenca de " + totalCarteiras.subtract(esperadoTotal) + ")");
        }

        Map<String, Object> totais = new LinkedHashMap<>();
        totais.put("carteiras", carteiras.size());
        totais.put("lancamentosConcluidos", lancamentos.size());
        totais.put("somaDasCarteiras", totalCarteiras);
        totais.put("recargas", recargas);
        totais.put("saques", saques);
        totais.put("estornos", estornos);
        totais.put("retencoes", retencoes);

        return new Resultado(problemas.isEmpty(), problemas, totais);
    }

    private static BigDecimal somaDoTipo(List<Transacao> lancamentos, TipoTransacao tipo) {
        return lancamentos.stream()
                .filter(t -> t.getTipo() == tipo)
                .map(Transacao::getValor)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    /**
     * O delta que aquele tipo aplicou ao disponivel.
     *
     * <p>Repete de proposito a tabela de {@link Movimento}, e por um motivo: se
     * a conferencia reusasse as fabricas que escreveram os lancamentos, ela
     * confirmaria que o codigo concorda consigo mesmo. Escrita de novo, a partir
     * da definicao de cada tipo, ela realmente confere — um erro na tabela de
     * la aparece aqui como divergencia em vez de passar despercebido.
     */
    private static BigDecimal deltaDisponivel(Transacao t) {
        BigDecimal v = t.getValor();
        return switch (t.getTipo()) {
            case RECARGA, PAGAMENTO_RECEBIDO, ESTORNO, BONUS, LIBERACAO_RESERVA -> v;
            case SAQUE, RESERVA, RETENCAO_ISS, RETENCAO_IRRF -> v.negate();
            case PAGAMENTO_ENVIADO -> BigDecimal.ZERO;
        };
    }

    private static BigDecimal deltaBloqueado(Transacao t) {
        BigDecimal v = t.getValor();
        return switch (t.getTipo()) {
            case RESERVA -> v;
            case LIBERACAO_RESERVA, PAGAMENTO_ENVIADO -> v.negate();
            case RECARGA, PAGAMENTO_RECEBIDO, ESTORNO, BONUS, SAQUE,
                 RETENCAO_ISS, RETENCAO_IRRF -> BigDecimal.ZERO;
        };
    }
}
