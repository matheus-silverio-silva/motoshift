package com.motoshift.config;

import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Notificacao;
import com.motoshift.entity.StatusInscricao;
import com.motoshift.entity.StatusPagamento;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.service.NotificacaoService;
import com.motoshift.service.PagamentoTurnoService;
import jakarta.persistence.EntityManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Massa de demonstração: 8 contas, turnos em todos os estados, extrato,
 * avaliações, notas fiscais e notificações.
 *
 * <p><b>Por que saiu do DataInitializer.</b> O seed era {@code @Profile("!prod")}
 * e só rodava com o banco vazio. Em produção nunca rodava, e o banco do Railway
 * — o que aparece numa demonstração ao vivo — envelhecia: turnos "abertos"
 * com início no passado, extrato parado, notificação de semanas atrás. Em dev
 * não havia como regerar sem derrubar tudo. Aqui o mesmo código serve aos dois
 * ambientes: {@link #popular()} cria, {@link #resetar()} limpa só a massa e
 * cria de novo.
 *
 * <p><b>Escopo.</b> A massa é identificada por uma coisa só: e-mail terminado
 * em {@link #SUFIXO_EMAIL}. Contas reais e o que é delas ficam intactos. O que
 * uma conta real fez COM a massa — aceitar um turno de lojista de demonstração,
 * avaliar um entregador de demonstração — é interação com a demonstração e sai
 * junto; sem isso as chaves estrangeiras da V11 impediriam apagar as contas.
 *
 * <p><b>Datas.</b> Tudo é derivado de "agora" no momento da execução — inclusive
 * nascimento e validade de CNH. Nada de data fixa: data fixa é o que fazia a
 * massa envelhecer.
 *
 * <p><b>Regras de negócio.</b> Nenhuma foi relaxada para caber a massa. Os
 * cenários que as regras não permitem criar pela API (turno que já começou,
 * turno finalizado no passado, cancelamento de véspera) são gravados direto
 * pelos repositórios. A nota fiscal é a exceção de propósito: passa pelo
 * {@link NotaFiscalService}, para a massa usar a mesma conta de tributos do app.
 */
@Component
public class MassaDemonstracao {

    /** O que marca uma conta como massa de demonstração. Único lugar com esta string. */
    public static final String SUFIXO_EMAIL = "@teste.com";

    /** Senha de todas as contas da massa (sempre gravada com hash). */
    public static final String SENHA = "senha123";

    private static final Logger log = LoggerFactory.getLogger(MassaDemonstracao.class);

    /** Id que nunca existe: evita IN () vazio nas consultas de limpeza. */
    private static final List<Long> NENHUM = List.of(-1L);

    private final EntityManager em;
    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;
    private final AvaliacaoRepository avaliacaoRepo;
    private final NotificacaoService notificacoes;
    private final NotaFiscalService notasFiscais;
    private final PasswordEncoder encoder;

    public MassaDemonstracao(EntityManager em,
                             UsuarioRepository usuarioRepo,
                             TurnoRepository turnoRepo,
                             TurnoInscricaoRepository inscricaoRepo,
                             CarteiraRepository carteiraRepo,
                             TransacaoRepository transacaoRepo,
                             AvaliacaoRepository avaliacaoRepo,
                             NotificacaoService notificacoes,
                             NotaFiscalService notasFiscais,
                             PasswordEncoder encoder) {
        this.em = em;
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
        this.avaliacaoRepo = avaliacaoRepo;
        this.notificacoes = notificacoes;
        this.notasFiscais = notasFiscais;
        this.encoder = encoder;
    }

    // ══ Reset ═════════════════════════════════════════════════════════════

    /**
     * Apaga a massa anterior e cria outra, com datas de agora.
     *
     * Uma transação só: se qualquer passo falhar — inclusive a emissão de uma
     * nota fiscal —, nada é apagado e o banco fica exatamente como estava.
     */
    @Transactional
    public void resetar() {
        Map<String, Long> apagados = apagar();
        popular();
        Map<String, Long> criados = contarEscopo();

        StringBuilder resumo = new StringBuilder("[massa] reset concluido")
                .append(String.format("%n  %-17s %9s %8s", "tabela", "apagados", "criados"));
        for (String tabela : apagados.keySet()) {
            resumo.append(String.format("%n  %-17s %9d %8d",
                    tabela, apagados.get(tabela), criados.get(tabela)));
        }
        log.info(resumo.toString());
    }

    /**
     * Linhas no escopo da massa, por tabela. É a mesma conta usada para
     * apagar — serve ao resumo do log e aos testes.
     */
    @Transactional(readOnly = true)
    public Map<String, Long> contarEscopo() {
        Escopo e = escopoAtual();
        Map<String, Long> n = new LinkedHashMap<>();
        n.put("notas_fiscais",    contar("select count(n) from NotaFiscal n where n.id in :notas", e));
        n.put("avaliacoes",       contar("select count(a) from Avaliacao a" + ONDE_AVALIACAO, e));
        n.put("transacoes",       contar("select count(t) from Transacao t" + ONDE_TRANSACAO, e));
        n.put("turno_inscricoes", contar("select count(i) from TurnoInscricao i" + ONDE_INSCRICAO, e));
        n.put("notificacoes",     contar("select count(n) from Notificacao n" + ONDE_NOTIFICACAO, e));
        n.put("turnos",           contar("select count(t) from Turno t where t.id in :turnos", e));
        n.put("carteiras",        contar("select count(c) from Carteira c" + ONDE_CARTEIRA, e));
        n.put("usuarios",         contar("select count(u) from Usuario u where u.id in :demo", e));
        return n;
    }

    // As condições de escopo, escritas uma vez para contar e para apagar.
    private static final String ONDE_AVALIACAO =
            " where a.turnoId in :turnos or a.avaliadorId in :demo or a.avaliadoId in :demo";
    private static final String ONDE_TRANSACAO =
            " where t.usuarioId in :demo or t.contraparteId in :demo or t.turnoId in :turnos"
          + " or t.motoboyId in :demo";
    private static final String ONDE_INSCRICAO =
            " where i.turnoId in :turnos or i.motoboyId in :demo";
    private static final String ONDE_NOTIFICACAO =
            " where n.usuarioId in :demo"
          + " or (n.referenciaTipo = 'turno' and n.referenciaId in :turnos)"
          + " or (n.referenciaTipo = 'nota_fiscal' and n.referenciaId in :notas)";
    private static final String ONDE_CARTEIRA =
            " where c.usuarioId in :demo or c.motoboyId in :demo";

    /**
     * Apaga, na ordem das chaves estrangeiras (de quem referencia para quem é
     * referenciado), tudo o que está no escopo da massa. DELETE com WHERE
     * sempre — nunca TRUNCATE nem DROP.
     */
    private Map<String, Long> apagar() {
        Escopo e = escopoAtual();
        Map<String, Long> n = new LinkedHashMap<>();
        n.put("notas_fiscais",    executar("delete from NotaFiscal n where n.id in :notas", e));
        n.put("avaliacoes",       executar("delete from Avaliacao a" + ONDE_AVALIACAO, e));
        n.put("transacoes",       executar("delete from Transacao t" + ONDE_TRANSACAO, e));
        n.put("turno_inscricoes", executar("delete from TurnoInscricao i" + ONDE_INSCRICAO, e));
        n.put("notificacoes",     executar("delete from Notificacao n" + ONDE_NOTIFICACAO, e));
        n.put("turnos",           executar("delete from Turno t where t.id in :turnos", e));
        n.put("carteiras",        executar("delete from Carteira c" + ONDE_CARTEIRA, e));
        n.put("usuarios",         executar("delete from Usuario u where u.id in :demo", e));
        return n;
    }

    /** Contas, turnos e notas da massa, na forma que as consultas usam. */
    private record Escopo(List<Long> demo, List<Long> turnos, List<Long> notas) {}

    private Escopo escopoAtual() {
        List<Long> demo = em.createQuery(
                        "select u.id from Usuario u where lower(u.email) like :sufixo", Long.class)
                .setParameter("sufixo", "%" + SUFIXO_EMAIL)
                .getResultList();

        // Turno da massa: publicado por conta da massa ou com ela de entregador
        // principal. Turno de conta real em que a massa só ocupou vaga extra
        // continua existindo — sai apenas a inscrição da conta da massa.
        List<Long> turnos = em.createQuery(
                        "select t.id from Turno t where t.lojistId in :demo or t.motoboyId in :demo",
                        Long.class)
                .setParameter("demo", ouNenhum(demo))
                .getResultList();

        List<Long> notas = em.createQuery(
                        "select n.id from NotaFiscal n where n.turnoId in :turnos"
                      + " or n.prestadorId in :demo or n.tomadorId in :demo or n.emitidaPorId in :demo",
                        Long.class)
                .setParameter("turnos", ouNenhum(turnos))
                .setParameter("demo", ouNenhum(demo))
                .getResultList();

        return new Escopo(ouNenhum(demo), ouNenhum(turnos), ouNenhum(notas));
    }

    private long executar(String jpql, Escopo e) {
        return parametros(em.createQuery(jpql), jpql, e).executeUpdate();
    }

    private long contar(String jpql, Escopo e) {
        return (Long) parametros(em.createQuery(jpql), jpql, e).getSingleResult();
    }

    private static jakarta.persistence.Query parametros(jakarta.persistence.Query q, String jpql, Escopo e) {
        if (jpql.contains(":demo"))   q.setParameter("demo", e.demo());
        if (jpql.contains(":turnos")) q.setParameter("turnos", e.turnos());
        if (jpql.contains(":notas"))  q.setParameter("notas", e.notas());
        return q;
    }

    private static List<Long> ouNenhum(List<Long> ids) {
        return ids.isEmpty() ? NENHUM : ids;
    }

    // ══ Criação ═══════════════════════════════════════════════════════════

    /**
     * Cria a massa inteira. Não é transacional por si: no boot de dev cada
     * gravação vale sozinha, e uma nota fiscal que falhe não impede o app de
     * subir. Chamado por {@link #resetar()}, roda dentro da transação dele.
     */
    public void popular() {
        LocalDateTime agora = LocalDateTime.now();
        LocalDate hoje = agora.toLocalDate();
        Saldos saldos = new Saldos();

        // ── Lojistas ─────────────────────────────────────────────────────────

        Usuario claudia = lojista("Cláudia Oliveira", "claudia@teste.com", "(41) 99111-2222",
                "12.345.678/0001-90", hoje.minusYears(41).minusDays(80), "Curitiba", "PR",
                "Hamburgueria da Cláudia", "Av. Água Verde, 1200 — Água Verde, Curitiba/PR", 4.8);
        Usuario fernando = lojista("Fernando Costa", "fernando@teste.com", "(41) 99333-4444",
                "98.765.432/0001-10", hoje.minusYears(48).minusDays(210), "Curitiba", "PR",
                "Pizzaria do Fernando", "R. Comendador Araújo, 450 — Batel, Curitiba/PR", 4.5);
        Usuario ana = lojista("Ana Souza", "ana@teste.com", "(41) 99555-6666",
                "11.222.333/0001-44", hoje.minusYears(35).minusDays(150), "Curitiba", "PR",
                "Farmácia Ana", "R. XV de Novembro, 980 — Centro Cívico, Curitiba/PR", 4.9);
        Usuario maria = lojista("Maria Andrade", "lojista@teste.com", "(11) 91234-5678",
                "12.345.678/0001-99", hoje.minusYears(44).minusDays(30), "São Paulo", "SP",
                "Mercado Andrade", "Av. Paulista, 1500 — Bela Vista, São Paulo/SP", null);

        // ── Entregadores ─────────────────────────────────────────────────────
        // Score na escala 0-5: Thiago está baixo porque tem cancelamento de
        // véspera (ver o turno cancelado dele, mais abaixo).

        Usuario ricardo = motoboy("Ricardo Souza", "ricardo@teste.com", "(41) 98111-2222",
                "12345678900", "A", hoje.plusYears(2).plusMonths(9), hoje.minusYears(31).minusDays(40),
                "Curitiba", "PR", "Honda CG 160 Titan", "ABC-1D23", hoje.getYear() - 4, "Vermelha", 4.7, 4.8);
        Usuario lucas = motoboy("Lucas Mendes", "lucas@teste.com", "(41) 98333-4444",
                "98765432100", "AB", hoje.plusYears(1).plusMonths(2), hoje.minusYears(33).minusDays(250),
                "Curitiba", "PR", "Yamaha Factor 150", "DEF-2E34", hoje.getYear() - 3, "Preta", 4.9, 4.6);
        Usuario thiago = motoboy("Thiago Alves", "thiago@teste.com", "(41) 98555-6666",
                "55566677788", "A", hoje.plusMonths(7), hoje.minusYears(27).minusDays(290),
                "Curitiba", "PR", "Honda Biz 125", "GHI-3F45", hoje.getYear() - 6, "Branca", 3.1, 3.2);
        Usuario carlos = motoboy("Carlos Mendes", "motoboy@teste.com", "(11) 99876-5432",
                "11122233344", "A", hoje.plusYears(3), hoje.minusYears(34).minusDays(33),
                "São Paulo", "SP", "Honda PCX 150", "JKL-4G56", hoje.getYear() - 2, "Azul", 5.0, null);

        // ── Turnos ABERTOS ───────────────────────────────────────────────────
        // Início sempre no futuro; o job de vencimento só age em aberto que já
        // começou.

        LocalDateTime em3h = redondo(agora.plusHours(3));
        LocalDateTime em5h = redondo(agora.plusHours(5));
        LocalDateTime amanha = agora.plusDays(1).truncatedTo(ChronoUnit.DAYS);
        LocalDateTime depoisDeAmanha = agora.plusDays(2).truncatedTo(ChronoUnit.DAYS);

        turno(claudia, null, "Turno Tarde — Hamburgueria da Cláudia", "Entregas na região do Água Verde",
                "Água Verde, Curitiba", em3h, em3h.plusHours(4), "120.00", 8.0, StatusTurno.ABERTO);
        turno(fernando, null, "Turno Tarde — Pizzaria do Fernando", "Entregas zona Batel e adjacências",
                "Batel, Curitiba", em5h, em5h.plusHours(4), "100.00", 5.0, StatusTurno.ABERTO);
        turno(ana, null, "Turno Manhã — Farmácia Ana", "Entregas de medicamentos",
                "Centro Cívico, Curitiba", amanha.with(LocalTime.of(8, 0)), amanha.with(LocalTime.of(12, 0)),
                "110.00", 6.0, StatusTurno.ABERTO);
        turno(claudia, null, "Turno Noite — Hamburgueria da Cláudia", "Entregas noturnas",
                "Água Verde, Curitiba", amanha.with(LocalTime.of(18, 0)), amanha.with(LocalTime.of(22, 0)),
                "130.00", 10.0, StatusTurno.ABERTO);
        turno(fernando, null, "Turno Manhã — Pizzaria do Fernando", "Preparação e entregas",
                "Batel, Curitiba", depoisDeAmanha.with(LocalTime.of(10, 0)),
                depoisDeAmanha.with(LocalTime.of(14, 0)), "105.00", 7.0, StatusTurno.ABERTO);

        // ── Turnos ACEITOS ───────────────────────────────────────────────────
        // O "em andamento" começou há pouco. A API não deixaria publicá-lo (RF04
        // exige 2h de antecedência), por isso vem direto do repositório.

        LocalDateTime comecouHaPouco = redondo(agora.minusHours(1));
        Turno emAndamento = turno(claudia, ricardo, "Turno Ativo — Hamburgueria da Cláudia",
                "Entregas em andamento", "Água Verde, Curitiba",
                comecouHaPouco, comecouHaPouco.plusHours(4), "120.00", 8.0, StatusTurno.ACEITO);
        turno(ana, lucas, "Turno Confirmado — Farmácia Ana", "Entregas de medicamentos tarde",
                "Centro Cívico, Curitiba", amanha.with(LocalTime.of(14, 0)), amanha.with(LocalTime.of(18, 0)),
                "110.00", 6.0, StatusTurno.ACEITO);

        // ── Finalizados e PAGOS ──────────────────────────────────────────────
        //   duas avaliações  → "Concluídos" dos dois lados
        //   uma avaliação    → quem não avaliou vê em "A avaliar"
        //   nenhuma          → os dois veem em "A avaliar"

        Turno t8 = pago(claudia, ricardo, "Turno Concluído — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(7), "120.00", 8.0, saldos);
        Turno t9 = pago(fernando, ricardo, "Turno Concluído — Pizzaria do Fernando",
                "Batel, Curitiba", agora.minusDays(15), "100.00", 5.0, saldos);
        Turno t10 = pago(ana, lucas, "Turno Concluído — Farmácia Ana",
                "Centro Cívico, Curitiba", agora.minusDays(3), "110.00", 6.0, saldos);
        Turno t11 = pago(claudia, thiago, "Turno Concluído — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(20), "120.00", 8.0, saldos);
        Turno t12 = pago(fernando, lucas, "Turno Concluído — Pizzaria do Fernando",
                "Batel, Curitiba", agora.minusDays(10), "100.00", 5.0, saldos);
        Turno t13 = pago(ana, ricardo, "Turno Manhã — Farmácia Ana",
                "Centro Cívico, Curitiba", agora.minusDays(2), "95.00", 5.0, saldos);
        Turno t14 = pago(claudia, lucas, "Turno Noite — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(1), "130.00", 8.0, saldos);

        // ── Finalizados com pagamento PENDENTE ───────────────────────────────
        // As combinações de quem já confirmou. Os dois confirmados não existe
        // aqui: seria PAGO, e a liquidação já teria acontecido.

        Turno t15 = pendente(claudia, ricardo, "Turno Concluído — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(5), "125.00", 8.0, false, false);
        Turno t16 = pendente(fernando, thiago, "Turno Tarde — Pizzaria do Fernando",
                "Batel, Curitiba", agora.minusDays(4), "95.00", 5.0, true, false);
        Turno t17 = pendente(ana, lucas, "Turno Concluído — Farmácia Ana",
                "Centro Cívico, Curitiba", agora.minusDays(6), "110.00", 6.0, false, true);
        pendente(claudia, thiago, "Turno Madrugada — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(8), "140.00", 8.0, false, false);

        // ── Cancelados ───────────────────────────────────────────────────────
        // O ScoreService conta como tardio o cancelamento feito a menos de 1h
        // do início. O do Ricardo foi com dias de folga; o do Thiago, em cima
        // da hora — é o evento que explica o score dele.

        LocalDateTime ricardoCancelou = redondo(agora.plusDays(3));
        turno(fernando, ricardo, "Turno Cancelado — Pizzaria do Fernando", "Turno cancelado",
                "Batel, Curitiba", ricardoCancelou, ricardoCancelou.plusHours(4),
                "100.00", 5.0, StatusTurno.CANCELADO);
        LocalDateTime thiagoCancelou = agora.plusMinutes(30).truncatedTo(ChronoUnit.MINUTES);
        Turno canceladoTardio = turno(claudia, thiago, "Turno Cancelado — Hamburgueria da Cláudia",
                "Turno cancelado", "Água Verde, Curitiba", thiagoCancelou, thiagoCancelou.plusHours(4),
                "120.00", 8.0, StatusTurno.CANCELADO);

        // ── Saque ────────────────────────────────────────────────────────────
        // Depois de t9 e t8 creditados (R$ 220), nunca deixando saldo negativo.

        saque(ricardo, "200.00", agora.minusDays(6), "ricardo@pix.com", saldos);

        // ── Carteiras ────────────────────────────────────────────────────────
        // Saldo = soma do extrato criado acima, e não um número à parte: é o
        // que mantém "saldo" e "extrato" contando a mesma história.

        // Toda conta tem carteira, como no cadastro (AuthService.registrar).
        for (Usuario u : List.of(claudia, fernando, ana, maria, thiago, carlos)) {
            carteira(u, saldos.de(u), null);
        }
        carteira(ricardo, saldos.de(ricardo), "ricardo@pix.com");
        carteira(lucas, saldos.de(lucas), "lucas@pix.com");

        // ── Avaliações ───────────────────────────────────────────────────────

        avaliacao(t8, ricardo, claudia, 5, "Ótima organização");
        avaliacao(t8, claudia, ricardo, 5, "Pontual e educado");
        avaliacao(t9, ricardo, fernando, 5, "Tudo certo, sem atrasos");
        avaliacao(t9, fernando, ricardo, 5, "Profissional dedicado");
        avaliacao(t10, lucas, ana, 4, "Boa comunicação");
        avaliacao(t10, ana, lucas, 5, "Excelente profissional");
        // Só o lojista avaliou
        avaliacao(t11, claudia, thiago, 3, "Atrasou 15 minutos");
        avaliacao(t12, fernando, lucas, 5, "Trabalho impecável");
        // Pendentes de pagamento, os dois lados já avaliaram
        avaliacao(t15, ricardo, claudia, 5, "Boa, como sempre");
        avaliacao(t15, claudia, ricardo, 5, "Sempre confiável");
        avaliacao(t16, thiago, fernando, 4, "Pedidos organizados");
        avaliacao(t16, fernando, thiago, 4, "Boa entrega");
        avaliacao(t17, lucas, ana, 5, "Excelente lojista");
        avaliacao(t17, ana, lucas, 5, "Sempre pontual e simpático");

        // ── Notas fiscais ────────────────────────────────────────────────────
        // Só para parte dos concluídos, de propósito: a tela "Notas fiscais"
        // abre com as duas metades — emitidas e a emitir.

        emitirNota(t8, ricardo);
        emitirNota(t9, ricardo);
        emitirNota(t10, lucas);

        // ── Notificações ─────────────────────────────────────────────────────
        // Criadas agora, então sempre recentes. Algumas já lidas, para o sino
        // mostrar os dois estados.

        notificar(claudia, "turno_aceito", "Vaga preenchida",
                ricardo.getNome() + " aceitou o turno \"" + emAndamento.getTitulo() + "\" (1/1 vagas).",
                "turno", emAndamento, true);
        notificar(claudia, "avaliacao_pendente", "Turno finalizado",
                "O turno \"" + t14.getTitulo() + "\" foi finalizado. Confirme o pagamento e avalie a outra parte.",
                "turno", t14, false);
        notificar(ricardo, "pagamento_confirmado", "Pagamento confirmado",
                "O pagamento do turno \"" + t13.getTitulo() + "\" foi creditado na sua carteira.",
                "carteira", t13, false);
        notificar(ricardo, "avaliacao_pendente", "Turno finalizado",
                "O turno \"" + t13.getTitulo() + "\" foi finalizado. Avalie o lojista.",
                "turno", t13, true);
        notificar(lucas, "avaliacao_pendente", "Turno finalizado",
                "O turno \"" + t14.getTitulo() + "\" foi finalizado. Avalie o lojista.",
                "turno", t14, false);
        notificar(thiago, "pagamento_pendente", "Confirme o recebimento",
                fernando.getNome() + " confirmou o pagamento do turno \"" + t16.getTitulo()
                        + "\". Confirme que recebeu.",
                "turno", t16, false);
        notificar(thiago, "turno_cancelado", "Turno cancelado",
                "O turno \"" + canceladoTardio.getTitulo() + "\" foi cancelado.",
                "turno", canceladoTardio, false);
        notificar(lucas, "pagamento_pendente", "Aguardando o lojista",
                "Você confirmou o recebimento do turno \"" + t17.getTitulo()
                        + "\". Falta a confirmação de " + ana.getNome() + ".",
                "turno", t17, true);
    }

    // ── Pessoas ──────────────────────────────────────────────────────────────

    private Usuario lojista(String nome, String email, String telefone, String cnpj,
                            LocalDate nascimento, String cidade, String uf,
                            String fantasia, String endereco, Double media) {
        Usuario u = conta(nome, email, telefone, "lojista", cnpj, 5.0, media);
        u.setDataNascimento(nascimento);
        u.setCidade(cidade);
        u.setEstado(uf);
        u.setNomeFantasia(fantasia);
        u.setEnderecoComercial(endereco);
        return usuarioRepo.save(u);
    }

    private Usuario motoboy(String nome, String email, String telefone, String cnh, String categoria,
                            LocalDate validadeCnh, LocalDate nascimento, String cidade, String uf,
                            String modelo, String placa, int ano, String cor,
                            double score, Double media) {
        Usuario u = conta(nome, email, telefone, "motoboy", cnh, score, media);
        u.setDataNascimento(nascimento);
        u.setCidade(cidade);
        u.setEstado(uf);
        u.setCnhNumero(cnh);
        u.setCnhCategoria(categoria);
        u.setCnhValidade(validadeCnh);
        u.setVeiculoModelo(modelo);
        u.setVeiculoPlaca(placa);
        u.setVeiculoAno(ano);
        u.setVeiculoCor(cor);
        return usuarioRepo.save(u);
    }

    private Usuario conta(String nome, String email, String telefone, String tipo,
                          String documento, double score, Double media) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(email);
        // Hash sempre: o login só conhece BCrypt.
        u.setSenha(encoder.encode(SENHA));
        u.setTelefone(telefone);
        u.setTipo(tipo);
        u.setDocumentoFederal(documento);
        u.setScore(score);
        u.setMediaAvaliacao(media);
        return u;
    }

    // ── Turnos ───────────────────────────────────────────────────────────────

    private Turno turno(Usuario lojista, Usuario motoboy, String titulo, String descricao,
                        String regiao, LocalDateTime inicio, LocalDateTime fim,
                        String valor, double raio, StatusTurno status) {
        return turno(lojista, motoboy, titulo, descricao, regiao, inicio, fim, valor, raio, status, null);
    }

    private Turno turno(Usuario lojista, Usuario motoboy, String titulo, String descricao,
                        String regiao, LocalDateTime inicio, LocalDateTime fim,
                        String valor, double raio, StatusTurno status,
                        StatusPagamento pagamento) {
        Turno t = new Turno();
        t.setLojistId(lojista.getId());
        t.setMotoboyId(motoboy == null ? null : motoboy.getId());
        t.setTitulo(titulo);
        t.setDescricao(descricao);
        t.setRegiao(regiao);
        t.setDataInicio(inicio);
        t.setDataFim(fim);
        t.setValorEstimado(new BigDecimal(valor));
        t.setRaioEntregaKm(raio);
        // Sem coordenada o turno não aparece no filtro por raio (SCRUM-18) e o
        // mapa da tela de detalhe fica vazio.
        double[] coord = coordenadaDaRegiao(regiao, titulo);
        t.setLatitude(coord[0]);
        t.setLongitude(coord[1]);
        t.setEndereco(regiao);
        t.setStatus(status);
        t.setPagamentoStatus(pagamento);
        Turno salvo = turnoRepo.save(t);

        // Todo turno com entregador tem inscrição — é o formato pós-V5, e sem
        // ela confirmar pagamento na massa estouraria 500.
        if (motoboy != null) {
            inscricao(salvo, motoboy, statusDaInscricao(status), null, null, null);
        }
        return salvo;
    }

    private Turno pago(Usuario lojista, Usuario motoboy, String titulo, String regiao,
                       LocalDateTime inicio, String valor, double raio, Saldos saldos) {
        LocalDateTime fim = inicio.plusHours(4);
        Turno t = turno(lojista, motoboy, titulo, "Turno concluído", regiao, inicio, fim,
                valor, raio, StatusTurno.FINALIZADO, StatusPagamento.PAGO);
        inscricao(t, motoboy, StatusInscricao.FINALIZADO, StatusPagamento.PAGO,
                fim.plusHours(1), fim.plusHours(2));
        pagamento(t, motoboy, StatusTransacao.CONCLUIDO, fim);
        saldos.creditar(motoboy, t.getValorEstimado());
        return t;
    }

    private Turno pendente(Usuario lojista, Usuario motoboy, String titulo, String regiao,
                           LocalDateTime inicio, String valor, double raio,
                           boolean lojistaConfirmou, boolean motoboyConfirmou) {
        LocalDateTime fim = inicio.plusHours(4);
        Turno t = turno(lojista, motoboy, titulo, "Turno concluído", regiao, inicio, fim,
                valor, raio, StatusTurno.FINALIZADO, StatusPagamento.PENDENTE);
        inscricao(t, motoboy, StatusInscricao.FINALIZADO, StatusPagamento.PENDENTE,
                lojistaConfirmou ? fim.plusHours(1) : null,
                motoboyConfirmou ? fim.plusHours(2) : null);
        pagamento(t, motoboy, StatusTransacao.PENDENTE, fim);
        return t;
    }

    private void inscricao(Turno t, Usuario motoboy, StatusInscricao status,
                           StatusPagamento pagamento,
                           LocalDateTime lojistaConfirmou, LocalDateTime motoboyConfirmou) {
        TurnoInscricao ins = inscricaoRepo
                .findByTurnoIdAndMotoboyId(t.getId(), motoboy.getId())
                .orElseGet(TurnoInscricao::new);
        ins.setTurnoId(t.getId());
        ins.setMotoboyId(motoboy.getId());
        ins.setStatus(status);
        ins.setPagamentoStatus(pagamento);
        ins.setLojistaConfirmouEm(lojistaConfirmou);
        ins.setMotoboyConfirmouEm(motoboyConfirmou);
        inscricaoRepo.save(ins);
    }

    /** O mesmo mapeamento da V5: só os estados terminais têm correspondência. */
    private static StatusInscricao statusDaInscricao(StatusTurno status) {
        return switch (status) {
            case FINALIZADO -> StatusInscricao.FINALIZADO;
            case CANCELADO  -> StatusInscricao.CANCELADO;
            default         -> StatusInscricao.ACEITO;
        };
    }

    /**
     * Coordenada aproximada do bairro, com um deslocamento determinístico
     * derivado do título para que turnos do mesmo bairro não caiam no mesmo
     * ponto exato.
     */
    private static double[] coordenadaDaRegiao(String regiao, String titulo) {
        double lat, lng;
        String r = regiao == null ? "" : regiao.toLowerCase();
        if (r.contains("agua verde") || r.contains("água verde")) { lat = -25.4560; lng = -49.2820; }
        else if (r.contains("batel"))                             { lat = -25.4420; lng = -49.2900; }
        else if (r.contains("civico") || r.contains("cívico"))    { lat = -25.4160; lng = -49.2690; }
        else                                                      { lat = -25.4284; lng = -49.2733; }

        // Jitter de até ~600 m, estável entre execuções.
        int h = titulo == null ? 0 : Math.abs(titulo.hashCode());
        lat += ((h % 100) - 50) / 10000.0;
        lng += (((h / 100) % 100) - 50) / 10000.0;
        return new double[] { lat, lng };
    }

    /** Hora cheia — turno de demonstração não começa às 14:37. */
    private static LocalDateTime redondo(LocalDateTime t) {
        return t.truncatedTo(ChronoUnit.HOURS);
    }

    // ── Dinheiro ─────────────────────────────────────────────────────────────

    /** Lançamento do pagamento de um turno, com a chave que o fluxo real usa. */
    private void pagamento(Turno t, Usuario motoboy, StatusTransacao status, LocalDateTime quando) {
        Transacao tx = new Transacao();
        tx.setUsuarioId(motoboy.getId());
        tx.setContraparteId(t.getLojistId());
        tx.setTurnoId(t.getId());
        tx.setTipo(TipoTransacao.PAGAMENTO_RECEBIDO);
        tx.setNatureza(com.motoshift.entity.NaturezaTransacao.CREDITO);
        tx.setValor(t.getValorEstimado());
        tx.setDescricao((status == StatusTransacao.PENDENTE ? "Turno aguardando pagamento: " : "Turno finalizado: ")
                + t.getTitulo());
        tx.setStatus(status);
        tx.setIdempotencyKey(PagamentoTurnoService.chaveDoPagamento(t.getId(), motoboy.getId()));
        // Datado no fim do turno, e não "agora": é o que dá mais de uma barra ao
        // gráfico mensal e deixa "ganhos do mês" com um recorte de verdade.
        tx.setCriadoEm(quando);
        transacaoRepo.save(tx);
    }

    private void saque(Usuario u, String valor, LocalDateTime quando, String pix, Saldos saldos) {
        Transacao tx = new Transacao();
        tx.setUsuarioId(u.getId());
        tx.setTipo(TipoTransacao.SAQUE);
        tx.setNatureza(com.motoshift.entity.NaturezaTransacao.DEBITO);
        tx.setValor(new BigDecimal(valor));
        tx.setDescricao("Transferência Pix — " + pix);
        tx.setStatus(StatusTransacao.CONCLUIDO);
        tx.setIdempotencyKey("saque:" + u.getId() + ":massa-demonstracao");
        tx.setCriadoEm(quando);
        transacaoRepo.save(tx);
        saldos.debitar(u, tx.getValor());
    }

    private void carteira(Usuario u, BigDecimal saldo, String pix) {
        Carteira c = new Carteira();
        c.setUsuarioId(u.getId());
        c.setSaldoDisponivel(saldo);
        c.setChavePix(pix);
        carteiraRepo.save(c);
    }

    /** Acumula o saldo que o extrato criado implica, por conta. */
    private static final class Saldos {
        private final Map<Long, BigDecimal> porConta = new HashMap<>();

        void creditar(Usuario u, BigDecimal valor) {
            porConta.merge(u.getId(), valor, BigDecimal::add);
        }

        void debitar(Usuario u, BigDecimal valor) {
            porConta.merge(u.getId(), valor.negate(), BigDecimal::add);
        }

        BigDecimal de(Usuario u) {
            return porConta.getOrDefault(u.getId(), BigDecimal.ZERO);
        }
    }

    // ── Avaliações, notas e notificações ─────────────────────────────────────

    private void avaliacao(Turno t, Usuario avaliador, Usuario avaliado, int nota, String comentario) {
        Avaliacao a = new Avaliacao();
        a.setTurnoId(t.getId());
        a.setAvaliadorId(avaliador.getId());
        a.setAvaliadoId(avaliado.getId());
        a.setNota(nota);
        a.setComentario(comentario);
        avaliacaoRepo.save(a);
    }

    /**
     * Nota de um turno da massa, emitida pelo entregador.
     *
     * No boot de dev, uma falha aqui é só registrada: se a regra do serviço
     * mudar e o turno deixar de ser elegível, o app sobe sem as notas de
     * exemplo em vez de não subir. Dentro do {@link #resetar()} a falha marca a
     * transação para rollback — e o reset inteiro é desfeito, que é o que se
     * quer de uma operação atômica.
     */
    private void emitirNota(Turno turno, Usuario motoboy) {
        try {
            notasFiscais.emitir(turno.getId(), motoboy.getId(), motoboy.getId());
        } catch (RuntimeException e) {
            log.warn("[massa] nota fiscal do turno {} nao emitida: {}", turno.getId(), e.getMessage());
        }
    }

    private void notificar(Usuario destinatario, String tipo, String titulo, String mensagem,
                           String referenciaTipo, Turno referencia, boolean lida) {
        Notificacao n = notificacoes.criar(destinatario.getId(), tipo, titulo, mensagem,
                referenciaTipo, referencia.getId());
        if (lida) {
            notificacoes.marcarComoLida(n.getId(), destinatario.getId());
        }
    }
}
