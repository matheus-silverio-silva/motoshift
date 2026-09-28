package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Selos de reputação — calculados na hora, a partir do que já está no banco.
 * Sem tabela: um selo é uma pergunta sobre o histórico, e guardar a resposta
 * seria guardar um dado que envelhece.
 *
 * <p><b>Entregador</b>: 25 turnos concluídos; 30 dias sem cancelar; nota
 * acima de 4,8 (com 10 avaliações ou mais); pontual (90% ou mais, com 10
 * check-ins ou mais). <b>Loja</b>: paga gorjeta; nota acima de 4,8; contrata
 * toda semana.
 *
 * <p>Cada selo leva o critério por extenso: a tela o mostra ao toque, e a
 * banca pode conferir a regra sem abrir o código.
 */
@Component
public class Selos {

    /** Um selo e a regra que o dá. */
    public record Selo(String codigo, String titulo, String criterio) {}

    static final int TURNOS_CONCLUIDOS = 25;
    static final int DIAS_SEM_CANCELAR = 30;
    static final double NOTA_MINIMA = 4.8;
    static final int AVALIACOES_MINIMAS = 10;
    static final int PONTUALIDADE_MINIMA = 90;
    static final int CHECKINS_MINIMOS = 10;
    static final int GORJETAS_MINIMAS = 3;
    static final int JANELA_GORJETAS_DIAS = 90;
    static final int SEMANAS_SEGUIDAS = 4;

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final AvaliacaoRepository avaliacaoRepo;
    private final TransacaoRepository transacaoRepo;
    private final Reputacao reputacao;

    public Selos(TurnoRepository turnoRepo,
                 TurnoInscricaoRepository inscricaoRepo,
                 AvaliacaoRepository avaliacaoRepo,
                 TransacaoRepository transacaoRepo,
                 Reputacao reputacao) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.avaliacaoRepo = avaliacaoRepo;
        this.transacaoRepo = transacaoRepo;
        this.reputacao = reputacao;
    }

    @Transactional(readOnly = true)
    public List<Selo> de(Usuario u) {
        return de(u, LocalDateTime.now());
    }

    @Transactional(readOnly = true)
    public List<Selo> de(Usuario u, LocalDateTime agora) {
        if (u == null || u.getId() == null) return List.of();
        return "lojista".equals(u.getTipo()) ? daLoja(u, agora) : doEntregador(u, agora);
    }

    private List<Selo> doEntregador(Usuario u, LocalDateTime agora) {
        Long id = u.getId();
        List<Selo> selos = new ArrayList<>();

        long concluidos = inscricaoRepo.countByMotoboyIdAndStatus(id, StatusInscricao.FINALIZADO);
        if (concluidos >= TURNOS_CONCLUIDOS) {
            selos.add(new Selo("turnos_concluidos", TURNOS_CONCLUIDOS + " turnos concluídos",
                    "Concluiu " + TURNOS_CONCLUIDOS + " turnos ou mais na plataforma."));
        }

        // Precisa de histórico mais velho que a janela: quem começou ontem
        // também está "sem cancelar", e o selo não diria nada.
        LocalDateTime inicioDaJanela = agora.minusDays(DIAS_SEM_CANCELAR);
        LocalDateTime primeiro = inscricaoRepo.primeiroTurnoConcluido(id);
        if (primeiro != null && !primeiro.isAfter(inicioDaJanela)
                && !turnoRepo.existsByCanceladoPorIdAndCanceladoEmAfter(id, inicioDaJanela)) {
            selos.add(new Selo("sem_cancelar", DIAS_SEM_CANCELAR + " dias sem cancelar",
                    "Nenhum turno cancelado por ele nos últimos " + DIAS_SEM_CANCELAR
                            + " dias, com turnos concluídos há mais tempo que isso."));
        }

        nota(u).ifPresent(selos::add);

        Reputacao.Pontualidade p = reputacao.pontualidade(id);
        if (p.percentual() != null && p.checkins() >= CHECKINS_MINIMOS
                && p.percentual() >= PONTUALIDADE_MINIMA) {
            selos.add(new Selo("pontual", "Pontual",
                    "Chegou até 10 min depois do início em " + PONTUALIDADE_MINIMA
                            + "% ou mais dos check-ins dos últimos 90 dias (mínimo de "
                            + CHECKINS_MINIMOS + ")."));
        }
        return selos;
    }

    private List<Selo> daLoja(Usuario u, LocalDateTime agora) {
        Long id = u.getId();
        List<Selo> selos = new ArrayList<>();

        long gorjetas = transacaoRepo.contarGorjetasDadasDesde(id, TipoTransacao.BONUS_ENVIADO,
                StatusTransacao.CONCLUIDO, agora.minusDays(JANELA_GORJETAS_DIAS));
        if (gorjetas >= GORJETAS_MINIMAS) {
            selos.add(new Selo("paga_gorjeta", "Paga gorjeta",
                    "Deu gorjeta em " + GORJETAS_MINIMAS + " turnos ou mais nos últimos "
                            + JANELA_GORJETAS_DIAS + " dias."));
        }

        nota(u).ifPresent(selos::add);

        // Uma semana é uma janela de 7 dias contada para trás a partir de
        // agora: as últimas 4 precisam ter, cada uma, um turno concluído.
        List<LocalDateTime> datas = turnoRepo.iniciosDosTurnosDaLojaDesde(id, StatusTurno.FINALIZADO,
                agora.minusDays(7L * SEMANAS_SEGUIDAS));
        boolean todaSemana = true;
        for (int k = 0; k < SEMANAS_SEGUIDAS && todaSemana; k++) {
            LocalDateTime fim = agora.minusDays(7L * k);
            LocalDateTime inicio = fim.minusDays(7);
            todaSemana = datas.stream().anyMatch(d -> !d.isBefore(inicio) && d.isBefore(fim));
        }
        if (todaSemana) {
            selos.add(new Selo("toda_semana", "Contrata toda semana",
                    "Teve turno concluído em cada uma das últimas " + SEMANAS_SEGUIDAS + " semanas."));
        }
        return selos;
    }

    private java.util.Optional<Selo> nota(Usuario u) {
        Double media = u.getMediaAvaliacao();
        if (media == null || media <= NOTA_MINIMA) return java.util.Optional.empty();
        if (avaliacaoRepo.countByAvaliadoId(u.getId()) < AVALIACOES_MINIMAS) return java.util.Optional.empty();
        return java.util.Optional.of(new Selo("nota_alta", "Nota acima de 4,8",
                "Média acima de 4,8 em " + AVALIACOES_MINIMAS + " avaliações ou mais."));
    }
}
