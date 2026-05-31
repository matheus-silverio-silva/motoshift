package com.motoshift.config;

import com.motoshift.entity.Avaliacao;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.AvaliacaoRepository;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

@Component
public class DataInitializer implements CommandLineRunner {

    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;
    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;
    private final AvaliacaoRepository avaliacaoRepo;

    public DataInitializer(UsuarioRepository usuarioRepo,
                           TurnoRepository turnoRepo,
                           CarteiraRepository carteiraRepo,
                           TransacaoRepository transacaoRepo,
                           AvaliacaoRepository avaliacaoRepo) {
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
        this.avaliacaoRepo = avaliacaoRepo;
    }

    @Override
    public void run(String... args) {
        if (usuarioRepo.count() > 0) return;

        // ── Lojistas ──────────────────────────────────────────────────────────

        Usuario claudia = criarUsuario("Cláudia Oliveira", "claudia@teste.com",
                "senha123", "(41) 99111-2222", "lojista", "12.345.678/0001-90", 5.0, 4.8);
        preencherLojista(claudia, LocalDate.of(1985, 3, 12), "Curitiba", "PR",
                "Hamburgueria da Cláudia", "Av. Água Verde, 1200 — Água Verde, Curitiba/PR");

        Usuario fernando = criarUsuario("Fernando Costa", "fernando@teste.com",
                "senha123", "(41) 99333-4444", "lojista", "98.765.432/0001-10", 5.0, 4.5);
        preencherLojista(fernando, LocalDate.of(1978, 7, 22), "Curitiba", "PR",
                "Pizzaria do Fernando", "R. Comendador Araújo, 450 — Batel, Curitiba/PR");

        Usuario ana = criarUsuario("Ana Souza", "ana@teste.com",
                "senha123", "(41) 99555-6666", "lojista", "11.222.333/0001-44", 5.0, 4.9);
        preencherLojista(ana, LocalDate.of(1990, 11, 5), "Curitiba", "PR",
                "Farmácia Ana", "R. XV de Novembro, 980 — Centro Cívico, Curitiba/PR");

        // Lojistas originais de teste
        Usuario maria = criarUsuario("Maria Andrade", "lojista@teste.com",
                "senha123", "(11) 91234-5678", "lojista", "12.345.678/0001-99", 5.0, null);
        preencherLojista(maria, LocalDate.of(1982, 5, 18), "São Paulo", "SP",
                "Mercado Andrade", "Av. Paulista, 1500 — Bela Vista, São Paulo/SP");

        // ── Motoboys ─────────────────────────────────────────────────────────

        // Score adaptado para escala 0-5.0: 87→4.7, 95→4.9, 62→3.1
        Usuario ricardo = criarUsuario("Ricardo Souza", "ricardo@teste.com",
                "senha123", "(41) 98111-2222", "motoboy", "12345678900", 4.7, 4.8);
        preencherMotoboy(ricardo, LocalDate.of(1995, 2, 10), "Curitiba", "PR",
                "12345678900", "A", LocalDate.of(2028, 6, 30),
                "Honda CG 160 Titan", "ABC-1D23", 2022, "Vermelha");

        Usuario lucas = criarUsuario("Lucas Mendes", "lucas@teste.com",
                "senha123", "(41) 98333-4444", "motoboy", "98765432100", 4.9, 4.6);
        preencherMotoboy(lucas, LocalDate.of(1993, 9, 24), "Curitiba", "PR",
                "98765432100", "AB", LocalDate.of(2027, 11, 15),
                "Yamaha Factor 150", "DEF-2E34", 2023, "Preta");

        Usuario thiago = criarUsuario("Thiago Alves", "thiago@teste.com",
                "senha123", "(41) 98555-6666", "motoboy", "55566677788", 3.1, 3.2);
        preencherMotoboy(thiago, LocalDate.of(1998, 12, 3), "Curitiba", "PR",
                "55566677788", "A", LocalDate.of(2026, 4, 20),
                "Honda Biz 125", "GHI-3F45", 2020, "Branca");

        // Motoboy original de teste
        Usuario motoboyOriginal = criarUsuario("Carlos Mendes", "motoboy@teste.com",
                "senha123", "(11) 99876-5432", "motoboy", "AB123456", 5.0, null);
        preencherMotoboy(motoboyOriginal, LocalDate.of(1992, 8, 14), "São Paulo", "SP",
                "AB123456", "A", LocalDate.of(2029, 1, 10),
                "Honda PCX 150", "JKL-4G56", 2024, "Azul");

        // ── Carteiras ────────────────────────────────────────────────────────

        criarCarteira(ricardo.getId(), 320.00, 220.00, "ricardo@pix.com");
        criarCarteira(lucas.getId(), 150.00, 110.00, "lucas@pix.com");
        criarCarteira(thiago.getId(), 80.00, 120.00, null);
        criarCarteira(motoboyOriginal.getId(), 0.00, 0.00, null);

        // ── Datas auxiliares ─────────────────────────────────────────────────

        LocalDateTime agora = LocalDateTime.now();
        LocalDateTime hoje3h  = agora.plusHours(3).withMinute(0).withSecond(0).withNano(0);
        LocalDateTime hoje5h  = agora.plusHours(5).withMinute(0).withSecond(0).withNano(0);
        LocalDateTime hoje7h  = agora.plusHours(7).withMinute(0).withSecond(0).withNano(0);
        LocalDateTime hoje9h  = agora.plusHours(9).withMinute(0).withSecond(0).withNano(0);
        LocalDateTime hoje1h  = agora.plusHours(1).withMinute(0).withSecond(0).withNano(0);

        LocalDateTime amanha8  = agora.plusDays(1).with(LocalTime.of(8, 0));
        LocalDateTime amanha12 = agora.plusDays(1).with(LocalTime.of(12, 0));
        LocalDateTime amanha14 = agora.plusDays(1).with(LocalTime.of(14, 0));
        LocalDateTime amanha18 = agora.plusDays(1).with(LocalTime.of(18, 0));
        LocalDateTime amanha22 = agora.plusDays(1).with(LocalTime.of(22, 0));

        LocalDateTime depoisAmanha10 = agora.plusDays(2).with(LocalTime.of(10, 0));
        LocalDateTime depoisAmanha14 = agora.plusDays(2).with(LocalTime.of(14, 0));

        // ── Turnos ABERTOS ────────────────────────────────────────────────────

        criarTurno(claudia.getId(), null, "Turno Tarde — Hamburgueria da Cláudia",
                "Entregas na região do Água Verde", "Água Verde, Curitiba",
                hoje3h, hoje7h, 120.00, 8.0, "aberto");

        criarTurno(fernando.getId(), null, "Turno Tarde — Pizzaria do Fernando",
                "Entregas zona Batel e adjacências", "Batel, Curitiba",
                hoje5h, hoje9h, 100.00, 5.0, "aberto");

        criarTurno(ana.getId(), null, "Turno Manhã — Farmácia Ana",
                "Entregas de medicamentos", "Centro Cívico, Curitiba",
                amanha8, amanha12, 110.00, 6.0, "aberto");

        criarTurno(claudia.getId(), null, "Turno Noite — Hamburgueria da Cláudia",
                "Entregas noturnas", "Água Verde, Curitiba",
                amanha18, amanha22, 130.00, 10.0, "aberto");

        criarTurno(fernando.getId(), null, "Turno Manhã — Pizzaria do Fernando",
                "Preparação e entregas", "Batel, Curitiba",
                depoisAmanha10, depoisAmanha14, 105.00, 7.0, "aberto");

        // ── Turnos CONFIRMADOS (aceitos) ──────────────────────────────────────

        Turno t6 = criarTurno(claudia.getId(), ricardo.getId(),
                "Turno Ativo — Hamburgueria da Cláudia",
                "Entregas em andamento", "Água Verde, Curitiba",
                hoje1h, hoje5h, 120.00, 8.0, "aceito");

        Turno t7 = criarTurno(ana.getId(), lucas.getId(),
                "Turno Confirmado — Farmácia Ana",
                "Entregas de medicamentos tarde", "Centro Cívico, Curitiba",
                amanha14, amanha18, 110.00, 6.0, "aceito");

        // ── Turnos CONCLUÍDOS (histórico) ─────────────────────────────────────

        Turno t8 = criarTurnoHistorico(claudia.getId(), ricardo.getId(),
                "Turno Concluído — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(7), 4, 120.00, 8.0);

        Turno t9 = criarTurnoHistorico(fernando.getId(), ricardo.getId(),
                "Turno Concluído — Pizzaria do Fernando",
                "Batel, Curitiba", agora.minusDays(15), 4, 100.00, 5.0);

        Turno t10 = criarTurnoHistorico(ana.getId(), lucas.getId(),
                "Turno Concluído — Farmácia Ana",
                "Centro Cívico, Curitiba", agora.minusDays(3), 4, 110.00, 6.0);

        Turno t11 = criarTurnoHistorico(claudia.getId(), thiago.getId(),
                "Turno Concluído — Hamburgueria da Cláudia",
                "Água Verde, Curitiba", agora.minusDays(20), 4, 120.00, 8.0);

        Turno t12 = criarTurnoHistorico(fernando.getId(), lucas.getId(),
                "Turno Concluído — Pizzaria do Fernando",
                "Batel, Curitiba", agora.minusDays(10), 4, 100.00, 5.0);

        // ── Transações da wallet (Ricardo) ────────────────────────────────────

        criarTransacao(ricardo.getId(), t8.getId(), "turno",  120.00,
                "Turno concluído - Hamburgueria da Cláudia", "processado");
        criarTransacao(ricardo.getId(), t9.getId(), "turno",  100.00,
                "Turno concluído - Pizzaria do Fernando", "processado");
        criarTransacao(ricardo.getId(), null,       "saque",  200.00,
                "Transferência Pix — ricardo@pix.com", "concluido");
        criarTransacao(ricardo.getId(), null,       "turno",  300.00,
                "Créditos de turnos anteriores", "processado");

        // Transações dos demais motoboys
        criarTransacao(lucas.getId(), t10.getId(), "turno", 110.00,
                "Turno concluído - Farmácia Ana", "processado");
        criarTransacao(lucas.getId(), t12.getId(), "turno", 100.00,
                "Turno concluído - Pizzaria do Fernando", "processado");
        criarTransacao(thiago.getId(), t11.getId(), "turno", 120.00,
                "Turno concluído - Hamburgueria da Cláudia", "processado");

        // ── Avaliações ────────────────────────────────────────────────────────

        criarAvaliacao(t8.getId(), ricardo.getId(), claudia.getId(), 5, "Ótima organização");
        criarAvaliacao(t8.getId(), claudia.getId(), ricardo.getId(), 5, "Pontual e educado");
        criarAvaliacao(t10.getId(), lucas.getId(),  ana.getId(),     4, "Boa comunicação");
        criarAvaliacao(t10.getId(), ana.getId(),    lucas.getId(),   5, "Excelente profissional");
        criarAvaliacao(t11.getId(), thiago.getId(), claudia.getId(), 3, "Poderia ser mais claro");
        criarAvaliacao(t11.getId(), claudia.getId(), thiago.getId(), 3, "Atrasou 15 minutos");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private Usuario criarUsuario(String nome, String email, String senha,
                                  String telefone, String tipo, String doc,
                                  double score, Double mediaAvaliacao) {
        Usuario u = new Usuario();
        u.setNome(nome);
        u.setEmail(email);
        u.setSenha(senha);
        u.setTelefone(telefone);
        u.setTipo(tipo);
        u.setDocumentoFederal(doc);
        u.setScore(score);
        u.setMediaAvaliacao(mediaAvaliacao);
        return usuarioRepo.save(u);
    }

    private void preencherLojista(Usuario u, LocalDate nascimento, String cidade,
                                   String estado, String fantasia, String endereco) {
        u.setDataNascimento(nascimento);
        u.setCidade(cidade);
        u.setEstado(estado);
        u.setNomeFantasia(fantasia);
        u.setEnderecoComercial(endereco);
        usuarioRepo.save(u);
    }

    private void preencherMotoboy(Usuario u, LocalDate nascimento, String cidade,
                                   String estado, String cnhNum, String cnhCat,
                                   LocalDate cnhVal, String modelo, String placa,
                                   int ano, String cor) {
        u.setDataNascimento(nascimento);
        u.setCidade(cidade);
        u.setEstado(estado);
        u.setCnhNumero(cnhNum);
        u.setCnhCategoria(cnhCat);
        u.setCnhValidade(cnhVal);
        u.setVeiculoModelo(modelo);
        u.setVeiculoPlaca(placa);
        u.setVeiculoAno(ano);
        u.setVeiculoCor(cor);
        usuarioRepo.save(u);
    }

    private void criarCarteira(Long motoboyId, double saldo, double ganhos, String pix) {
        Carteira c = new Carteira();
        c.setMotoboyId(motoboyId);
        c.setSaldoAtual(saldo);
        c.setGanhosMensais(ganhos);
        c.setChavePix(pix);
        carteiraRepo.save(c);
    }

    private Turno criarTurno(Long lojistId, Long motoboyId, String titulo,
                              String descricao, String regiao,
                              LocalDateTime inicio, LocalDateTime fim,
                              double valor, double raio, String status) {
        Turno t = new Turno();
        t.setLojistId(lojistId);
        t.setMotoboyId(motoboyId);
        t.setTitulo(titulo);
        t.setDescricao(descricao);
        t.setRegiao(regiao);
        t.setDataInicio(inicio);
        t.setDataFim(fim);
        t.setValorEstimado(valor);
        t.setRaioEntregaKm(raio);
        t.setStatus(status);
        return turnoRepo.save(t);
    }

    private Turno criarTurnoHistorico(Long lojistId, Long motoboyId, String titulo,
                                       String regiao, LocalDateTime inicio,
                                       int duracaoHoras, double valor, double raio) {
        return criarTurno(lojistId, motoboyId, titulo,
                "Turno concluído", regiao,
                inicio, inicio.plusHours(duracaoHoras),
                valor, raio, "finalizado");
    }

    private void criarTransacao(Long motoboyId, Long turnoId, String tipo,
                                 double valor, String descricao, String status) {
        Transacao tx = new Transacao();
        tx.setMotoboyId(motoboyId);
        tx.setTurnoId(turnoId);
        tx.setTipo(tipo);
        tx.setValor(valor);
        tx.setDescricao(descricao);
        tx.setStatus(status);
        transacaoRepo.save(tx);
    }

    private void criarAvaliacao(Long turnoId, Long avaliadorId, Long avaliadoId,
                                 int nota, String comentario) {
        Avaliacao a = new Avaliacao();
        a.setTurnoId(turnoId);
        a.setAvaliadorId(avaliadorId);
        a.setAvaliadoId(avaliadoId);
        a.setNota(nota);
        a.setComentario(comentario);
        avaliacaoRepo.save(a);
    }
}
