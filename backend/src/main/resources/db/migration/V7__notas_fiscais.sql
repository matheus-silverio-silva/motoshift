-- ============================================================================
--  V7 — Nota fiscal de serviço dos turnos (NFS-e).
--
--  Tabela nova, nada é alterado no que já existe: a migração é puramente
--  aditiva e pode subir junto com o código que a usa, sem janela de
--  incompatibilidade com instâncias da versão anterior — elas simplesmente
--  ignoram a tabela.
--
--  MODELO: uma nota por par (turno, prestador). Um turno de três vagas gera
--  três notas, uma para cada entregador — por isso a unicidade é do par, e não
--  do turno. O prestador é sempre o entregador e o tomador sempre o lojista;
--  emitida_por_id registra qual dos dois disparou a emissão, que é outra
--  pergunta.
--
--  ESCOPO: documento interno, com a estrutura de uma NFS-e. Não há transmissão
--  à prefeitura, RPS nem certificado digital. As colunas de tributo guardam
--  alíquota E valor de propósito: a alíquota vigente pode mudar, e a nota
--  precisa continuar mostrando a que valeu no dia em que foi emitida.
--
--  ROLLBACK: DROP TABLE notas_fiscais. Nenhuma outra tabela referencia esta.
-- ============================================================================

CREATE TABLE IF NOT EXISTS notas_fiscais (
    id                   BIGSERIAL PRIMARY KEY,

    turno_id             BIGINT        NOT NULL,
    prestador_id         BIGINT        NOT NULL,
    tomador_id           BIGINT        NOT NULL,
    emitida_por_id       BIGINT        NOT NULL,

    numero               INTEGER       NOT NULL,
    serie                VARCHAR(8)    NOT NULL,
    codigo_verificacao   VARCHAR(16)   NOT NULL,

    descricao_servico    VARCHAR(300)  NOT NULL,
    valor_servico        NUMERIC(12,2) NOT NULL,

    iss_aliquota         NUMERIC(6,4)  NOT NULL,
    iss_valor            NUMERIC(12,2) NOT NULL,
    irrf_aliquota        NUMERIC(6,4)  NOT NULL,
    irrf_valor           NUMERIC(12,2) NOT NULL,
    valor_liquido        NUMERIC(12,2) NOT NULL,

    emitida_em           TIMESTAMP     NOT NULL,
    cancelada_em         TIMESTAMP,
    motivo_cancelamento  VARCHAR(255),

    CONSTRAINT uk_nota_turno_prestador UNIQUE (turno_id, prestador_id)
);

-- As duas listagens da tela "Notas fiscais": as minhas como prestador e as
-- minhas como tomador, ambas da mais recente para a mais antiga.
CREATE INDEX IF NOT EXISTS ix_nota_prestador ON notas_fiscais (prestador_id, emitida_em);
CREATE INDEX IF NOT EXISTS ix_nota_tomador   ON notas_fiscais (tomador_id, emitida_em);
CREATE INDEX IF NOT EXISTS ix_nota_turno     ON notas_fiscais (turno_id);
