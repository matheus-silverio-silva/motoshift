package com.motoshift.config;

import com.motoshift.dto.AvaliacaoRequest;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.entity.StatusTurno;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.AvaliacaoService;
import com.motoshift.service.CarteiraService;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.service.PagamentoTurnoService;
import com.motoshift.service.TurnoExpiracaoService;
import com.motoshift.service.TurnoService;
import jakarta.persistence.EntityManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Massa de demonstração: 8 contas e cinco meses de história contados pelos
 * mesmos serviços que o app usa.
 *
 * <p><b>A história.</b> Quatro lojas — três em Curitiba e o Mercado Andrade
 * em São Paulo — recarregam a carteira todo mês, publicam turnos toda semana e
 * pagam os entregadores na finalização; os entregadores sacam uma vez por mês.
 * Os dois lados se avaliam, o lojista emite a nota de cada pagamento (uma já
 * foi cancelada), e os pagamentos da última semana ainda estão sem nota — "a
 * emitir" para o lojista, "aguardando emissão" para o entregador. Há um turno
 * com três entregadores (três notas), turnos com vaga sobrando, um expirado,
 * um cancelado com folga e um cancelado em cima da hora, que é o que explica o
 * score do Thiago. E há o presente: turnos abertos, um em andamento e dois
 * confirmados para amanhã.
 *
 * <p><b>Nada é gravado à mão.</b> Recarga e saque passam pelo
 * {@link CobrancaService}; aceite, finalização e cancelamento pelo
 * {@link TurnoService}; avaliação pelo {@link AvaliacaoService} (que recalcula
 * a média); nota pelo {@link NotaFiscalService}, sempre a pedido do lojista;
 * o vencimento pelo próprio job ({@link TurnoExpiracaoService}). Por isso o
 * score e a média são os que a regra produz, as notificações são as que o
 * código gera hoje — com os textos de hoje —, e a massa termina passando em
 * {@code ConsistenciaService.verificarConsistencia()}. A única coisa que vai
 * direto ao repositório é o turno do passado: a RF04 não deixa publicar com
 * menos de 2h de antecedência, e um turno de três meses atrás não tem como
 * respeitá-la hoje. Ele nasce pelo repositório e reserva pelo
 * {@link PagamentoTurnoService}, como o {@code criar} faria.
 *
 * <p><b>Datas.</b> Tudo é derivado de "agora" no momento da execução —
 * inclusive nascimento e validade de CNH. Os serviços carimbam o que gravam
 * com a hora em que rodam, e deve ser assim; a massa — e só ela — reescreve
 * depois a data do que cada passo gravou ({@link Enredo#em}). A história é
 * executada em ordem cronológica, para o "saldo após" de cada lançamento bater
 * com a ordem em que o extrato o mostra.
 *
 * <p><b>Escopo do reset.</b> A massa é identificada por uma coisa só: e-mail
 * terminado em {@link #SUFIXO_EMAIL}. {@link #resetar()} apaga só ela e o que
 * uma conta real fez com ela; {@link #apagarTudoERecriar()} apaga todos os
 * dados de negócio. Os dois são uma transação só — ver
 * {@link ResetDaMassaNoBoot}.
 */
@Component
public class MassaDemonstracao {

    /** O que marca uma conta como massa de demonstração. Único lugar com esta string. */
    public static final String SUFIXO_EMAIL = "@teste.com";

    /** Senha de todas as contas da massa (sempre gravada com hash). */
    public static final String SENHA = "senha123";

    /** Semanas de história antes da semana atual — pouco mais de cinco meses. */
    static final int SEMANAS_DE_HISTORIA = 22;

    private static final Logger log = LoggerFactory.getLogger(MassaDemonstracao.class);

    /** Id que nunca existe: evita IN () vazio nas consultas de limpeza. */
    private static final List<Long> NENHUM = List.of(-1L);

    private final EntityManager em;
    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;
    private final CarteiraRepository carteiraRepo;
    private final PasswordEncoder encoder;
    private final PagamentoTurnoService pagamentos;
    private final TurnoService turnos;
    private final TurnoExpiracaoService expiracao;
    private final CobrancaService cobrancas;
    private final CarteiraService carteiras;
    private final AvaliacaoService avaliacoes;
    private final NotaFiscalService notasFiscais;

    public MassaDemonstracao(EntityManager em,
                             UsuarioRepository usuarioRepo,
                             TurnoRepository turnoRepo,
                             CarteiraRepository carteiraRepo,
                             PasswordEncoder encoder,
                             PagamentoTurnoService pagamentos,
                             TurnoService turnos,
                             TurnoExpiracaoService expiracao,
                             CobrancaService cobrancas,
                             CarteiraService carteiras,
                             AvaliacaoService avaliacoes,
                             NotaFiscalService notasFiscais) {
        this.em = em;
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
        this.encoder = encoder;
        this.pagamentos = pagamentos;
        this.turnos = turnos;
        this.expiracao = expiracao;
        this.cobrancas = cobrancas;
        this.carteiras = carteiras;
        this.avaliacoes = avaliacoes;
        this.notasFiscais = notasFiscais;
    }

    // ══ Reset: só a massa ═════════════════════════════════════════════════

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
        n.put("cobrancas",        contar("select count(c) from Cobranca c" + ONDE_COBRANCA, e));
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
    // Cobranca so tem um dono, entao o escopo e mais simples que o da transacao.
    private static final String ONDE_COBRANCA =
            " where c.usuarioId in :demo";
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
        n.put("cobrancas",        executar("delete from Cobranca c" + ONDE_COBRANCA, e));
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

    // ══ Reset total: todos os dados de negócio ════════════════════════════

    /**
     * As tabelas de domínio na ordem das chaves estrangeiras — de quem
     * referencia para quem é referenciado (V11, V12 e V14). É a ordem em que
     * se apaga. O {@code flyway_schema_history} não está aqui de propósito: não
     * é dado de negócio, e sem ele o próximo boot tentaria reaplicar as
     * migrações num banco que já as tem.
     */
    private static final Map<String, String> TABELAS_DE_NEGOCIO = tabelasDeNegocio();

    private static Map<String, String> tabelasDeNegocio() {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("notas_fiscais",    "NotaFiscal");
        m.put("avaliacoes",       "Avaliacao");
        m.put("transacoes",       "Transacao");
        m.put("cobrancas",        "Cobranca");
        m.put("turno_inscricoes", "TurnoInscricao");
        m.put("notificacoes",     "Notificacao");
        m.put("turnos",           "Turno");
        m.put("carteiras",        "Carteira");
        m.put("usuarios",         "Usuario");
        return m;
    }

    /**
     * Apaga TODOS os dados de negócio — contas reais inclusive — e cria a
     * massa de novo. É o {@code MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo}.
     *
     * <p>DELETE, tabela por tabela, na ordem das FKs; nunca TRUNCATE nem DROP.
     * O schema, as migrações e o {@code flyway_schema_history} ficam como
     * estão. Uma transação só: se a massa falhar no meio, nada foi apagado.
     *
     * @return as contagens por tabela antes, depois de apagar e no fim — o
     *         que o log mostra
     */
    @Transactional
    public Map<String, long[]> apagarTudoERecriar() {
        Map<String, Long> antes = contarTudo();
        Map<String, Long> apagados = new LinkedHashMap<>();
        for (Map.Entry<String, String> t : TABELAS_DE_NEGOCIO.entrySet()) {
            apagados.put(t.getKey(), (long) em.createQuery("delete from " + t.getValue()).executeUpdate());
        }
        popular();
        Map<String, Long> depois = contarTudo();

        Map<String, long[]> resumo = new LinkedHashMap<>();
        StringBuilder texto = new StringBuilder("[massa] reset TOTAL concluido — todos os dados de negocio")
                .append(String.format("%n  %-17s %8s %9s %8s", "tabela", "antes", "apagados", "depois"));
        for (String tabela : TABELAS_DE_NEGOCIO.keySet()) {
            long[] linha = {antes.get(tabela), apagados.get(tabela), depois.get(tabela)};
            resumo.put(tabela, linha);
            texto.append(String.format("%n  %-17s %8d %9d %8d", tabela, linha[0], linha[1], linha[2]));
        }
        log.warn(texto.toString());
        return resumo;
    }

    /** Linhas de cada tabela de negócio — o banco inteiro, não só a massa. */
    @Transactional(readOnly = true)
    public Map<String, Long> contarTudo() {
        Map<String, Long> n = new LinkedHashMap<>();
        for (Map.Entry<String, String> t : TABELAS_DE_NEGOCIO.entrySet()) {
            n.put(t.getKey(), em.createQuery("select count(x) from " + t.getValue() + " x", Long.class)
                    .getSingleResult());
        }
        return n;
    }

    // ══ Criação ═══════════════════════════════════════════════════════════

    /**
     * Cria a massa inteira, numa transação só: uma falha no meio deixaria
     * saldo bloqueado sem turno, ou turno sem lastro. Tudo ou nada.
     */
    @Transactional
    public void popular() {
        new Enredo(LocalDateTime.now()).contar();
    }

    /**
     * A história da massa, com o "agora" fixado no começo — para a mesma
     * execução não ver duas horas diferentes.
     */
    private final class Enredo {

        private final LocalDateTime agora;
        private final LocalDate hoje;

        private Usuario claudia, fernando, ana, maria;
        private Usuario ricardo, lucas, thiago, carlos;

        Enredo(LocalDateTime agora) {
            this.agora = agora.truncatedTo(ChronoUnit.SECONDS);
            this.hoje = this.agora.toLocalDate();
        }

        void contar() {
            pessoas();
            passado();
            ultimosDias();
            presente();
        }

        // ── Pessoas ──────────────────────────────────────────────────────

        /**
         * As oito contas do README. Nenhuma recebe score nem média: o score é
         * o inicial da regra (5,0) até um cancelamento tardio mudá-lo, e a
         * média nasce da primeira avaliação.
         */
        private void pessoas() {
            claudia = lojista("Cláudia Oliveira", "claudia@teste.com", "(41) 99111-2222",
                    "12.345.678/0001-90", hoje.minusYears(41).minusDays(80), "Curitiba", "PR",
                    "Hamburgueria da Cláudia", "Av. Água Verde, 1200 — Água Verde, Curitiba/PR");
            fernando = lojista("Fernando Costa", "fernando@teste.com", "(41) 99333-4444",
                    "98.765.432/0001-10", hoje.minusYears(48).minusDays(210), "Curitiba", "PR",
                    "Pizzaria do Fernando", "R. Comendador Araújo, 450 — Batel, Curitiba/PR");
            ana = lojista("Ana Souza", "ana@teste.com", "(41) 99555-6666",
                    "11.222.333/0001-44", hoje.minusYears(35).minusDays(150), "Curitiba", "PR",
                    "Farmácia Ana", "R. XV de Novembro, 980 — Centro Cívico, Curitiba/PR");
            maria = lojista("Maria Andrade", "lojista@teste.com", "(11) 91234-5678",
                    "12.345.678/0001-99", hoje.minusYears(44).minusDays(30), "São Paulo", "SP",
                    "Mercado Andrade", "Av. Paulista, 1500 — Bela Vista, São Paulo/SP");

            ricardo = motoboy("Ricardo Souza", "ricardo@teste.com", "(41) 98111-2222",
                    "12345678900", "A", hoje.plusYears(2).plusMonths(9), hoje.minusYears(31).minusDays(40),
                    "Curitiba", "PR", "Honda CG 160 Titan", "ABC-1D23", hoje.getYear() - 4, "Vermelha");
            lucas = motoboy("Lucas Mendes", "lucas@teste.com", "(41) 98333-4444",
                    "98765432100", "AB", hoje.plusYears(1).plusMonths(2), hoje.minusYears(33).minusDays(250),
                    "Curitiba", "PR", "Yamaha Factor 150", "DEF-2E34", hoje.getYear() - 3, "Preta");
            thiago = motoboy("Thiago Alves", "thiago@teste.com", "(41) 98555-6666",
                    "55566677788", "A", hoje.plusMonths(7), hoje.minusYears(27).minusDays(290),
                    "Curitiba", "PR", "Honda Biz 125", "GHI-3F45", hoje.getYear() - 6, "Branca");
            carlos = motoboy("Carlos Mendes", "motoboy@teste.com", "(11) 99876-5432",
                    "11122233344", "A", hoje.plusYears(3), hoje.minusYears(34).minusDays(33),
                    "São Paulo", "SP", "Honda PCX 150", "JKL-4G56", hoje.getYear() - 2, "Azul");

            // Toda conta tem carteira, como no cadastro; a chave Pix do
            // entregador é o que o saque exige.
            for (Usuario u : List.of(claudia, fernando, ana, maria)) {
                carteiras.obterOuCriar(u.getId());
            }
            carteiras.atualizarPix(ricardo.getId(), "ricardo@pix.com");
            carteiras.atualizarPix(lucas.getId(), "lucas@pix.com");
            carteiras.atualizarPix(thiago.getId(), "thiago@pix.com");
            carteiras.atualizarPix(carlos.getId(), "carlos@pix.com");
        }

        // ── Passado: cinco meses, semana a semana ────────────────────────

        /**
         * {@link #SEMANAS_DE_HISTORIA} semanas completas. Em cada uma: no
         * primeiro dia, as recargas do mês e os saques; depois, os turnos da
         * semana, cada um com publicação, aceite, finalização, avaliação dos
         * dois lados e nota emitida pelo lojista no dia seguinte.
         */
        private void passado() {
            List<Plano> planos = new ArrayList<>();
            for (int w = SEMANAS_DE_HISTORIA; w >= 1; w--) {
                LocalDate base = hoje.minusWeeks(w);
                LocalDate segunda = base.minusDays(6);

                if (w % 4 == 2 || w == SEMANAS_DE_HISTORIA) {
                    boolean primeira = w == SEMANAS_DE_HISTORIA;
                    LocalDateTime cedo = segunda.atTime(8, 0);
                    recarga(claudia, primeira ? "1200.00" : "700.00", cedo);
                    recarga(fernando, primeira ? "600.00" : "300.00", cedo.plusMinutes(5));
                    recarga(ana, primeira ? "500.00" : "250.00", cedo.plusMinutes(10));
                    recarga(maria, primeira ? "800.00" : "450.00", cedo.plusMinutes(15));
                }
                if (w % 4 == 1) {
                    LocalDateTime almoco = segunda.atTime(12, 0);
                    sacarParte(ricardo, almoco);
                    sacarParte(lucas, almoco.plusMinutes(10));
                    sacarParte(thiago, almoco.plusMinutes(20));
                    sacarParte(carlos, almoco.plusMinutes(30));
                }

                planos.clear();
                planos.add(noiteDaClaudia(w, base.minusDays(1)));
                planos.add(tardeDaMaria(w, base.minusDays(2)));
                if (w % 2 == 0) planos.add(almocoDoFernando(w, base.minusDays(3)));
                if (w % 3 == 0) planos.add(manhaDaAna(w, base.minusDays(5)));
                planos.sort(Comparator.comparing(Plano::fim));
                for (Plano p : planos) executar(p);

                // Cada flush confere todas as entidades gerenciadas; sem soltar
                // as da semana que passou, o custo cresce com a história.
                em.flush();
                em.clear();
            }
        }

        private Plano noiteDaClaudia(int w, LocalDate dia) {
            LocalDateTime inicio = dia.atTime(18, 0);
            Usuario[] vez = {ricardo, lucas, thiago};
            if (w == 2) {
                // O turno de sábado com três vagas: três entregadores, três
                // pagamentos, três notas — uma por entregador.
                return new Plano(claudia, "Turno Sábado — Hamburgueria da Cláudia (3 vagas)",
                        "Noite de movimento: três entregadores na mesma escala",
                        "Água Verde, Curitiba", inicio, inicio.plusHours(4), "130.00", 3,
                        List.of(ricardo, lucas, thiago), w);
            }
            if (w % 4 == 0) {
                // Duas vagas, um entregador: a sobra da reserva volta à loja
                // como liberação — o caso que prova que vaga vazia não prende
                // dinheiro.
                return new Plano(claudia, "Turno Dupla — Hamburgueria da Cláudia",
                        "Duas vagas; uma ficou em aberto", "Água Verde, Curitiba",
                        inicio, inicio.plusHours(4), "120.00", 2, List.of(vez[w % 3]), w);
            }
            return new Plano(claudia, "Turno Noite — Hamburgueria da Cláudia", "Entregas noturnas",
                    "Água Verde, Curitiba", inicio, inicio.plusHours(4),
                    w % 5 == 0 ? "140.00" : "130.00", 1, List.of(vez[w % 3]), w);
        }

        private Plano tardeDaMaria(int w, LocalDate dia) {
            LocalDateTime inicio = dia.atTime(14, 0);
            return new Plano(maria, "Turno Tarde — Mercado Andrade", "Entregas de compras do mercado",
                    "Bela Vista, São Paulo", inicio, inicio.plusHours(4),
                    w % 3 == 0 ? "100.00" : "95.00", 1, List.of(carlos), w);
        }

        private Plano almocoDoFernando(int w, LocalDate dia) {
            LocalDateTime inicio = dia.atTime(11, 0);
            return new Plano(fernando, "Turno Almoço — Pizzaria do Fernando", "Entregas zona Batel e adjacências",
                    "Batel, Curitiba", inicio, inicio.plusHours(4), "100.00", 1,
                    List.of(w % 4 == 0 ? ricardo : lucas), w);
        }

        private Plano manhaDaAna(int w, LocalDate dia) {
            LocalDateTime inicio = dia.atTime(8, 0);
            return new Plano(ana, "Turno Manhã — Farmácia Ana", "Entregas de medicamentos",
                    "Centro Cívico, Curitiba", inicio, inicio.plusHours(4), "110.00", 1,
                    List.of(w % 2 == 0 ? thiago : lucas), w);
        }

        /** Um turno do passado, da publicação à nota. */
        private void executar(Plano p) {
            Turno t = publicarNoPassado(p);
            for (int i = 0; i < p.entregadores().size(); i++) {
                Usuario e = p.entregadores().get(i);
                em(p.inicio().minusHours(20).plusMinutes(10L * i), () -> turnos.aceitar(t.getId(), e.getId()));
            }
            em(p.fim(), () -> turnos.finalizar(t.getId(), p.lojista().getId()));

            for (int i = 0; i < p.entregadores().size(); i++) {
                Usuario e = p.entregadores().get(i);
                avaliarOsDois(t, p.lojista(), e, p.fim().plusHours(1).plusMinutes(10L * i), p.semana() + i);
            }
            LocalDateTime emissao = p.fim().toLocalDate().plusDays(1).atTime(10, 0);
            for (int i = 0; i < p.entregadores().size(); i++) {
                Usuario e = p.entregadores().get(i);
                em(emissao.plusMinutes(i), () -> notasFiscais.emitir(t.getId(), e.getId(), p.lojista().getId()));
            }
            // Uma nota cancelada pelo lojista — não estorna nada: o pagamento
            // continua no extrato, e o entregador é avisado.
            if (p.lojista() == fernando && p.semana() == 6) {
                Long nota = notaDe(t, p.entregadores().get(0));
                LocalDateTime cancelada = emissao.plusHours(3);
                em(cancelada, () -> notasFiscais.cancelar(nota,
                        "Emitida com a competência errada; o serviço segue registrado no extrato.",
                        fernando.getId()));
                // A nota já existia antes do passo, então o carimbo geral não a
                // alcança: a data do cancelamento vai direto nela.
                carimbar("update notas_fiscais set cancelada_em = :q where id = :id", cancelada, nota);
            }
            carimbarTurno(t, p.publicacao(), p.fim());
        }

        // ── Últimos dias: o que ainda está pendente ──────────────────────

        /**
         * A semana corrente: pagamentos que ainda não viraram nota (três),
         * avaliações por fazer e o turno que venceu sem ninguém.
         */
        private void ultimosDias() {
            LocalDate dia4 = hoje.minusDays(4), dia3 = hoje.minusDays(3), dia2 = hoje.minusDays(2);

            // Tudo feito: avaliado pelos dois e com nota emitida.
            Plano fernandoThiago = new Plano(fernando, "Turno Almoço — Pizzaria do Fernando",
                    "Entregas zona Batel e adjacências", "Batel, Curitiba",
                    dia4.atTime(11, 0), dia4.atTime(15, 0), "100.00", 1, List.of(thiago), 0);
            Turno t1 = publicarNoPassado(fernandoThiago);
            em(fernandoThiago.inicio().minusHours(20), () -> turnos.aceitar(t1.getId(), thiago.getId()));
            em(fernandoThiago.fim(), () -> turnos.finalizar(t1.getId(), fernando.getId()));
            avaliarOsDois(t1, fernando, thiago, fernandoThiago.fim().plusHours(1), 3);
            em(dia3.atTime(10, 0), () -> notasFiscais.emitir(t1.getId(), thiago.getId(), fernando.getId()));
            carimbarTurno(t1, fernandoThiago.publicacao(), fernandoThiago.fim());

            // Avaliado pelos dois, nota ainda não emitida: "a emitir" para a
            // Maria, "aguardando emissão" para o Carlos.
            Plano mariaCarlos = new Plano(maria, "Turno Tarde — Mercado Andrade",
                    "Entregas de compras do mercado", "Bela Vista, São Paulo",
                    dia3.atTime(14, 0), dia3.atTime(18, 0), "95.00", 1, List.of(carlos), 1);
            Turno t2 = publicarNoPassado(mariaCarlos);
            em(mariaCarlos.inicio().minusHours(20), () -> turnos.aceitar(t2.getId(), carlos.getId()));
            em(mariaCarlos.fim(), () -> turnos.finalizar(t2.getId(), maria.getId()));
            avaliarOsDois(t2, maria, carlos, mariaCarlos.fim().plusHours(1), 0);
            carimbarTurno(t2, mariaCarlos.publicacao(), mariaCarlos.fim());

            // Só o Ricardo avaliou; a Ana ainda deve a avaliação e a nota.
            Plano anaRicardo = new Plano(ana, "Turno Manhã — Farmácia Ana", "Entregas de medicamentos",
                    "Centro Cívico, Curitiba", dia3.atTime(8, 0), dia3.atTime(12, 0), "110.00", 1,
                    List.of(ricardo), 2);
            Turno t3 = publicarNoPassado(anaRicardo);
            em(anaRicardo.inicio().minusHours(20), () -> turnos.aceitar(t3.getId(), ricardo.getId()));
            em(anaRicardo.fim(), () -> turnos.finalizar(t3.getId(), ana.getId()));
            em(anaRicardo.fim().plusHours(2), () -> avaliar(t3, ricardo, ana, 5,
                    "Pedidos prontos no horário • Endereços corretos"));
            carimbarTurno(t3, anaRicardo.publicacao(), anaRicardo.fim());

            // Ninguém avaliou, ninguém emitiu: as duas pendências aparecem nos
            // dois lados.
            Plano claudiaLucas = new Plano(claudia, "Turno Noite — Hamburgueria da Cláudia",
                    "Entregas noturnas", "Água Verde, Curitiba", dia2.atTime(18, 0), dia2.atTime(22, 0),
                    "130.00", 1, List.of(lucas), 0);
            Turno t4 = publicarNoPassado(claudiaLucas);
            em(claudiaLucas.inicio().minusHours(20), () -> turnos.aceitar(t4.getId(), lucas.getId()));
            em(claudiaLucas.fim(), () -> turnos.finalizar(t4.getId(), claudia.getId()));
            carimbarTurno(t4, claudiaLucas.publicacao(), claudiaLucas.fim());

            // Publicado, ninguém aceitou, o início passou: quem vence o turno
            // e devolve a reserva é o próprio job de expiração.
            LocalDateTime inicioVencido = dia2.atTime(14, 0);
            Plano vencido = new Plano(ana, "Turno Tarde — Farmácia Ana", "Turno que venceu sem entregador",
                    "Centro Cívico, Curitiba", inicioVencido, inicioVencido.plusHours(4), "110.00", 1,
                    List.of(), 0);
            Turno t5 = publicarNoPassado(vencido);
            em(inicioVencido, expiracao::expirarTurnosNaoPreenchidos);
            carimbarTurno(t5, vencido.publicacao(), inicioVencido);
            carimbar("update turnos set expirado_em = :q where id = :id", inicioVencido, t5.getId());
        }

        // ── Presente ─────────────────────────────────────────────────────

        /**
         * O que a demonstração mostra ao vivo: turnos abertos, um em
         * andamento, dois confirmados para amanhã e dois cancelamentos — um
         * com folga e um em cima da hora, que custa 0,5 no score do Thiago.
         */
        private void presente() {
            LocalDateTime ontem = agora.minusDays(1);

            // Folga para a loja publicar mais um turno na frente da banca.
            reforcarSaldo(claudia, "1100.00", ontem.minusHours(1));
            reforcarSaldo(fernando, "700.00", ontem.minusHours(1).plusMinutes(5));
            reforcarSaldo(ana, "600.00", ontem.minusHours(1).plusMinutes(10));
            reforcarSaldo(maria, "600.00", ontem.minusHours(1).plusMinutes(15));

            LocalDateTime amanha = agora.plusDays(1).truncatedTo(ChronoUnit.DAYS);
            LocalDateTime depoisDeAmanha = agora.plusDays(2).truncatedTo(ChronoUnit.DAYS);

            // Cancelado com folga, pelo entregador: sem penalidade.
            LocalDateTime em3Dias = redondo(agora.plusDays(3));
            Turno folga = publicar(fernando, "Turno Noite — Pizzaria do Fernando", "Turno cancelado com folga",
                    "Batel, Curitiba", em3Dias, em3Dias.plusHours(4), "100.00", 1, ontem);
            em(agora.minusHours(18), () -> turnos.aceitar(folga.getId(), ricardo.getId()));
            LocalDateTime cancelouComFolga = agora.minusHours(5);
            em(cancelouComFolga, () -> turnos.cancelar(folga.getId(), ricardo.getId()));
            carimbarTurno(folga, ontem, cancelouComFolga);

            // Confirmados para amanhã.
            Turno anaLucas = publicar(ana, "Turno Confirmado — Farmácia Ana", "Entregas de medicamentos à tarde",
                    "Centro Cívico, Curitiba", amanha.with(LocalTime.of(14, 0)), amanha.with(LocalTime.of(18, 0)),
                    "110.00", 1, ontem.plusHours(1));
            em(agora.minusHours(20), () -> turnos.aceitar(anaLucas.getId(), lucas.getId()));
            carimbarTurno(anaLucas, ontem.plusHours(1), agora.minusHours(20));

            Turno mariaCarlos = publicar(maria, "Turno Confirmado — Mercado Andrade", "Entregas de compras do mercado",
                    "Bela Vista, São Paulo", amanha.with(LocalTime.of(14, 0)), amanha.with(LocalTime.of(18, 0)),
                    "95.00", 1, ontem.plusHours(2));
            em(agora.minusHours(19), () -> turnos.aceitar(mariaCarlos.getId(), carlos.getId()));
            carimbarTurno(mariaCarlos, ontem.plusHours(2), agora.minusHours(19));

            // Em andamento: começou há pouco. A RF04 não deixaria publicá-lo
            // agora, e ele foi publicado com as 2h de antecedência — antes.
            LocalDateTime comecou = redondo(agora.minusHours(1));
            Turno andamento = publicar(claudia, "Turno Ativo — Hamburgueria da Cláudia", "Entregas em andamento",
                    "Água Verde, Curitiba", comecou, comecou.plusHours(4), "130.00", 1, comecou.minusHours(3));
            em(comecou.minusHours(2), () -> turnos.aceitar(andamento.getId(), ricardo.getId()));
            carimbarTurno(andamento, comecou.minusHours(3), comecou.minusHours(2));

            // Em cima da hora: publicado com 2h30 de antecedência, aceito pelo
            // Thiago — que cancela no fim desta história.
            LocalDateTime logo = agora.plusMinutes(30).truncatedTo(ChronoUnit.MINUTES);
            Turno tardio = publicar(claudia, "Turno Relâmpago — Hamburgueria da Cláudia", "Reforço para o pico do jantar",
                    "Água Verde, Curitiba", logo, logo.plusHours(4), "120.00", 1, logo.minusHours(2).minusMinutes(30));
            em(agora.minusMinutes(90), () -> turnos.aceitar(tardio.getId(), thiago.getId()));

            // Abertos, esperando entregador.
            LocalDateTime publicados = agora.minusMinutes(30);
            LocalDateTime em3h = redondo(agora.plusHours(3));
            LocalDateTime em5h = redondo(agora.plusHours(5));
            Turno a1 = publicar(claudia, "Turno Tarde — Hamburgueria da Cláudia", "Entregas na região do Água Verde",
                    "Água Verde, Curitiba", em3h, em3h.plusHours(4), "120.00", 1, publicados);
            Turno a2 = publicar(fernando, "Turno Tarde — Pizzaria do Fernando", "Entregas zona Batel e adjacências",
                    "Batel, Curitiba", em5h, em5h.plusHours(4), "100.00", 1, publicados.plusMinutes(1));
            Turno a3 = publicar(ana, "Turno Manhã — Farmácia Ana", "Entregas de medicamentos",
                    "Centro Cívico, Curitiba", depoisDeAmanha.with(LocalTime.of(8, 0)),
                    depoisDeAmanha.with(LocalTime.of(12, 0)), "110.00", 1, publicados.plusMinutes(2));
            Turno a4 = publicar(claudia, "Turno Noite — Hamburgueria da Cláudia", "Entregas noturnas",
                    "Água Verde, Curitiba", amanha.with(LocalTime.of(18, 0)), amanha.with(LocalTime.of(22, 0)),
                    "130.00", 1, publicados.plusMinutes(3));
            Turno a5 = publicar(fernando, "Turno Manhã — Pizzaria do Fernando", "Preparação e entregas",
                    "Batel, Curitiba", depoisDeAmanha.with(LocalTime.of(10, 0)),
                    depoisDeAmanha.with(LocalTime.of(14, 0)), "105.00", 1, publicados.plusMinutes(4));
            Turno a6 = publicar(maria, "Turno Manhã — Mercado Andrade", "Reposição e entregas da manhã",
                    "Bela Vista, São Paulo", depoisDeAmanha.with(LocalTime.of(9, 0)),
                    depoisDeAmanha.with(LocalTime.of(13, 0)), "95.00", 1, publicados.plusMinutes(5));
            for (Turno t : List.of(a1, a2, a3, a4, a5, a6)) {
                carimbarTurno(t, publicados, publicados);
            }
            carimbarTurno(tardio, logo.minusHours(2).minusMinutes(30), agora.minusMinutes(90));

            // Por último, e com a hora de agora: o cancelamento tardio. É o
            // TurnoService que tira 0,5 do score — ninguém grava 4,5 à mão.
            turnos.cancelar(tardio.getId(), thiago.getId());
        }

        // ── Turnos ───────────────────────────────────────────────────────

        /** O turno do passado: pelo repositório (a RF04 não deixa), reserva pelo serviço. */
        private Turno publicarNoPassado(Plano p) {
            return publicar(p.lojista(), p.titulo(), p.descricao(), p.regiao(), p.inicio(), p.fim(),
                    p.valor(), p.vagas(), p.publicacao());
        }

        private Turno publicar(Usuario lojista, String titulo, String descricao, String regiao,
                               LocalDateTime inicio, LocalDateTime fim, String valor, int vagas,
                               LocalDateTime quando) {
            BigDecimal custo = new BigDecimal(valor).multiply(BigDecimal.valueOf(vagas));
            garantirSaldo(lojista, custo, quando.minusMinutes(30));

            Turno t = new Turno();
            t.setLojistId(lojista.getId());
            t.setTitulo(titulo);
            t.setDescricao(descricao);
            t.setRegiao(regiao);
            t.setDataInicio(inicio);
            t.setDataFim(fim);
            t.setValorEstimado(new BigDecimal(valor));
            t.setRaioEntregaKm(regiao.contains("Paulo") ? 6.0 : 8.0);
            // Sem coordenada o turno não aparece no filtro por raio (SCRUM-18) e
            // o mapa da tela de detalhe fica vazio.
            double[] coord = coordenadaDaRegiao(regiao, titulo + inicio);
            t.setLatitude(coord[0]);
            t.setLongitude(coord[1]);
            t.setEndereco(regiao);
            t.setStatus(StatusTurno.ABERTO);
            t.setVagas(vagas);
            Turno salvo = turnoRepo.save(t);
            em(quando, () -> pagamentos.reservar(salvo));
            return salvo;
        }

        /**
         * Criação e última mudança do turno: {@code criadoEm} é quando a loja
         * publicou (o "turnos no mês" do painel conta por ele) e
         * {@code atualizadoEm} quando ele mudou de estado pela última vez (o
         * "concluídos no mês" do entregador e o "cancelamento tardio" do score
         * leem esse).
         */
        private void carimbarTurno(Turno t, LocalDateTime publicado, LocalDateTime atualizado) {
            em.flush();
            em.createNativeQuery("update turnos set criado_em = :p, atualizado_em = :a where id = :id")
                    .setParameter("p", publicado)
                    .setParameter("a", atualizado)
                    .setParameter("id", t.getId())
                    .executeUpdate();
        }

        // ── Dinheiro ─────────────────────────────────────────────────────

        /** Recarga pelo Pix simulado: cobrança criada e confirmada, como o app faz. */
        private void recarga(Usuario u, String valor, LocalDateTime quando) {
            em(quando, () -> {
                Long cobranca = cobrancas.criarRecarga(u.getId(), new BigDecimal(valor),
                        "massa-recarga-" + quando).getId();
                cobrancas.confirmarRecarga(u.getId(), cobranca);
            });
        }

        /** Saca 70% do disponível, em múltiplos de R$ 50 — sempre pelo gateway. */
        private void sacarParte(Usuario u, LocalDateTime quando) {
            BigDecimal disponivel = disponivel(u);
            BigDecimal valor = disponivel.multiply(new BigDecimal("0.70"))
                    .divide(new BigDecimal("50"), 0, RoundingMode.DOWN)
                    .multiply(new BigDecimal("50"));
            if (valor.compareTo(new BigDecimal("50")) < 0) return;
            em(quando, () -> cobrancas.sacar(u.getId(), valor, "massa-saque-" + quando));
        }

        /**
         * Lojista sem saldo para publicar recarrega antes — é o que a pessoa
         * faria, e o que a regra exige (RF04: sem lastro, não publica).
         */
        private void garantirSaldo(Usuario lojista, BigDecimal custo, LocalDateTime quando) {
            BigDecimal falta = custo.subtract(disponivel(lojista));
            if (falta.signum() <= 0) return;
            BigDecimal recarga = falta.divide(new BigDecimal("100"), 0, RoundingMode.UP)
                    .multiply(new BigDecimal("100")).max(new BigDecimal("300"));
            recarga(lojista, recarga.toPlainString(), quando);
        }

        /** Deixa pelo menos [alvo] disponível, para a demonstração ter folga. */
        private void reforcarSaldo(Usuario lojista, String alvo, LocalDateTime quando) {
            garantirSaldo(lojista, new BigDecimal(alvo), quando);
        }

        private BigDecimal disponivel(Usuario u) {
            em.flush();
            return carteiraRepo.findByUsuarioId(u.getId())
                    .map(c -> c.getSaldoDisponivel())
                    .orElse(BigDecimal.ZERO);
        }

        // ── Avaliações e notas ───────────────────────────────────────────

        /** O lojista avalia o entregador e o entregador avalia a loja. */
        private void avaliarOsDois(Turno t, Usuario lojista, Usuario entregador,
                                   LocalDateTime quando, int n) {
            Avaliacao doLojista = entregador == thiago
                    ? DO_LOJISTA_AO_THIAGO[n % DO_LOJISTA_AO_THIAGO.length]
                    : DO_LOJISTA[n % DO_LOJISTA.length];
            Avaliacao doEntregador = DO_ENTREGADOR[(n + lojista.getId().intValue()) % DO_ENTREGADOR.length];
            em(quando, () -> avaliar(t, lojista, entregador, doLojista.nota(), doLojista.comentario()));
            em(quando.plusMinutes(40), () -> avaliar(t, entregador, lojista,
                    doEntregador.nota(), doEntregador.comentario()));
        }

        private void avaliar(Turno t, Usuario avaliador, Usuario avaliado, int nota, String comentario) {
            AvaliacaoRequest req = new AvaliacaoRequest();
            req.setTurnoId(t.getId());
            req.setAvaliadoId(avaliado.getId());
            req.setNota(nota);
            req.setComentario(comentario);
            avaliacoes.avaliar(req, avaliador.getId());
        }

        private Long notaDe(Turno t, Usuario prestador) {
            return notasFiscais.listarDoUsuario(prestador.getId()).stream()
                    .filter(n -> t.getId().equals(n.getTurnoId()))
                    .map(NotaFiscalResponse::getId)
                    .findFirst()
                    .orElseThrow();
        }

        // ── O carimbo de data ────────────────────────────────────────────

        /**
         * Roda [acao] e dá a tudo o que ela gravou a data [quando]: os
         * lançamentos, as cobranças, as inscrições, as avaliações, as notas e
         * as notificações. Notificação com mais de três dias já foi lida;
         * as dos últimos dias continuam no sino.
         */
        private void em(LocalDateTime quando, Runnable acao) {
            long[] marco = marco();
            acao.run();
            em.flush();
            carimbarDesde("update transacoes set criado_em = :q where id > :m", quando, marco[0]);
            carimbarDesde("update cobrancas set criada_em = :q, concluida_em = :q "
                    + "where id > :m and concluida_em is not null", quando, marco[1]);
            carimbarDesde("update cobrancas set criada_em = :q where id > :m and concluida_em is null",
                    quando, marco[1]);
            carimbarDesde("update turno_inscricoes set criado_em = :q where id > :m", quando, marco[2]);
            carimbarDesde("update avaliacoes set criado_em = :q where id > :m", quando, marco[3]);
            carimbarDesde("update notas_fiscais set emitida_em = :q where id > :m", quando, marco[4]);
            if (quando.isBefore(agora.minusDays(3))) {
                carimbarDesde("update notificacoes set criado_em = :q, lida = true, lida_em = :q "
                        + "where id > :m", quando, marco[5]);
            } else {
                carimbarDesde("update notificacoes set criado_em = :q where id > :m", quando, marco[5]);
            }
        }

        /** O maior id de cada tabela que um passo pode gravar, numa consulta só. */
        private long[] marco() {
            em.flush();
            Object[] linha = (Object[]) em.createNativeQuery(
                            "select (select coalesce(max(id), 0) from transacoes),"
                          + " (select coalesce(max(id), 0) from cobrancas),"
                          + " (select coalesce(max(id), 0) from turno_inscricoes),"
                          + " (select coalesce(max(id), 0) from avaliacoes),"
                          + " (select coalesce(max(id), 0) from notas_fiscais),"
                          + " (select coalesce(max(id), 0) from notificacoes)")
                    .getSingleResult();
            long[] m = new long[linha.length];
            for (int i = 0; i < linha.length; i++) m[i] = ((Number) linha[i]).longValue();
            return m;
        }

        private void carimbarDesde(String sql, LocalDateTime quando, long marco) {
            em.createNativeQuery(sql)
                    .setParameter("q", quando)
                    .setParameter("m", marco)
                    .executeUpdate();
        }

        private void carimbar(String sql, LocalDateTime quando, Long id) {
            em.flush();
            em.createNativeQuery(sql)
                    .setParameter("q", quando)
                    .setParameter("id", id)
                    .executeUpdate();
        }

        private LocalDateTime redondo(LocalDateTime t) {
            return t.truncatedTo(ChronoUnit.HOURS);
        }
    }

    /** Um turno do passado, antes de acontecer. */
    private record Plano(Usuario lojista, String titulo, String descricao, String regiao,
                         LocalDateTime inicio, LocalDateTime fim, String valor, int vagas,
                         List<Usuario> entregadores, int semana) {

        /** Publicado na véspera, às 10h — sempre com mais de 2h de antecedência. */
        LocalDateTime publicacao() {
            return inicio.toLocalDate().minusDays(1).atTime(10, 0);
        }
    }

    /** Uma avaliação da massa: nota e comentário no formato do app (tags • tags — texto). */
    private record Avaliacao(int nota, String comentario) {}

    /** O lojista avaliando o entregador — tags de TagsDeAvaliacao.doEntregador. */
    private static final Avaliacao[] DO_LOJISTA = {
        new Avaliacao(5, "Pontual • Cuidado com a carga"),
        new Avaliacao(5, "Pontual • Educado — chegou antes do horário"),
        new Avaliacao(4, "Educado • Boa comunicação — saiu uns minutos atrasado"),
        new Avaliacao(5, "Conhece a região • Boa comunicação"),
        new Avaliacao(5, "Cuidado com a carga • Educado"),
        new Avaliacao(4, "Cuidado com a carga — o trânsito atrasou o fim do turno"),
        new Avaliacao(5, "Pontual • Conhece a região — entregas rápidas"),
    };

    /** O Thiago recebe notas um pouco menores: é o entregador que atrasa. */
    private static final Avaliacao[] DO_LOJISTA_AO_THIAGO = {
        new Avaliacao(3, "Atrasou 15 minutos para começar"),
        new Avaliacao(4, "Educado • Cuidado com a carga — mas chegou atrasado"),
        new Avaliacao(5, "Pontual • Educado"),
        new Avaliacao(4, "Boa comunicação — avisou do atraso com antecedência"),
    };

    /** O entregador avaliando a loja — tags de TagsDeAvaliacao.daLoja. */
    private static final Avaliacao[] DO_ENTREGADOR = {
        new Avaliacao(5, "Pedidos prontos no horário • Carga bem embalada"),
        new Avaliacao(5, "Endereços corretos • Boa comunicação"),
        new Avaliacao(4, "Boa comunicação — alguns pedidos demoraram na cozinha"),
        new Avaliacao(5, "Pedidos prontos no horário • Valor justo"),
        new Avaliacao(5, "Carga bem embalada • Endereços corretos"),
        new Avaliacao(3, "Pedidos atrasaram na cozinha e a rota ficou apertada"),
        new Avaliacao(4, "Valor justo • Carga bem embalada — um endereço veio incompleto"),
    };

    // ── Pessoas ──────────────────────────────────────────────────────────────

    private Usuario lojista(String nome, String email, String telefone, String cnpj,
                            LocalDate nascimento, String cidade, String uf,
                            String fantasia, String endereco) {
        Usuario u = conta(nome, email, telefone, "lojista", cnpj);
        u.setDataNascimento(nascimento);
        u.setCidade(cidade);
        u.setEstado(uf);
        u.setNomeFantasia(fantasia);
        u.setEnderecoComercial(endereco);
        return usuarioRepo.save(u);
    }

    private Usuario motoboy(String nome, String email, String telefone, String cnh, String categoria,
                            LocalDate validadeCnh, LocalDate nascimento, String cidade, String uf,
                            String modelo, String placa, int ano, String cor) {
        Usuario u = conta(nome, email, telefone, "motoboy", cnh);
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

    private Usuario conta(String nome, String email, String telefone, String tipo, String documento) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(email);
        // Hash sempre: o login só conhece BCrypt.
        u.setSenha(encoder.encode(SENHA));
        u.setTelefone(telefone);
        u.setTipo(tipo);
        u.setDocumentoFederal(documento);
        // Nem score nem média aqui: o score é o inicial da regra até um
        // cancelamento tardio mudá-lo, e a média nasce da primeira avaliação.
        return u;
    }

    /**
     * Coordenada aproximada do bairro, com um deslocamento determinístico
     * derivado do título para que turnos do mesmo bairro não caiam no mesmo
     * ponto exato.
     */
    private static double[] coordenadaDaRegiao(String regiao, String semente) {
        double lat, lng;
        String r = regiao == null ? "" : regiao.toLowerCase();
        if (r.contains("agua verde") || r.contains("água verde")) { lat = -25.4560; lng = -49.2820; }
        else if (r.contains("batel"))                             { lat = -25.4420; lng = -49.2900; }
        else if (r.contains("civico") || r.contains("cívico"))    { lat = -25.4160; lng = -49.2690; }
        else if (r.contains("bela vista") || r.contains("paulo")) { lat = -23.5614; lng = -46.6559; }
        else                                                      { lat = -25.4284; lng = -49.2733; }

        // Jitter de até ~600 m, estável entre execuções.
        int h = semente == null ? 0 : Math.abs(semente.hashCode() % 1_000_000);
        lat += ((h % 100) - 50) / 10000.0;
        lng += (((h / 100) % 100) - 50) / 10000.0;
        return new double[] { lat, lng };
    }
}
