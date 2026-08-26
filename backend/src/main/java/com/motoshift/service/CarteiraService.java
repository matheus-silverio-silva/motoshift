package com.motoshift.service;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Transacao;
import com.motoshift.repository.CarteiraRepository;
import com.motoshift.repository.TransacaoRepository;
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
     * Tipos de lancamento que contam como ganho do entregador.
     * "turno" e o legado, anterior a liquidacao automatica; "pagamento_recebido"
     * e o que passa a ser gerado. Somar os dois mantem o extrato coerente para
     * quem tem historico das duas epocas.
     */
    public static final List<String> TIPOS_GANHO = List.of("turno", "pagamento_recebido");

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

    /**
     * Ganhos do mes corrente, somados das transacoes.
     *
     * Substitui o antigo campo Carteira.ganhosMensais, que so incrementava e
     * nunca era resetado — ou seja, mostrava o acumulado de sempre rotulado
     * como "do mes".
     */
    public BigDecimal ganhosDoMes(Long usuarioId) {
        LocalDateTime inicioMes = LocalDate.now().withDayOfMonth(1).atStartOfDay();
        BigDecimal total = transacaoRepo.somarPorTipoDesde(usuarioId, TIPOS_GANHO, inicioMes);
        return (total == null ? BigDecimal.ZERO : total).setScale(2, RoundingMode.HALF_UP);
    }

    @Transactional
    public Map<String, Object> saque(Long usuarioId, BigDecimal valor) {
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

        if (carteira.getChavePix() == null || carteira.getChavePix().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Cadastre uma chave Pix antes de solicitar saque.");
        }

        // Saque sai do disponivel: o bloqueado esta comprometido com turnos.
        if (carteira.getSaldoDisponivel().compareTo(valor) < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Saldo insuficiente para saque.");
        }

        carteira.setSaldoDisponivel(carteira.getSaldoDisponivel().subtract(valor));
        carteiraRepo.save(carteira);

        Transacao tx = new Transacao();
        tx.setUsuarioId(usuarioId);
        tx.setTipo("saque");
        tx.setValor(valor);
        tx.setDescricao("Transferência Pix — " + carteira.getChavePix());
        tx.setStatus("concluido");
        transacaoRepo.save(tx);

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

    public List<Map<String, Object>> grafico(Long usuarioId, int meses) {
        List<Transacao> txs = transacaoRepo
                .findByUsuarioIdAndTipoInOrderByCriadoEmDesc(usuarioId, TIPOS_GANHO);

        LocalDate hoje = LocalDate.now();
        List<Map<String, Object>> result = new ArrayList<>();

        for (int i = meses - 1; i >= 0; i--) {
            LocalDate mesRef = hoje.minusMonths(i);
            int ano = mesRef.getYear();
            int mes = mesRef.getMonthValue();

            BigDecimal total = txs.stream()
                    .filter(tx -> tx.getCriadoEm().getYear() == ano
                            && tx.getCriadoEm().getMonthValue() == mes)
                    .map(Transacao::getValor)
                    .filter(Objects::nonNull)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("mes", String.format("%02d/%d", mes, ano));
            item.put("ganhos", total.setScale(2, RoundingMode.HALF_UP));
            result.add(item);
        }

        return result;
    }
}
