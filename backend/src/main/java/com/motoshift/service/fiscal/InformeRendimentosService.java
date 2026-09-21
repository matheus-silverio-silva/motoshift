package com.motoshift.service.fiscal;

import com.motoshift.dto.DocumentoResponse;
import com.motoshift.dto.InformeAnualResponse;
import com.motoshift.dto.InformeAnualResponse.PorContraparte;
import com.motoshift.dto.InformeAnualResponse.PorMes;
import com.motoshift.entity.NotaFiscal;
import com.motoshift.entity.StatusTransacao;
import com.motoshift.entity.TipoTransacao;
import com.motoshift.entity.Transacao;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.NotaFiscalRepository;
import com.motoshift.repository.TransacaoRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.util.Csv;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.Year;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Informe anual SIMULADO: o que o entregador recebeu no ano, por fonte
 * pagadora e por mês; ou o que o lojista pagou em serviços, por prestador.
 *
 * <p><b>A base é o extrato, não as notas.</b> Rendimento é dinheiro que
 * entrou, e entrou quando o pagamento_recebido foi creditado — regime de
 * caixa, como um informe de rendimentos de verdade. Somar as notas emitidas
 * deixaria de fora todo pagamento cuja nota ainda não foi gerada, e o informe
 * mentiria para menos. As notas entram ao lado, como contagem do que já está
 * documentado.
 *
 * <p>É por isso que a soma do informe bate, por construção, com a soma dos
 * pagamentos recebidos concluídos do ano — e há um teste que confere.
 *
 * <p>Nada aqui é declaração à Receita. É a mecânica do documento, com a
 * marca "DOCUMENTO SIMULADO — SEM VALOR FISCAL".
 */
@Service
public class InformeRendimentosService {

    private final TransacaoRepository transacaoRepo;
    private final NotaFiscalRepository notaRepo;
    private final UsuarioRepository usuarioRepo;

    public InformeRendimentosService(TransacaoRepository transacaoRepo,
                                     NotaFiscalRepository notaRepo,
                                     UsuarioRepository usuarioRepo) {
        this.transacaoRepo = transacaoRepo;
        this.notaRepo = notaRepo;
        this.usuarioRepo = usuarioRepo;
    }

    @Transactional(readOnly = true)
    public InformeAnualResponse informe(Long usuarioId, boolean ehLojista, Integer anoPedido) {
        int ano = anoPedido == null ? Year.now().getValue() : anoPedido;
        if (ano < 2000 || ano > 2100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ano fora do intervalo aceito.");
        }
        LocalDateTime inicio = LocalDateTime.of(ano, 1, 1, 0, 0);
        LocalDateTime fim = inicio.plusYears(1);

        TipoTransacao pagamento = ehLojista
                ? TipoTransacao.PAGAMENTO_ENVIADO
                : TipoTransacao.PAGAMENTO_RECEBIDO;
        List<Transacao> lancamentos = transacaoRepo
                .findByUsuarioIdAndTipoInAndStatusAndCriadoEmGreaterThanEqualAndCriadoEmLessThan(
                        usuarioId,
                        List.of(pagamento, TipoTransacao.RETENCAO_ISS, TipoTransacao.RETENCAO_IRRF),
                        StatusTransacao.CONCLUIDO, inicio, fim);

        List<Transacao> pagamentos = lancamentos.stream().filter(t -> t.getTipo() == pagamento).toList();
        Set<String> documentados = pagamentosDocumentados(pagamentos);

        Map<Long, Acumulado> porContraparte = new LinkedHashMap<>();
        BigDecimal[] porMesTotal = new BigDecimal[12];
        int[] porMesQtd = new int[12];
        for (int i = 0; i < 12; i++) porMesTotal[i] = BigDecimal.ZERO;

        for (Transacao t : lancamentos) {
            Acumulado a = porContraparte.computeIfAbsent(t.getContraparteId(), k -> new Acumulado());
            switch (t.getTipo()) {
                case RETENCAO_ISS -> a.iss = a.iss.add(t.getValor());
                case RETENCAO_IRRF -> a.irrf = a.irrf.add(t.getValor());
                default -> {
                    a.total = a.total.add(t.getValor());
                    a.pagamentos++;
                    if (documentados.contains(chave(t))) a.notas++;
                    int m = t.getCriadoEm().getMonthValue() - 1;
                    porMesTotal[m] = porMesTotal[m].add(t.getValor());
                    porMesQtd[m]++;
                }
            }
        }

        Map<Long, Usuario> pessoas = new HashMap<>();
        for (Usuario u : usuarioRepo.findAllById(porContraparte.keySet().stream()
                .filter(id -> id != null).toList())) {
            pessoas.put(u.getId(), u);
        }

        List<PorContraparte> contrapartes = new ArrayList<>();
        for (Map.Entry<Long, Acumulado> e : porContraparte.entrySet()) {
            Usuario u = pessoas.get(e.getKey());
            DocumentoDaParte doc = DocumentoDaParte.de(u);
            Acumulado a = e.getValue();
            contrapartes.add(new PorContraparte(e.getKey(), nomeDe(u), doc.tipo(), doc.numero(),
                    reais(a.total), reais(a.iss), reais(a.irrf), a.pagamentos, a.notas));
        }
        contrapartes.sort(Comparator.comparing(PorContraparte::total).reversed());

        List<PorMes> meses = new ArrayList<>(12);
        for (int i = 0; i < 12; i++) meses.add(new PorMes(i + 1, reais(porMesTotal[i]), porMesQtd[i]));

        return new InformeAnualResponse(
                ano,
                ehLojista ? "tomador" : "prestador",
                ehLojista ? "Serviços tomados no ano" : "Informe de rendimentos",
                reais(soma(contrapartes, PorContraparte::total)),
                reais(soma(contrapartes, PorContraparte::issRetido)),
                reais(soma(contrapartes, PorContraparte::irrfRetido)),
                pagamentos.size(),
                contrapartes.stream().mapToInt(PorContraparte::notasEmitidas).sum(),
                contrapartes,
                meses,
                true,
                DocumentoResponse.MARCA);
    }

    /**
     * O informe em CSV — separador ';', como o extrato, porque o Excel em
     * português usa a vírgula como separador decimal.
     */
    public String exportarCsv(Long usuarioId, boolean ehLojista, Integer ano) {
        InformeAnualResponse inf = informe(usuarioId, ehLojista, ano);
        StringBuilder csv = new StringBuilder();
        csv.append(Csv.seguro(inf.marca())).append('\n');
        csv.append(Csv.seguro(inf.titulo())).append(';').append(inf.ano()).append('\n');
        csv.append(ehLojista ? "prestador" : "fonte_pagadora")
                .append(";documento;total;iss_retido;irrf_retido;pagamentos;notas_emitidas\n");
        for (PorContraparte c : inf.contrapartes()) {
            csv.append(Csv.seguro(c.nome())).append(';')
               .append(Csv.seguro(c.documento() == null ? c.documentoTipo() + " não informado" : c.documento()))
               .append(';')
               .append(Csv.decimal(c.total())).append(';')
               .append(Csv.decimal(c.issRetido())).append(';')
               .append(Csv.decimal(c.irrfRetido())).append(';')
               .append(c.pagamentos()).append(';')
               .append(c.notasEmitidas()).append('\n');
        }
        csv.append("TOTAL;;").append(Csv.decimal(inf.total())).append(';')
           .append(Csv.decimal(inf.issRetido())).append(';')
           .append(Csv.decimal(inf.irrfRetido())).append(';')
           .append(inf.pagamentos()).append(';')
           .append(inf.notasEmitidas()).append('\n');
        csv.append('\n').append("mes;total;pagamentos\n");
        for (PorMes m : inf.meses()) {
            csv.append(m.mes()).append(';').append(Csv.decimal(m.total())).append(';')
               .append(m.pagamentos()).append('\n');
        }
        return csv.toString();
    }

    // ── Apoio ───────────────────────────────────────────────────────────────

    /** "turno:prestador" dos pagamentos que já têm nota válida (não cancelada). */
    private Set<String> pagamentosDocumentados(List<Transacao> pagamentos) {
        Set<Long> turnos = new HashSet<>();
        for (Transacao t : pagamentos) {
            if (t.getTurnoId() != null) turnos.add(t.getTurnoId());
        }
        Set<String> saida = new HashSet<>();
        if (turnos.isEmpty()) return saida;
        for (NotaFiscal n : notaRepo.findByTurnoIdIn(turnos)) {
            if (!n.isCancelada()) saida.add(n.getTurnoId() + ":" + n.getPrestadorId());
        }
        return saida;
    }

    private static String chave(Transacao t) {
        return t.getTurnoId() + ":" + IndiceDeDocumentos.prestadorDe(t);
    }

    private static String nomeDe(Usuario u) {
        if (u == null) return "—";
        return u.getNomeFantasia() != null && !u.getNomeFantasia().isBlank()
                ? u.getNomeFantasia() : u.getNome();
    }

    private static BigDecimal soma(List<PorContraparte> l,
                                   java.util.function.Function<PorContraparte, BigDecimal> campo) {
        return l.stream().map(campo).reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private static BigDecimal reais(BigDecimal v) {
        return v.setScale(2, RoundingMode.HALF_UP);
    }

    private static final class Acumulado {
        BigDecimal total = BigDecimal.ZERO;
        BigDecimal iss = BigDecimal.ZERO;
        BigDecimal irrf = BigDecimal.ZERO;
        int pagamentos;
        int notas;
    }
}
