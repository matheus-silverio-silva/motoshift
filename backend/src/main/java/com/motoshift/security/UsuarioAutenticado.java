package com.motoshift.security;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/**
 * Quem está fazendo a requisição, lido do JWT — nunca do corpo dela.
 *
 * Antes desta classe a autorização vinha do JSON: {@code {"motoboyId": 7}}.
 * Quem escolhia o número escolhia de quem era o turno, o saldo e o saque.
 * Agora o id sai do token assinado e o corpo passa a ser só dado.
 *
 * Os métodos {@code exigir*} existem para que o controller diga a regra em uma
 * linha legível e o 403 saia sempre com a mesma mensagem.
 */
public record UsuarioAutenticado(Long id, String email, String tipo) {

    public boolean isLojista() {
        return "lojista".equals(tipo);
    }

    public boolean isMotoboy() {
        return "motoboy".equals(tipo);
    }

    /** Só o dono do recurso passa. Usado onde a rota carrega um id no caminho. */
    public void exigirMesmoUsuario(Long usuarioId) {
        if (usuarioId == null || !usuarioId.equals(id)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: você só pode acessar os seus próprios dados.");
        }
    }

    /** Rotas exclusivas de um perfil (ex.: publicar turno é do lojista). */
    public void exigirTipo(String tipoEsperado) {
        if (!tipoEsperado.equals(tipo)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Acesso negado: endpoint exclusivo para perfil " + tipoEsperado + ".");
        }
    }
}
