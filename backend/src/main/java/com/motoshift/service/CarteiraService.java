package com.motoshift.service;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.NaturezaTransacao;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.GanhoMensal;
import com.motoshift.repository.TransacaoRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class CarteiraService {

    /**
     * O que conta como ganho: pagamento de turno ja liquidado.
     *
     * Eram duas listas de compatibilidade — tipos ("turno" legado e
     * "pagamento_recebido") e status ("processado" legado e "concluido"). A V10
     * unificou os valores no banco e o corte virou um tipo e um status. O que
     * continua importando e o que fica de fora: o pagamento nasce PENDENTE na
     * finalizacao do turno, muito antes de ser pago, e somar pendente mostraria
     * ao entregador R$ 120 de "ganhos do mes" com o saldo em R$ 0.
     */
    public static final TipoTransacao TIPO_GANHO = TipoTransacao.PAGAMENTO_RECEBIDO;
    public static final StatusTransacao STATUS_LIQUIDADO = StatusTransacao.CONCLUIDO;

    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;

    /**
     * Injecao tardia para quebrar o ciclo CarteiraService -> CobrancaService ->
     * CarteiraService. O {@code @Lazy} coloca um proxy no lugar e o bean real
     * so e resolvido na primeira chamada — que acontece bem depois do boot.
     *
     * <p>O ciclo existe porque {@link #saque} e um invólucro de compatibilidade:
     * quando o app migrar para POST /api/carteira/saques ele sai, e a
     * dependencia sai junto.
     */
    private final CobrancaService cobrancas;

    public CarteiraService(CarteiraRepository carteiraRepo,
                           TransacaoRepository transacaoRepo,
                           @org.springframework.context.annotation.Lazy CobrancaService cobrancas) {
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
        this.cobrancas = cobrancas;
    }

    /** Carteira do usuario, criada na hora se ainda nao existir. */
    @Transactional
    public Carteira obterOuCriar(Long usuarioId) {
        return carteiraRepo.findByUsuarioId(usuarioId)
                .orElseGet(() -> {
                    Carteira c = new Carteira();
                    c.setUsuarioId(usuarioId);
                    return carteiraRepo.save(c);
                });
    }

    @Transactional
    public CarteiraResponse buscar(Long usuarioId) {
        Carteira carteira = obterOuCriar(usuarioId);

        CarteiraResponse resp = CarteiraResponse.from(carteira);
        resp.setGanhosMensais(ganhosDoMes(usuarioId));

        // Só a primeira página, e não o extrato inteiro.
        //
        // Esta rota devolvia TODOS os lançamentos do usuário num array só. Com
        // vinte linhas passava despercebido; com dois anos de uso é uma
        // resposta enorme para uma tela que mostra as primeiras dez. Quem
        // precisa do resto usa GET /api/carteira/extrato, que pagina e filtra.
        List<TransacaoResponse> transacoes = transacaoRepo
                .findByUsuarioIdOrderByCriadoEmDesc(usuarioId,
                        PageRequest.of(0, PRIMEIRA_PAGINA_DO_EXTRATO))
                .map(TransacaoResponse::from)
                .getContent();
        resp.setTransacoes(transacoes);
        return resp;
    }

    /**
     * Quantos lançamentos a rota de compatibilidade devolve.
     *
     * Suficiente para a tela de carteira do app atual, que lista os últimos
     * lançamentos e não tem paginação própria.
     */
    private static final int PRIMEIRA_PAGINA_DO_EXTRATO = 20;

    /** Extrato paginado, do lancamento mais recente para o mais antigo. */
    public Page<TransacaoResponse> extrato(Long usuarioId, Pageable pagina) {
        return transacaoRepo.findByUsuarioIdOrderByCriadoEmDesc(usuarioId, pagina)
                .map(TransacaoResponse::from);
    }

    /**
     * Ganhos do mes corrente, somados das transacoes.
     *
     * Substitui o antigo campo Carteira.ganhosMensais, que so incrementava e
     * nunca era resetado — ou seja, mostrava o acumulado de sempre rotulado
     * como "do mes".
     */
    public BigDecimal ganhosDoMes(Long usuarioId) {
        LocalDateTime inicioMes = LocalDate.now().withDayOfMonth(1).atStartOfDay();
        BigDecimal total = transacaoRepo.somarPorTipoDesde(
                usuarioId, TIPO_GANHO, STATUS_LIQUIDADO, inicioMes);
        return (total == null ? BigDecimal.ZERO : total).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * Saque via Pix, no formato da resposta antiga.
     *
     * @deprecated O saque de verdade e {@link CobrancaService#sacar} — ele fala
     *     com o gateway, trata a recusa e devolve a cobranca com o estado da
     *     operacao. Este metodo existe so para manter o corpo que o app em
     *     producao espera ({@code mensagem} + {@code novoSaldo}) enquanto ele
     *     nao migra para POST /api/carteira/saques. Sai junto com a rota
     *     {@code /{usuarioId}/saque}.
     */
    @Deprecated
    @Transactional
    public Map<String, Object> saque(Long usuarioId, BigDecimal valor, String chaveDoCliente) {
        cobrancas.sacar(usuarioId, valor, chaveDoCliente);

        Carteira carteira = obterOuCriar(usuarioId);
        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("mensagem", "Saque realizado com sucesso!");
        resp.put("novoSaldo", carteira.getSaldoDisponivel().setScale(2, RoundingMode.HALF_UP));
        return resp;
    }

    @Transactional
    public void atualizarPix(Long usuarioId, String chavePix) {
        Carteira carteira = obterOuCriar(usuarioId);
        carteira.setChavePix(chavePix);
        carteiraRepo.save(carteira);
    }

    /**
     * Ganhos por mes, para o grafico da carteira.
     *
     * A soma sai agrupada do banco; aqui so se monta a serie com um item por
     * mes pedido, inclusive os meses sem lancamento.
     */
    public List<Map<String, Object>> grafico(Long usuarioId, int meses) {
        LocalDate hoje = LocalDate.now();
        LocalDateTime desde = hoje.minusMonths(Math.max(meses, 1) - 1L)
                .withDayOfMonth(1).atStartOfDay();

        Map<String, BigDecimal> porMes = new HashMap<>();
        for (GanhoMensal g : transacaoRepo.somarPorMesDesde(
                usuarioId, TIPO_GANHO, STATUS_LIQUIDADO, desde)) {
            porMes.put(rotulo(g.mes(), g.ano()), g.total());
        }

        List<Map<String, Object>> result = new ArrayList<>();
        for (int i = meses - 1; i >= 0; i--) {
            LocalDate mesRef = hoje.minusMonths(i);
            String rotulo = rotulo(mesRef.getMonthValue(), mesRef.getYear());
            BigDecimal total = porMes.getOrDefault(rotulo, BigDecimal.ZERO);

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("mes", rotulo);
            item.put("ganhos", total.setScale(2, RoundingMode.HALF_UP));
            result.add(item);
        }

        return result;
    }

    private static String rotulo(int mes, int ano) {
        return String.format("%02d/%d", mes, ano);
    }
}
