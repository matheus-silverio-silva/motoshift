package com.motoshift.service;

import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.util.Artigo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Lembrete de turno aceito que começa em até 1 hora — para o entregador e
 * para a loja.
 *
 * <p>Mesmo padrão do {@link TurnoExpiracaoService}: job de 5 em 5 minutos,
 * desligável com {@code MOTOSHIFT_JOBS_HABILITADOS=false}. Não duplica: o
 * aviso sai por {@code criarUnica}, que não cria segunda notificação do mesmo
 * tipo para o mesmo turno e a mesma pessoa. Não precisou de coluna de
 * controle — a notificação já existente é o controle.
 *
 * <p>Quem é lembrado: cada entregador com inscrição ACEITA (ainda não
 * chegou, nem finalizou), e a loja uma vez. Turno sem ninguém inscrito não
 * tem o que lembrar — para esse o {@code turno_vencendo} já avisa a loja.
 */
@Service
@ConditionalOnProperty(name = "motoshift.jobs.habilitados", havingValue = "true", matchIfMissing = true)
public class TurnoLembreteService {

    private static final Logger log = LoggerFactory.getLogger(TurnoLembreteService.class);

    static final String TIPO = "turno_lembrete";
    static final Duration ANTECEDENCIA = Duration.ofHours(1);

    private static final DateTimeFormatter HORA = DateTimeFormatter.ofPattern("HH:mm");

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final UsuarioRepository usuarioRepo;
    private final NotificacaoService notificacoes;

    public TurnoLembreteService(TurnoRepository turnoRepo,
                                TurnoInscricaoRepository inscricaoRepo,
                                UsuarioRepository usuarioRepo,
                                NotificacaoService notificacoes) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.usuarioRepo = usuarioRepo;
        this.notificacoes = notificacoes;
    }

    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void lembrar() {
        lembrar(LocalDateTime.now());
    }

    /** O mesmo, com o relógio na mão — para o teste e para a massa. */
    @Transactional
    public int lembrar(LocalDateTime agora) {
        List<Turno> proximos = turnoRepo.findByStatusInAndDataInicioBetween(
                List.of(StatusTurno.ABERTO, StatusTurno.ACEITO, StatusTurno.EM_ANDAMENTO),
                agora, agora.plus(ANTECEDENCIA));
        if (proximos.isEmpty()) return 0;

        Map<Long, List<TurnoInscricao>> porTurno = new HashMap<>();
        for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdInAndStatus(
                proximos.stream().map(Turno::getId).toList(), StatusInscricao.ACEITO)) {
            if (ins.getCheckinEm() != null) continue; // já chegou: não precisa
            porTurno.computeIfAbsent(ins.getTurnoId(), k -> new ArrayList<>()).add(ins);
        }
        if (porTurno.isEmpty()) return 0;

        List<Long> ids = new ArrayList<>();
        proximos.forEach(t -> ids.add(t.getLojistId()));
        porTurno.values().forEach(l -> l.forEach(i -> ids.add(i.getMotoboyId())));
        Map<Long, Usuario> pessoas = usuarioRepo.findAllById(ids).stream()
                .collect(Collectors.toMap(Usuario::getId, Function.identity(), (a, b) -> a));

        int enviados = 0;
        for (Turno t : proximos) {
            List<TurnoInscricao> quem = porTurno.get(t.getId());
            if (quem == null) continue;

            String hora = t.getDataInicio().format(HORA);
            long minutos = Math.max(1, Duration.between(agora, t.getDataInicio()).toMinutes());
            String loja = nomeDaLoja(pessoas.get(t.getLojistId()));

            for (TurnoInscricao ins : quem) {
                if (notificacoes.criarUnica(ins.getMotoboyId(), TIPO,
                        "Seu turno começa em breve",
                        "\"" + t.getTitulo() + "\"" + naLoja(loja) + " começa às " + hora
                                + " — daqui a " + minutos + " min.",
                        "turno", t.getId()) != null) {
                    enviados++;
                }
            }

            String primeiro = primeiroNome(pessoas.get(quem.get(0).getMotoboyId()));
            String equipe = quem.size() == 1 ? primeiro
                    : primeiro + " e mais " + (quem.size() - 1);
            if (notificacoes.criarUnica(t.getLojistId(), TIPO,
                    "Turno começa em breve",
                    "\"" + t.getTitulo() + "\" começa às " + hora + ", com " + equipe + ".",
                    "turno", t.getId()) != null) {
                enviados++;
            }
        }
        if (enviados > 0) log.info("[lembrete] {} lembretes de turno enviados", enviados);
        return enviados;
    }

    /** " na Hamburgueria da Cláudia", " no Mercado Andrade". */
    private static String naLoja(String loja) {
        if (loja == null) return "";
        return ("a".equals(Artigo.definido(loja)) ? " na " : " no ") + loja;
    }

    private static String nomeDaLoja(Usuario u) {
        if (u == null) return null;
        return u.getNomeFantasia() != null && !u.getNomeFantasia().isBlank()
                ? u.getNomeFantasia() : u.getNome();
    }

    private static String primeiroNome(Usuario u) {
        if (u == null || u.getNome() == null || u.getNome().isBlank()) return "o entregador";
        return u.getNome().trim().split("\\s+")[0];
    }
}
