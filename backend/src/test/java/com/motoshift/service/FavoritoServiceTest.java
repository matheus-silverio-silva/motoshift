package com.motoshift.service;

import com.motoshift.dto.FavoritoResponse;
import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.entity.Notificacao;
import com.motoshift.entity.Turno;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.FavoritoRepository;
import com.motoshift.repository.NotificacaoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.support.CenarioFinanceiro;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Favoritos (V18): só a loja favorita, só entregador é favorito, uma vez por
 * par — e o efeito: aviso na publicação e selo na lista de disponíveis.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
@Import(CenarioFinanceiro.class)
class FavoritoServiceTest {

    @Autowired private CenarioFinanceiro cenario;
    @Autowired private FavoritoService favoritos;
    @Autowired private FavoritoRepository repo;
    @Autowired private TurnoService turnos;
    @Autowired private UsuarioRepository usuarioRepo;
    @Autowired private NotificacaoRepository notificacaoRepo;

    private Usuario claudia;
    private Usuario fernando;
    private Usuario ricardo;
    private Usuario lucas;

    @BeforeEach
    void contas() {
        claudia = cenario.conta("lojista", "Cláudia Oliveira", "12.345.678/0001-90");
        claudia.setNomeFantasia("Hamburgueria da Cláudia");
        claudia = usuarioRepo.save(claudia);
        fernando = cenario.conta("lojista", "Fernando Lima", "98.765.432/0001-10");
        fernando.setNomeFantasia("Mercado do Fernando");
        fernando = usuarioRepo.save(fernando);
        ricardo = cenario.conta("motoboy", "Ricardo Souza", "12345678900");
        lucas = cenario.conta("motoboy", "Lucas Mendes", "98765432100");
    }

    @Nested
    @DisplayName("Papéis")
    class Papeis {

        @Test
        @DisplayName("o entregador não tem favoritos: 403 ao favoritar, desfavoritar e listar")
        void entregadorNaoFavorita() {
            for (Runnable chamada : List.<Runnable>of(
                    () -> favoritos.favoritar(ricardo.getId(), lucas.getId()),
                    () -> favoritos.desfavoritar(ricardo.getId(), lucas.getId()),
                    () -> favoritos.listar(ricardo.getId()))) {
                assertThatThrownBy(chamada::run)
                        .isInstanceOfSatisfying(ResponseStatusException.class,
                                e -> assertThat(e.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN));
            }
            assertThat(favoritosDasContas()).isZero();
        }

        @Test
        @DisplayName("loja não favorita loja: 422")
        void lojaNaoEFavorita() {
            assertThatThrownBy(() -> favoritos.favoritar(claudia.getId(), fernando.getId()))
                    .isInstanceOfSatisfying(ResponseStatusException.class,
                            e -> assertThat(e.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY));
        }

        @Test
        @DisplayName("entregador que não existe: 404")
        void entregadorInexistente() {
            assertThatThrownBy(() -> favoritos.favoritar(claudia.getId(), 999_999L))
                    .isInstanceOfSatisfying(ResponseStatusException.class,
                            e -> assertThat(e.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND));
        }

        @Test
        @DisplayName("cada loja vê só os seus favoritos")
        void cadaLojaASua() {
            favoritos.favoritar(claudia.getId(), ricardo.getId());
            favoritos.favoritar(fernando.getId(), lucas.getId());

            assertThat(favoritos.listar(claudia.getId())).extracting(FavoritoResponse::motoboyId)
                    .containsExactly(ricardo.getId());
            assertThat(favoritos.listar(fernando.getId())).extracting(FavoritoResponse::motoboyId)
                    .containsExactly(lucas.getId());
        }
    }

    @Nested
    @DisplayName("Duplicidade")
    class Duplicidade {

        @Test
        @DisplayName("favoritar duas vezes deixa uma linha e devolve o mesmo favorito")
        void duasVezes() {
            FavoritoResponse primeiro = favoritos.favoritar(claudia.getId(), ricardo.getId());
            FavoritoResponse segundo = favoritos.favoritar(claudia.getId(), ricardo.getId());

            assertThat(favoritosDasContas()).isEqualTo(1);
            assertThat(segundo.favoritadoEm()).isEqualTo(primeiro.favoritadoEm());
            assertThat(segundo.nome()).isEqualTo("Ricardo Souza");
        }

        @Test
        @DisplayName("desfavoritar tira da lista; desfavoritar de novo não é erro")
        void desfavoritar() {
            favoritos.favoritar(claudia.getId(), ricardo.getId());
            favoritos.desfavoritar(claudia.getId(), ricardo.getId());
            favoritos.desfavoritar(claudia.getId(), ricardo.getId());

            assertThat(favoritos.listar(claudia.getId())).isEmpty();
            assertThat(favoritosDasContas()).isZero();
        }

        @Test
        @DisplayName("lista do mais recente para o mais antigo, sem contato nem documento")
        void ordem() {
            favoritos.favoritar(claudia.getId(), ricardo.getId());
            var antigo = repo.findById(new com.motoshift.entity.Favorito.Chave(claudia.getId(), ricardo.getId()))
                    .orElseThrow();
            antigo.setCriadoEm(LocalDateTime.now().minusDays(3));
            repo.saveAndFlush(antigo);
            favoritos.favoritar(claudia.getId(), lucas.getId());

            assertThat(favoritos.listar(claudia.getId())).extracting(FavoritoResponse::nome)
                    .containsExactly("Lucas Mendes", "Ricardo Souza");
        }
    }

    @Nested
    @DisplayName("Publicar avisa os favoritos")
    class Aviso {

        @Test
        @DisplayName("o favorito recebe \"A Hamburgueria da Cláudia publicou um turno para ...\"; os outros, nada")
        void avisaSoOsFavoritos() {
            favoritos.favoritar(claudia.getId(), ricardo.getId());
            cenario.recarregar(claudia.getId(), "200.00");

            TurnoResponse t = turnos.criar(pedido(LocalDate.now().plusDays(1).atTime(18, 0)), claudia.getId());

            List<Notificacao> doRicardo = notificacoes(ricardo, FavoritoService.TIPO_NOTIFICACAO);
            assertThat(doRicardo).hasSize(1);
            assertThat(doRicardo.get(0).getMensagem())
                    .isEqualTo("A Hamburgueria da Cláudia publicou um turno para amanhã, 18h.");
            assertThat(doRicardo.get(0).getReferenciaTipo()).isEqualTo("turno");
            assertThat(doRicardo.get(0).getReferenciaId()).isEqualTo(t.getId());
            assertThat(notificacoes(lucas, FavoritoService.TIPO_NOTIFICACAO)).isEmpty();
        }

        @Test
        @DisplayName("publicação recusada por saldo não avisa ninguém")
        void semSaldoNaoAvisa() {
            favoritos.favoritar(claudia.getId(), ricardo.getId());
            assertThatThrownBy(() -> turnos.criar(pedido(LocalDate.now().plusDays(1).atTime(18, 0)),
                    claudia.getId())).isInstanceOf(ResponseStatusException.class);
            assertThat(notificacoes(ricardo, FavoritoService.TIPO_NOTIFICACAO)).isEmpty();
        }

        @Test
        @DisplayName("o artigo acompanha o nome: \"O Mercado do Fernando publicou\"")
        void artigo() {
            favoritos.favoritar(fernando.getId(), lucas.getId());
            cenario.recarregar(fernando.getId(), "200.00");
            turnos.criar(pedido(LocalDate.now().plusDays(1).atTime(9, 30)), fernando.getId());

            assertThat(notificacoes(lucas, FavoritoService.TIPO_NOTIFICACAO))
                    .extracting(Notificacao::getMensagem)
                    .containsExactly("O Mercado do Fernando publicou um turno para amanhã, 9h30.");
        }

        @Test
        @DisplayName("quando: hoje, amanhã, dia da semana até 6 dias, data depois disso")
        void quando() {
            LocalDate segunda = LocalDate.of(2026, 9, 28);
            assertThat(FavoritoService.quando(segunda.atTime(18, 0), segunda)).isEqualTo("hoje, 18h");
            assertThat(FavoritoService.quando(segunda.plusDays(1).atTime(18, 0), segunda)).isEqualTo("amanhã, 18h");
            assertThat(FavoritoService.quando(segunda.plusDays(4).atTime(11, 15), segunda)).isEqualTo("sexta, 11h15");
            assertThat(FavoritoService.quando(segunda.plusDays(6).atTime(8, 0), segunda)).isEqualTo("domingo, 8h");
            assertThat(FavoritoService.quando(segunda.plusDays(7).atTime(8, 0), segunda)).isEqualTo("05/10, 8h");
        }
    }

    @Test
    @DisplayName("selo: só os turnos das lojas que favoritaram este entregador")
    void selo() {
        favoritos.favoritar(claudia.getId(), ricardo.getId());
        TurnoResponse daClaudia = resposta(claudia);
        TurnoResponse doFernando = resposta(fernando);

        favoritos.marcarLojasQueTeChamaram(List.of(daClaudia, doFernando), ricardo.getId());
        assertThat(daClaudia.isLojaQueJaTeChamou()).isTrue();
        assertThat(doFernando.isLojaQueJaTeChamou()).isFalse();

        TurnoResponse paraOLucas = resposta(claudia);
        favoritos.marcarLojasQueTeChamaram(List.of(paraOLucas), lucas.getId());
        assertThat(paraOLucas.isLojaQueJaTeChamou()).isFalse();
    }

    /**
     * Os favoritos das contas deste teste — e não a tabela inteira: o banco do
     * contexto é compartilhado, e a massa de demonstração também tem os seus.
     */
    private long favoritosDasContas() {
        java.util.Set<Long> contas = java.util.Set.of(
                claudia.getId(), fernando.getId(), ricardo.getId(), lucas.getId());
        return repo.findAll().stream()
                .filter(f -> contas.contains(f.getLojistaId()) || contas.contains(f.getMotoboyId()))
                .count();
    }

    private TurnoRequest pedido(LocalDateTime inicio) {
        TurnoRequest req = new TurnoRequest();
        req.setTitulo("Turno Noite");
        req.setRegiao("Água Verde, Curitiba");
        req.setDataInicio(inicio);
        req.setDataFim(req.getDataInicio().plusHours(4));
        req.setValorEstimado(new BigDecimal("130.00"));
        req.setVagas(1);
        return req;
    }

    private static TurnoResponse resposta(Usuario loja) {
        Turno t = new Turno();
        t.setLojistId(loja.getId());
        t.setValorEstimado(new BigDecimal("100.00"));
        return TurnoResponse.from(t);
    }

    private List<Notificacao> notificacoes(Usuario u, String tipo) {
        return notificacaoRepo.findAll().stream()
                .filter(n -> n.getUsuarioId().equals(u.getId()) && tipo.equals(n.getTipo()))
                .toList();
    }
}
