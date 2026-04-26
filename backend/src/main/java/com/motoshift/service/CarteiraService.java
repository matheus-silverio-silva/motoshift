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

import java.util.List;
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
    public void saque(Long motoboyId, double valor) {
        Carteira carteira = carteiraRepo.findByMotoboyId(motoboyId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Carteira não encontrada"));

        if (carteira.getSaldoAtual() < valor) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Saldo insuficiente para saque.");
        }

        carteira.setSaldoAtual(carteira.getSaldoAtual() - valor);
        carteiraRepo.save(carteira);

        Transacao tx = new Transacao();
        tx.setMotoboyId(motoboyId);
        tx.setTipo("saque");
        tx.setValor(valor);
        tx.setDescricao("Transferência para conta bancária");
        tx.setStatus("concluido");
        transacaoRepo.save(tx);
    }
}
