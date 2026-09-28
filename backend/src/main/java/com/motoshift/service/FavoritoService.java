package com.motoshift.service;

import com.motoshift.dto.FavoritoResponse;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Favorito;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.FavoritoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.util.Artigo;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Os entregadores favoritos de cada loja (V18).
 *
 * <p><b>Papéis.</b> Só o lojista favorita, e só entregador é favoritado. A
 * lista é da loja: o entregador não vê quem o favoritou — vê só o selo "Loja
 * que já te chamou" nos turnos daquela loja, que é o efeito do favorito.
 *
 * <p><b>Duplicidade.</b> Favoritar de novo não cria linha nem erro: devolve o
 * favorito que existe. Quem garante é a chave primária (lojista, entregador);
 * a corrida de dois cliques que escapa do {@code exists} bate nela e é lida
 * como "já era favorito" (o controller repete a chamada). Desfavoritar o
 * que não é favorito também é no-op.
 *
 * <p><b>O efeito.</b> Quando a loja publica um turno, cada favorito recebe
 * "A Hamburgueria da Cláudia publicou um turno para amanhã, 18h".
 */
@Service
public class FavoritoService {

    static final String TIPO_NOTIFICACAO = "turno_de_favorito";

    private static final String[] DIAS = {
            "segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"};

    private final FavoritoRepository repo;
    private final UsuarioRepository usuarioRepo;
    private final NotificacaoService notificacoes;
    private final Reputacao reputacao;

    public FavoritoService(FavoritoRepository repo,
                           UsuarioRepository usuarioRepo,
                           NotificacaoService notificacoes,
                           Reputacao reputacao) {
        this.repo = repo;
        this.usuarioRepo = usuarioRepo;
        this.notificacoes = notificacoes;
        this.reputacao = reputacao;
    }

    @Transactional
    public FavoritoResponse favoritar(Long lojistaId, Long motoboyId) {
        exigirLojista(lojistaId);
        Usuario entregador = entregador(motoboyId);

        Favorito existente = repo.findById(new Favorito.Chave(lojistaId, motoboyId)).orElse(null);
        if (existente != null) return FavoritoResponse.de(existente, entregador, reputacao);
        // Na corrida de dois cliques, o segundo bate na chave primária com
        // DataIntegrityViolationException. A transação morre com ela; quem
        // repete é o controller, e a segunda chamada cai no "já existe" acima.
        Favorito novo = repo.saveAndFlush(new Favorito(lojistaId, motoboyId));
        return FavoritoResponse.de(novo, entregador, reputacao);
    }

    @Transactional
    public void desfavoritar(Long lojistaId, Long motoboyId) {
        exigirLojista(lojistaId);
        Favorito.Chave chave = new Favorito.Chave(lojistaId, motoboyId);
        if (repo.existsById(chave)) repo.deleteById(chave);
    }

    @Transactional(readOnly = true)
    public List<FavoritoResponse> listar(Long lojistaId) {
        exigirLojista(lojistaId);
        List<Favorito> favoritos = repo.findByLojistaIdOrderByCriadoEmDesc(lojistaId);
        Map<Long, Usuario> entregadores = usuarioRepo
                .findAllById(favoritos.stream().map(Favorito::getMotoboyId).toList()).stream()
                .collect(Collectors.toMap(Usuario::getId, Function.identity()));
        return favoritos.stream()
                .filter(f -> entregadores.containsKey(f.getMotoboyId()))
                .map(f -> FavoritoResponse.de(f, entregadores.get(f.getMotoboyId()), reputacao))
                .toList();
    }

    /**
     * Marca, nos turnos da lista de disponíveis, os das lojas que favoritaram
     * este entregador. Uma consulta só, qualquer que seja o tamanho da lista.
     */
    @Transactional(readOnly = true)
    public void marcarLojasQueTeChamaram(Collection<TurnoResponse> turnos, Long motoboyId) {
        if (turnos == null || turnos.isEmpty() || motoboyId == null) return;
        Set<Long> lojas = repo.lojasQueFavoritaram(motoboyId);
        if (lojas.isEmpty()) return;
        for (TurnoResponse t : turnos) {
            if (lojas.contains(t.getLojistId())) t.setLojaQueJaTeChamou(true);
        }
    }

    /**
     * Avisa os favoritos da loja de que ela publicou um turno. Roda na
     * transação da publicação: turno que não chegou a existir não avisa
     * ninguém.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public int avisarFavoritos(Turno turno, LocalDate hoje) {
        List<Favorito> favoritos = repo.findByLojistaId(turno.getLojistId());
        if (favoritos.isEmpty()) return 0;
        String loja = usuarioRepo.findById(turno.getLojistId())
                .map(FavoritoService::nomeDaLoja).orElse("Uma loja");
        String texto = capitalizar(Artigo.definido(loja)) + " " + loja
                + " publicou um turno para " + quando(turno.getDataInicio(), hoje) + ".";
        for (Favorito f : favoritos) {
            notificacoes.criar(f.getMotoboyId(), TIPO_NOTIFICACAO,
                    "Turno novo de quem já te chamou", texto, "turno", turno.getId());
        }
        return favoritos.size();
    }

    /** "hoje, 18h", "amanhã, 18h30", "sexta, 9h", "12/10, 18h". */
    static String quando(LocalDateTime inicio, LocalDate hoje) {
        String hora = inicio.getMinute() == 0
                ? inicio.getHour() + "h"
                : inicio.getHour() + "h" + String.format("%02d", inicio.getMinute());
        LocalDate dia = inicio.toLocalDate();
        long dias = java.time.temporal.ChronoUnit.DAYS.between(hoje, dia);
        String quando;
        if (dias == 0) quando = "hoje";
        else if (dias == 1) quando = "amanhã";
        else if (dias > 1 && dias < 7) quando = DIAS[dia.getDayOfWeek().getValue() - DayOfWeek.MONDAY.getValue()];
        else quando = String.format("%02d/%02d", dia.getDayOfMonth(), dia.getMonthValue());
        return quando + ", " + hora;
    }

    static String nomeDaLoja(Usuario u) {
        return u.getNomeFantasia() != null && !u.getNomeFantasia().isBlank()
                ? u.getNomeFantasia() : u.getNome();
    }

    private static String capitalizar(String s) {
        return s.isEmpty() ? s : Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    private void exigirLojista(Long lojistaId) {
        Usuario u = usuarioRepo.findById(lojistaId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.NOT_FOUND, "Conta não encontrada."));
        if (!"lojista".equals(u.getTipo())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Só a loja tem entregadores favoritos.");
        }
    }

    private Usuario entregador(Long motoboyId) {
        Usuario u = usuarioRepo.findById(motoboyId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.NOT_FOUND, "Entregador não encontrado."));
        if (!"motoboy".equals(u.getTipo())) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Só entregador pode ser favorito.");
        }
        return u;
    }
}
