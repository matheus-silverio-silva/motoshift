package com.motoshift.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.mockito.Mockito.*;

/**
 * A trava do reset: um valor exato abre, qualquer outra coisa não faz nada.
 *
 * É a única coisa entre um deploy comum e apagar a massa do banco de produção,
 * então cada quase-acerto plausível está listado.
 */
class ResetDaMassaNoBootTest {

    @ParameterizedTest(name = "trava = [{0}] não reseta")
    @NullAndEmptySource
    @ValueSource(strings = {"sim", "true", "1", "CONFIRMO", "Confirmo", " confirmo", "confirmo ", "confirma"})
    @DisplayName("sem o valor exato, o reset não roda")
    void semTrava_naoFazNada(String trava) {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);

        new ResetDaMassaNoBoot(massa, trava).run(null);

        verifyNoInteractions(massa);
    }

    @Test
    @DisplayName("com MOTOSHIFT_SEED_RESET=confirmo, reseta uma vez")
    void comTrava_reseta() {
        MassaDemonstracao massa = mock(MassaDemonstracao.class);

        new ResetDaMassaNoBoot(massa, "confirmo").run(null);

        verify(massa, times(1)).resetar();
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
}
