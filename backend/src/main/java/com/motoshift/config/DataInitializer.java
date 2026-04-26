package com.motoshift.config;

import com.motoshift.entity.Carteira;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TurnoRepository;
import com.motoshift.repository.UsuarioRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

// Popula o banco H2 em memória com dados de teste na inicialização.
// Senhas em texto simples (alinhado com AuthService.login que usa equals()).
// Em produção, substituir por BCrypt + Spring Security.
@Component
public class DataInitializer implements CommandLineRunner {

    private final UsuarioRepository usuarioRepo;
    private final TurnoRepository turnoRepo;
    private final CarteiraRepository carteiraRepo;

    public DataInitializer(UsuarioRepository usuarioRepo,
                           TurnoRepository turnoRepo,
                           CarteiraRepository carteiraRepo) {
        this.usuarioRepo = usuarioRepo;
        this.turnoRepo = turnoRepo;
        this.carteiraRepo = carteiraRepo;
    }

    @Override
    public void run(String... args) {
        if (usuarioRepo.count() > 0) return;

        // ── Lojista de teste ──────────────────────────────────────────────────
        Usuario lojista = new Usuario();
        lojista.setNome("Maria Andrade");
        lojista.setEmail("lojista@teste.com");
        lojista.setSenha("senha123");
        lojista.setTelefone("(11) 91234-5678");
        lojista.setTipo("lojista");
        lojista.setDocumentoFederal("12.345.678/0001-99"); // CNPJ
        lojista = usuarioRepo.save(lojista);

        // ── Motoboy de teste ─────────────────────────────────────────────────
        Usuario motoboy = new Usuario();
        motoboy.setNome("Carlos Mendes");
        motoboy.setEmail("motoboy@teste.com");
        motoboy.setSenha("senha123");
        motoboy.setTelefone("(11) 99876-5432");
        motoboy.setTipo("motoboy");
        motoboy.setDocumentoFederal("AB123456");          // CNH
        motoboy = usuarioRepo.save(motoboy);

        // ── Carteira inicial do motoboy (saldo zero) ─────────────────────────
        Carteira carteira = new Carteira();
        carteira.setMotoboyId(motoboy.getId());
        carteira.setSaldoAtual(0.0);
        carteira.setGanhosMensais(0.0);
        carteiraRepo.save(carteira);

        // ── Turnos disponíveis (datas futuras para respeitar regra de 2h) ────
        LocalDateTime amanha9h = LocalDateTime.now()
                .plusDays(1).withHour(9).withMinute(0).withSecond(0).withNano(0);

        LocalDateTime depoisDeAmanha14h = LocalDateTime.now()
                .plusDays(2).withHour(14).withMinute(0).withSecond(0).withNano(0);

        Turno turno1 = new Turno();
        turno1.setLojistId(lojista.getId());
        turno1.setTitulo("Turno Manha - " + amanha9h.toLocalDate());
        turno1.setDescricao("Entregas na regiao central");
        turno1.setRegiao("Centro - Sao Paulo");
        turno1.setDataInicio(amanha9h);
        turno1.setDataFim(amanha9h.plusHours(4));
        turno1.setValorEstimado(120.0);
        turno1.setRaioEntregaKm(8.0);
        turnoRepo.save(turno1);

        Turno turno2 = new Turno();
        turno2.setLojistId(lojista.getId());
        turno2.setTitulo("Turno Tarde - " + depoisDeAmanha14h.toLocalDate());
        turno2.setDescricao("Entregas zona sul");
        turno2.setRegiao("Vila Mariana - Sao Paulo");
        turno2.setDataInicio(depoisDeAmanha14h);
        turno2.setDataFim(depoisDeAmanha14h.plusHours(5));
        turno2.setValorEstimado(180.0);
        turno2.setRaioEntregaKm(15.0);
        turnoRepo.save(turno2);
    }
}
