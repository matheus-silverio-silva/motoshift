package com.motoshift.repository;

import com.motoshift.dto.ExtratoFiltro;
import com.motoshift.entity.Transacao;
import jakarta.persistence.criteria.Predicate;
import org.springframework.data.jpa.domain.Specification;

import java.util.ArrayList;
import java.util.List;

/**
 * Os filtros do extrato, traduzidos para SQL.
 *
 * <p><b>Por que Specification e não um punhado de métodos derivados.</b> São
 * dez filtros combináveis: período, tipo, status, natureza, turno, contraparte,
 * faixa de valor e busca textual. Como métodos de repositório, isso seria uma
 * explosão combinatória de assinaturas — ou, o que é pior e foi o que existia
 * antes, filtro nenhum no banco e a lista inteira mandada para o app filtrar em
 * memória. Um extrato com dois anos de uso não cabe nessa estratégia.
 *
 * <p>Cada filtro ausente simplesmente não entra na cláusula: {@code null}
 * significa "não filtre por isso", nunca "filtre por nada".
 */
public final class TransacaoSpecs {

    private TransacaoSpecs() {}

    public static Specification<Transacao> de(Long usuarioId, ExtratoFiltro f) {
        return (raiz, consulta, cb) -> {
            List<Predicate> onde = new ArrayList<>();

            // O dono nunca é opcional: extrato é de alguém, e esse alguém sai
            // do token. Um filtro esquecido aqui vazaria o extrato alheio.
            onde.add(cb.equal(raiz.get("usuarioId"), usuarioId));

            if (f.getDataInicio() != null) {
                onde.add(cb.greaterThanOrEqualTo(raiz.get("criadoEm"), f.getDataInicio()));
            }
            if (f.getDataFim() != null) {
                // Fim EXCLUSIVO, com o dia seguinte já somado por quem montou o
                // filtro: "até 30/09" tem de incluir 30/09 às 23:59, e um <=
                // sobre o início do dia deixaria o último dia de fora.
                onde.add(cb.lessThan(raiz.get("criadoEm"), f.getDataFim()));
            }
            if (f.getTipos() != null && !f.getTipos().isEmpty()) {
                onde.add(raiz.get("tipo").in(f.getTipos()));
            }
            if (f.getStatus() != null) {
                onde.add(cb.equal(raiz.get("status"), f.getStatus()));
            }
            if (f.getNatureza() != null) {
                onde.add(cb.equal(raiz.get("natureza"), f.getNatureza()));
            }
            if (f.getTurnoId() != null) {
                onde.add(cb.equal(raiz.get("turnoId"), f.getTurnoId()));
            }
            if (f.getContraparteId() != null) {
                onde.add(cb.equal(raiz.get("contraparteId"), f.getContraparteId()));
            }
            if (f.getValorMin() != null) {
                onde.add(cb.greaterThanOrEqualTo(raiz.get("valor"), f.getValorMin()));
            }
            if (f.getValorMax() != null) {
                onde.add(cb.lessThanOrEqualTo(raiz.get("valor"), f.getValorMax()));
            }
            if (f.getBusca() != null && !f.getBusca().isBlank()) {
                // lower() nos dois lados: "pizzaria" tem de achar "Pizzaria".
                String alvo = "%" + f.getBusca().trim().toLowerCase() + "%";
                onde.add(cb.like(cb.lower(raiz.get("descricao")), alvo));
            }

            return cb.and(onde.toArray(new Predicate[0]));
        };
    }
}
