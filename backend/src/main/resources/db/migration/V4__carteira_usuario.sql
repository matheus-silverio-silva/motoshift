-- ============================================================================
--  V4 — Carteira de qualquer usuario, saldo bloqueado e extrato com dois lados.
--
--  Ate aqui carteira era coisa de entregador (motoboy_id NOT NULL UNIQUE) e o
--  extrato so tinha um dono. Com a liquidacao automatica o lojista tambem
--  precisa de carteira: e dela que sai a reserva ao publicar um turno.
--
--  Nada e renomeado no banco. A coluna saldo_atual continua com esse nome — o
--  campo Java virou saldoDisponivel, mas renomear coluna com dados em producao
--  perde informacao sem ganhar nada. As colunas legadas (motoboy_id,
--  ganhos_mensais) ficam onde estao, so perdem o NOT NULL.
-- ============================================================================

-- ── carteiras ───────────────────────────────────────────────────────────────

ALTER TABLE carteiras ADD COLUMN IF NOT EXISTS usuario_id     BIGINT;
ALTER TABLE carteiras ADD COLUMN IF NOT EXISTS saldo_bloqueado NUMERIC(12,2);
ALTER TABLE carteiras ADD COLUMN IF NOT EXISTS versao          BIGINT;

-- Toda carteira que existe hoje e de um entregador: o dono e o proprio motoboy.
UPDATE carteiras SET usuario_id      = motoboy_id WHERE usuario_id      IS NULL;
UPDATE carteiras SET saldo_bloqueado = 0          WHERE saldo_bloqueado IS NULL;
-- @Version comeca em zero. Linha com versao NULL faz o Hibernate tratar a
-- entidade como nova e tentar INSERT em cima de uma linha que ja existe.
UPDATE carteiras SET versao          = 0          WHERE versao          IS NULL;

ALTER TABLE carteiras ALTER COLUMN usuario_id      SET NOT NULL;
ALTER TABLE carteiras ALTER COLUMN saldo_bloqueado SET NOT NULL;
ALTER TABLE carteiras ALTER COLUMN saldo_bloqueado SET DEFAULT 0;
ALTER TABLE carteiras ALTER COLUMN versao          SET DEFAULT 0;

-- motoboy_id deixa de ser obrigatorio: carteira de lojista nao tem motoboy.
ALTER TABLE carteiras ALTER COLUMN motoboy_id DROP NOT NULL;

-- ganhos_mensais sai do mapeamento da entidade — o campo so incrementava e
-- nunca era resetado, entao o "ganho do mes" que ele mostrava estava errado.
-- Passa a ser calculado a partir de transacoes. A COLUNA fica no banco, com o
-- historico intacto; so perde o NOT NULL, senao todo INSERT que nao a informa
-- (o mapeamento novo nao a informa mais) seria rejeitado.
ALTER TABLE carteiras ALTER COLUMN ganhos_mensais DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uk_carteira_usuario'
    ) THEN
        ALTER TABLE carteiras ADD CONSTRAINT uk_carteira_usuario UNIQUE (usuario_id);
    END IF;
END $$;

-- ── transacoes ──────────────────────────────────────────────────────────────

ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS usuario_id      BIGINT;
ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS contraparte_id  BIGINT;
ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(255);

-- Todo lancamento existente e de um entregador.
UPDATE transacoes SET usuario_id = motoboy_id WHERE usuario_id IS NULL;

ALTER TABLE transacoes ALTER COLUMN usuario_id SET NOT NULL;
-- Pelo mesmo motivo da carteira: transacao de lojista nao tem motoboy dono.
ALTER TABLE transacoes ALTER COLUMN motoboy_id DROP NOT NULL;

-- Unica, mas nullable: as transacoes legadas nao tem chave, e no PostgreSQL
-- varios NULL nao colidem em indice unico.
CREATE UNIQUE INDEX IF NOT EXISTS uk_transacao_idempotency
    ON transacoes (idempotency_key);

CREATE INDEX IF NOT EXISTS ix_transacao_usuario ON transacoes (usuario_id, criado_em);
CREATE INDEX IF NOT EXISTS ix_transacao_turno   ON transacoes (turno_id);
