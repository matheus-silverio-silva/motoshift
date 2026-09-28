-- ============================================================================
--  V19 — ADITIVA: a meta do mês do entregador e quem cancelou o turno.
--
--  usuarios.meta_mensal — quanto o entregador quer ganhar no mês (pagamentos
--    recebidos + gorjetas). Editável no perfil; nula = sem meta, e o painel
--    convida a definir em vez de desenhar uma barra zerada. CHECK: positiva.
--
--  turnos.cancelado_por_id / cancelado_em — o selo "30 dias sem cancelar"
--    precisa saber QUEM cancelou: cancelar é permitido aos dois lados, e sem
--    esta coluna um cancelamento da loja tiraria o selo do entregador.
--    Anuláveis: turno não cancelado, ou cancelado antes desta versão (quem
--    cancelou esses não se sabe — e o selo não os conta contra ninguém).
--    FK para usuarios, ON DELETE RESTRICT como as da V11.
--
--  ROLLBACK:
--    ALTER TABLE usuarios DROP CONSTRAINT ck_usuario_meta_positiva;
--    ALTER TABLE usuarios DROP COLUMN meta_mensal;
--    ALTER TABLE turnos DROP CONSTRAINT fk_turno_cancelado_por;
--    DROP INDEX ix_turno_cancelado_por;
--    ALTER TABLE turnos DROP COLUMN cancelado_por_id, DROP COLUMN cancelado_em;
-- ============================================================================

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS meta_mensal NUMERIC(12,2);

ALTER TABLE turnos ADD COLUMN IF NOT EXISTS cancelado_por_id BIGINT;
ALTER TABLE turnos ADD COLUMN IF NOT EXISTS cancelado_em     TIMESTAMP(6);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_usuario_meta_positiva') THEN
        ALTER TABLE usuarios ADD CONSTRAINT ck_usuario_meta_positiva
            CHECK (meta_mensal IS NULL OR meta_mensal > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_turno_cancelado_por') THEN
        ALTER TABLE turnos ADD CONSTRAINT fk_turno_cancelado_por
            FOREIGN KEY (cancelado_por_id) REFERENCES usuarios (id) ON DELETE RESTRICT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_turno_cancelado_por ON turnos (cancelado_por_id, cancelado_em);
