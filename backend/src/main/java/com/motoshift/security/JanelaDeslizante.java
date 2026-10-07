package com.motoshift.security;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Limite de requisições por janela deslizante, em memória.
 *
 * <p><b>Por que deslizante, e não um contador por hora cheia.</b> Com o
 * contador que zera na virada, quem gasta o limite às 13h59 gasta outro
 * inteiro às 14h00 — o dobro em dois minutos. Aqui cada chave guarda os
 * instantes das últimas requisições, e "10 por hora" quer dizer 10 em
 * QUALQUER intervalo de 60 minutos.
 *
 * <p><b>O custo.</b> Um instante (8 bytes) por requisição aceita, no máximo
 * {@code limite} por chave. Com limites de 10 e 20, é pouco.
 *
 * <p><b>O que "em memória" significa.</b> O estado é desta instância: some no
 * deploy e não é dividido entre réplicas — com duas, o limite efetivo dobra.
 * Para o que este filtro protege (o custo da IA e o abuso de cadastro) basta;
 * um limite exato entre réplicas pediria um armazenamento compartilhado.
 *
 * <p>Sem dependência de relógio: quem chama informa o instante. É o que
 * deixa o teste andar uma hora sem esperar uma hora.
 */
public class JanelaDeslizante {

    /**
     * Teto de chaves guardadas. Passado o teto (depois de jogar fora as
     * vencidas), o mapa é esvaziado: perde-se a contagem, não a memória do
     * servidor. Um limitador que derruba o processo protege menos do que um
     * que esquece.
     */
    static final int MAX_CHAVES = 50_000;

    /** A cada tantas requisições, joga fora as chaves que já venceram. */
    private static final int FAXINA_A_CADA = 1_000;

    private final int limite;
    private final long janelaMs;
    private final ConcurrentHashMap<String, Deque<Long>> acessos = new ConcurrentHashMap<>();
    private final AtomicLong contador = new AtomicLong();

    public JanelaDeslizante(int limite, Duration janela) {
        if (limite <= 0 || janela.isZero() || janela.isNegative()) {
            throw new IllegalArgumentException("Limite e janela precisam ser positivos.");
        }
        this.limite = limite;
        this.janelaMs = janela.toMillis();
    }

    /**
     * O que o limitador respondeu.
     *
     * @param permitido       a requisição cabe na janela (e foi contada)
     * @param esperarSegundos em quanto tempo a próxima cabe; 0 quando permitido
     */
    public record Decisao(boolean permitido, long esperarSegundos) {}

    /**
     * Conta a requisição de {@code chave} no instante {@code agoraMs}, se
     * couber. Requisição recusada não é contada: quem insiste durante o
     * bloqueio não empurra a própria liberação para a frente.
     */
    public Decisao registrar(String chave, long agoraMs) {
        if (contador.incrementAndGet() % FAXINA_A_CADA == 0 || acessos.size() > MAX_CHAVES) {
            faxina(agoraMs);
        }

        long[] espera = {0};
        // compute() é atômico por chave: duas requisições simultâneas da mesma
        // chave não leem a mesma fila "com uma vaga" e entram as duas.
        acessos.compute(chave, (k, fila) -> {
            Deque<Long> instantes = fila != null ? fila : new ArrayDeque<>(limite);
            descartarVencidos(instantes, agoraMs);
            if (instantes.size() < limite) {
                instantes.addLast(agoraMs);
            } else {
                // A vaga abre quando o mais antigo sair da janela.
                long faltaMs = instantes.peekFirst() + janelaMs - agoraMs;
                espera[0] = Math.max(1, (faltaMs + 999) / 1000);
            }
            return instantes;
        });
        return new Decisao(espera[0] == 0, espera[0]);
    }

    private void descartarVencidos(Deque<Long> instantes, long agoraMs) {
        long corte = agoraMs - janelaMs;
        while (!instantes.isEmpty() && instantes.peekFirst() <= corte) {
            instantes.pollFirst();
        }
    }

    /** Remove as chaves sem requisição dentro da janela. */
    void faxina(long agoraMs) {
        acessos.forEach((chave, fila) -> acessos.computeIfPresent(chave, (k, f) -> {
            descartarVencidos(f, agoraMs);
            return f.isEmpty() ? null : f;
        }));
        if (acessos.size() > MAX_CHAVES) acessos.clear();
    }

    /** Quantas chaves estão guardadas — para o teste da faxina. */
    int chavesGuardadas() {
        return acessos.size();
    }
}
