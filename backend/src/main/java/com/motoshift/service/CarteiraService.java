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

    /** Valor minimo de saque (RF: R$ 20,00). */
    private static final BigDecimal SAQUE_MINIMO = new BigDecimal("20.00");

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

    public CarteiraService(CarteiraRepository carteiraRepo, TransacaoRepository transacaoRepo) {
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
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

        List<TransacaoResponse> transacoes = transacaoRepo
                .findByUsuarioIdOrderByCriadoEmDesc(usuarioId)
                .stream()
                .map(TransacaoResponse::from)
                .collect(Collectors.toList());
        resp.setTransacoes(transacoes);
        return resp;
    }

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
     * Saque via Pix.
     *
     * {@code chaveDoCliente} vem do header Idempotency-Key. Com ela, o mesmo
     * pedido repetido — duplo toque no botao, retry depois de um timeout —
     * devolve o resultado do primeiro em vez de debitar de novo. Sem ela o
     * lancamento ganha uma chave aleatoria: a coluna fica preenchida e unica,
     * mas a protecao contra repeticao depende de o cliente mandar a chave.
     */
    @Transactional
    public Map<String, Object> saque(Long usuarioId, BigDecimal valor, String chaveDoCliente) {
        if (valor == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Informe o valor do saque.");
        }
        // compareTo, nunca equals: equals considera a escala, entao
        // new BigDecimal("20.0").equals(new BigDecimal("20.00")) e false.
        if (valor.compareTo(SAQUE_MINIMO) < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Valor mínimo para saque é R$ 20,00.");
        }

        Carteira carteira = carteiraRepo.findByUsuarioId(usuarioId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Carteira não encontrada"));

        String chave = chaveDoSaque(usuarioId, chaveDoCliente);
        if (chaveDoCliente != null && transacaoRepo.existsByIdempotencyKey(chave)) {
            // Ja foi feito. Responder igual ao primeiro pedido e o que torna a
            // repeticao inofensiva para quem chamou.
            return respostaDoSaque(carteira);
        }

        if (carteira.getChavePix() == null || carteira.getChavePix().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Cadastre uma chave Pix antes de solicitar saque.");
        }

        // Saque sai do disponivel: o bloqueado esta comprometido com turnos.
        if (carteira.getSaldoDisponivel().compareTo(valor) < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Saldo insuficiente para saque.");
        }

        Transacao tx = new Transacao();
        tx.setUsuarioId(usuarioId);
        tx.setTipo(TipoTransacao.SAQUE);
        tx.setNatureza(NaturezaTransacao.DEBITO);
        tx.setValor(valor);
        tx.setDescricao("Transferência Pix — " + carteira.getChavePix());
        tx.setStatus(StatusTransacao.CONCLUIDO);
        tx.setIdempotencyKey(chave);
        try {
            // O lancamento vai ao banco ANTES do debito: se dois pedidos com a
            // mesma chave passarem juntos pela checagem acima, o indice unico
            // barra o segundo aqui e a transacao inteira volta — saldo incluso.
            transacaoRepo.saveAndFlush(tx);
        } catch (DataIntegrityViolationException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Este saque já está sendo processado.");
        }

        carteira.setSaldoDisponivel(carteira.getSaldoDisponivel().subtract(valor));
        carteiraRepo.save(carteira);

        return respostaDoSaque(carteira);
    }

    private static String chaveDoSaque(Long usuarioId, String chaveDoCliente) {
        if (chaveDoCliente == null || chaveDoCliente.isBlank()) {
            return "saque:" + UUID.randomUUID();
        }
        // O usuario entra na chave: a mesma string vinda de duas contas sao
        // dois pedidos diferentes, e nunca um "ja processado" do vizinho.
        return "saque:" + usuarioId + ":" + chaveDoCliente.trim();
    }

    private static Map<String, Object> respostaDoSaque(Carteira carteira) {
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
