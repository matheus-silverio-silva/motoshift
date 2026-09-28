package com.motoshift.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.mockito.Mockito.*;

/**
 * A trava do reset: dois valores exatos abrem, qualquer outra coisa não faz
 * nada.
 *
 * É a única coisa entre um deploy comum e apagar dados do banco de produção,
 * então cada quase-acerto plausível está listado — dos dois modos.
 */
class ResetDaMassaNoBootTest {

    @ParameterizedTest(name = "trava = [{0}] não reseta")
    @NullAndEmptySource
    @ValueSource(strings = {
            "sim", "true", "1", "CONFIRMO", "Confirmo", " confirmo", "confirmo ", "confirma",
            // Quase-acertos do modo total: nenhum deles pode cair em nenhum dos modos.
            "CONFIRMO-APAGAR-TUDO", " confirmo-apagar-tudo", "confirmo-apagar-tudo ",
            "confirmo-apagar", "apagar-tudo", "confirmo apagar tudo", "confirmo_apagar_tudo",
            "confirmo-apagar-todo"})
    @DisplayName("sem um dos dois valores exatos, nada roda")
    void semTrava_naoFazNada(String trava) {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);

        new ResetDaMassaNoBoot(massa, trava).run(null);

        verifyNoInteractions(massa);
    }

    @Test
    @DisplayName("com MOTOSHIFT_SEED_RESET=confirmo, reseta só a massa, uma vez")
    void comTrava_reseta() {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);

        new ResetDaMassaNoBoot(massa, "confirmo").run(null);

        verify(massa, times(1)).resetar();
        verifyNoMoreInteractions(massa);
    }

    @Test
    @DisplayName("com MOTOSHIFT_SEED_RESET=confirmo-apagar-tudo, apaga tudo e recria, uma vez")
    void comTravaTotal_apagaTudo() {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);

        new ResetDaMassaNoBoot(massa, "confirmo-apagar-tudo").run(null);

        verify(massa, times(1)).apagarTudoERecriar();
        verifyNoMoreInteractions(massa);
    }

    @Test
    @DisplayName("reset que falha não derruba o boot")
    void falhaNaoDerrubaOBoot() {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);
        doThrow(new IllegalStateException("nota fiscal recusada")).when(massa).resetar();

        // Sem excecao aqui: o app sobe e o log explica. O reset e uma transacao
        // so, entao falhar significa que nada foi apagado.
        new ResetDaMassaNoBoot(massa, "confirmo").run(null);

        verify(massa).resetar();
    }

    @Test
    @DisplayName("reset total que falha também não derruba o boot")
    void falhaDoTotalNaoDerrubaOBoot() {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);
        doThrow(new IllegalStateException("nota fiscal recusada")).when(massa).apagarTudoERecriar();

        new ResetDaMassaNoBoot(massa, "confirmo-apagar-tudo").run(null);

        verify(massa).apagarTudoERecriar();
    }
}
