package com.motoshift.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * Um custo ou uma receita que o usuário INFORMA, para a DRE fechar (V25).
 *
 * <p><b>Não é transação, e não pode virar uma.</b> Ele não entra em
 * {@code transacoes}, não move saldo, não gera documento fiscal e não aparece
 * no extrato. O motivo é o que o ledger promete: ele registra só dinheiro que
 * a plataforma movimentou, e as três invariantes da seção 6 do
 * FLUXO-FINANCEIRO dependem disso — "carteira = extrato" e "a plataforma não
 * cria nem destrói dinheiro" só valem porque cada linha do extrato tem um
 * movimento de saldo do outro lado. O combustível que o entregador pagou no
 * posto, a plataforma não viu passar: ela ouviu falar dele. Se esse número
 * digitado entrasse no extrato, as invariantes passariam a depender da
 * memória de alguém.
 *
 * <p>Por isso a tabela é outra, o serviço é outro
 * ({@code LancamentoGerencialService}) e nada daqui chama o
 * {@code LedgerService}. Quem junta os dois mundos é a {@code DreService} — só
 * na leitura, somando o que o extrato registrou com o que a pessoa informou.
 *
 * <p><b>Sem coluna "tipo".</b> Receita ou custo, e a linha da DRE, saem da
 * {@link CategoriaLancamento}. O {@code valor} é sempre positivo.
 *
 * <p><b>Regime de caixa.</b> {@code data} é o dia em que o dinheiro saiu ou
 * entrou. Com {@code recorrente}, vira o dia do mês em que isso se repete — a
 * regra está em {@code service.Recorrencia}.
 */
@Entity
@Table(name = "lancamentos_gerenciais",
       indexes = @Index(name = "ix_lancamento_gerencial_usuario_data", columnList = "usuarioId, data"))
public class LancamentoGerencial {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, updatable = false)
    private Long usuarioId;

    @Column(nullable = false, length = 40)
    private CategoriaLancamento categoria;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal valor;

    /** O dia do pagamento (ou do recebimento). */
    @Column(nullable = false)
    private LocalDate data;

    @Column(nullable = false)
    private boolean recorrente;

    /** Última data em que a recorrência ainda vale; nulo = sem fim. */
    private LocalDate recorrenteAte;

    /** O turno a que o lançamento se refere, quando se refere a um. */
    private Long turnoId;

    /** Quilômetros rodados — é o que permite o "custo por km". */
    @Column(precision = 8, scale = 1)
    private BigDecimal km;

    @Column(length = 200)
    private String descricao;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @Column(nullable = false)
    private LocalDateTime atualizadoEm;

    protected LancamentoGerencial() {}

    public LancamentoGerencial(Long usuarioId) {
        this.usuarioId = usuarioId;
    }

    @PrePersist
    private void prePersist() {
        LocalDateTime agora = LocalDateTime.now();
        if (criadoEm == null) criadoEm = agora;
        atualizadoEm = agora;
    }

    @PreUpdate
    private void preUpdate() {
        atualizadoEm = LocalDateTime.now();
    }

    public Long getId() { return id; }
    public Long getUsuarioId() { return usuarioId; }

    public CategoriaLancamento getCategoria() { return categoria; }
    public void setCategoria(CategoriaLancamento categoria) { this.categoria = categoria; }

    public BigDecimal getValor() { return valor; }
    public void setValor(BigDecimal valor) { this.valor = valor; }

    public LocalDate getData() { return data; }
    public void setData(LocalDate data) { this.data = data; }

    public boolean isRecorrente() { return recorrente; }
    public void setRecorrente(boolean recorrente) { this.recorrente = recorrente; }

    public LocalDate getRecorrenteAte() { return recorrenteAte; }
    public void setRecorrenteAte(LocalDate recorrenteAte) { this.recorrenteAte = recorrenteAte; }

    public Long getTurnoId() { return turnoId; }
    public void setTurnoId(Long turnoId) { this.turnoId = turnoId; }

    public BigDecimal getKm() { return km; }
    public void setKm(BigDecimal km) { this.km = km; }

    public String getDescricao() { return descricao; }
    public void setDescricao(String descricao) { this.descricao = descricao; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
    public LocalDateTime getAtualizadoEm() { return atualizadoEm; }
}
