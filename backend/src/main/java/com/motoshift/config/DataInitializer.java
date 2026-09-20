package com.motoshift.config;

import com.motoshift.repository.UsuarioRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Gatilho da massa de demonstração no desenvolvimento: banco vazio, massa nova.
 *
 * A massa em si mora em {@link MassaDemonstracao}, que também serve à
 * produção pelo reset com trava ({@link ResetDaMassaNoBoot}). Aqui fica só a
 * decisão de dev, e o {@code @Profile("!prod")} continua sendo o ponto: em
 * produção esta classe nem é instanciada, e o boot não cria nada sozinho.
 */
@Component
@Profile("!prod")
public class DataInitializer implements CommandLineRunner {

    private final UsuarioRepository usuarioRepo;
    private final MassaDemonstracao massa;

    public DataInitializer(UsuarioRepository usuarioRepo, MassaDemonstracao massa) {
        this.usuarioRepo = usuarioRepo;
        this.massa = massa;
    }

    @Override
    public void run(String... args) {
        if (usuarioRepo.count() > 0) return;
        massa.popular();
    }
}
