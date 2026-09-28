package com.motoshift.dto;

import com.motoshift.entity.Favorito;
import com.motoshift.entity.Usuario;
import com.motoshift.service.Reputacao;

import java.time.LocalDateTime;

/**
 * Um entregador da lista "Meus entregadores favoritos". Só o que o perfil
 * público já mostra — nome, nota e reputação —, nunca contato ou documento.
 */
public record FavoritoResponse(
        Long motoboyId,
        String nome,
        String fotoPerfil,
        Double mediaAvaliacao,
        Double score,
        LocalDateTime favoritadoEm) {

    public static FavoritoResponse de(Favorito f, Usuario entregador, Reputacao reputacao) {
        return new FavoritoResponse(
                f.getMotoboyId(),
                entregador.getNome(),
                entregador.getFotoPerfil(),
                entregador.getMediaAvaliacao(),
                reputacao.scoreVisivel(entregador),
                f.getCriadoEm());
    }
}
