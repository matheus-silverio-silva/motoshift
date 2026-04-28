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

import java.time.LocalDate;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class CarteiraService {

    private final CarteiraRepository carteiraRepo;
    private final TransacaoRepository transacaoRepo;

    public CarteiraService(CarteiraRepository carteiraRepo, TransacaoRepository transacaoRepo) {
        this.carteiraRepo = carteiraRepo;
        this.transacaoRepo = transacaoRepo;
    }

    public CarteiraResponse buscar(Long motoboyId) {
        Carteira carteira = carteiraRepo.findByMotoboyId(motoboyId)
                .orElseGet(() -> {
                    Carteira c = new Carteira();
                    c.setMotoboyId(motoboyId);
                    return carteiraRepo.save(c);
                });

        CarteiraResponse resp = CarteiraResponse.from(carteira);
        List<TransacaoResponse> transacoes = transacaoRepo
                .findByMotoboyIdOrderByCriadoEmDesc(motoboyId)
                .stream()
                .map(TransacaoResponse::from)
                .collect(Collectors.toList());
        resp.setTransacoes(transacoes);
        return resp;
    }

    @Transactional
    public Map<String, Object> saque(Long motoboyId, double valor) {
        if (valor < 20.0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Valor mínimo para saque é R$ 20,00.");
        }

        Carteira carteira = carteiraRepo.findByMotoboyId(motoboyId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Carteira não encontrada"));

        if (carteira.getChavePix() == null || carteira.getChavePix().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Cadastre uma chave Pix antes de solicitar saque.");
        }

        if (carteira.getSaldoAtual() < valor) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Saldo insuficiente para saque.");
        }

        carteira.setSaldoAtual(carteira.getSaldoAtual() - valor);
        carteiraRepo.save(carteira);

        Transacao tx = new Transacao();
        tx.setMotoboyId(motoboyId);
        tx.setTipo("saque");
        tx.setValor(valor);
        tx.setDescricao("Transferência Pix — " + carteira.getChavePix());
        tx.setStatus("concluido");
        transacaoRepo.save(tx);

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("mensagem", "Saque realizado com sucesso!");
        resp.put("novoSaldo", carteira.getSaldoAtual());
        return resp;
    }

    @Transactional
    public void atualizarPix(Long motoboyId, String chavePix) {
        Carteira carteira = carteiraRepo.findByMotoboyId(motoboyId)
                .orElseGet(() -> {
                    Carteira c = new Carteira();
                    c.setMotoboyId(motoboyId);
                    return c;
                });
        carteira.setChavePix(chavePix);
        carteiraRepo.save(carteira);
    }

    public List<Map<String, Object>> grafico(Long motoboyId, int meses) {
        List<Transacao> txs = transacaoRepo
                .findByMotoboyIdAndTipoOrderByCriadoEmDesc(motoboyId, "turno");

        LocalDate hoje = LocalDate.now();
        List<Map<String, Object>> result = new ArrayList<>();

        for (int i = meses - 1; i >= 0; i--) {
            LocalDate mesRef = hoje.minusMonths(i);
            int ano = mesRef.getYear();
            int mes = mesRef.getMonthValue();

            double total = txs.stream()
                    .filter(tx -> tx.getCriadoEm().getYear() == ano
                            && tx.getCriadoEm().getMonthValue() == mes)
                    .mapToDouble(Transacao::getValor)
                    .sum();

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("mes", String.format("%02d/%d", mes, ano));
            item.put("ganhos", Math.round(total * 100.0) / 100.0);
            result.add(item);
        }

        return result;
    }
}
