-- ============================================================================
--  V16 — ADITIVA: o horário real em que o entregador chegou e saiu.
--
--  O QUE FALTAVA. O turno tinha hora marcada e nenhuma hora real. O estado
--  EM_ANDAMENTO existia e era lido, mas nada o escrevia; a pontualidade saiu
--  do perfil por falta de dado.
--
--  O QUE ENTRA, em turno_inscricoes — e não em turnos, porque num turno de
--  três vagas cada entregador chega e sai na sua hora:
--    checkin_em          — quando o entregador tocou "Cheguei"
--    checkin_latitude    — de onde (a regra de proximidade confere a
--    checkin_longitude     distância até o ponto do turno)
--    checkout_em         — quando tocou "Encerrar turno"
--
--  CHECK: saída só depois da chegada. É a regra do CheckinService, repetida
--  no banco para valer também para o que não passa por ele.
--
--  Índice (motoboy_id, checkin_em): a pontualidade dos últimos 90 dias.
--
--  Anuláveis: inscrição de antes desta versão, ou de quem não fez check-in,
--  fica com as quatro colunas nulas — e a pontualidade a ignora.
--
--  ROLLBACK:
--    ALTER TABLE turno_inscricoes DROP CONSTRAINT ck_inscricao_saida_apos_chegada;
--    DROP INDEX ix_inscricao_checkin;
--    ALTER TABLE turno_inscricoes DROP COLUMN checkin_em, DROP COLUMN checkin_latitude,
--                                 DROP COLUMN checkin_longitude, DROP COLUMN checkout_em;
-- ============================================================================

ALTER TABLE turno_inscricoes ADD COLUMN IF NOT EXISTS checkin_em        TIMESTAMP(6);
ALTER TABLE turno_inscricoes ADD COLUMN IF NOT EXISTS checkin_latitude  FLOAT(53);
ALTER TABLE turno_inscricoes ADD COLUMN IF NOT EXISTS checkin_longitude FLOAT(53);
ALTER TABLE turno_inscricoes ADD COLUMN IF NOT EXISTS checkout_em       TIMESTAMP(6);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_inscricao_saida_apos_chegada') THEN
        ALTER TABLE turno_inscricoes ADD CONSTRAINT ck_inscricao_saida_apos_chegada
            CHECK (checkout_em IS NULL OR (checkin_em IS NOT NULL AND checkout_em >= checkin_em))
            NOT VALID;
    END IF;
    -- As colunas nasceram agora, vazias: não há linha que viole.
    ALTER TABLE turno_inscricoes VALIDATE CONSTRAINT ck_inscricao_saida_apos_chegada;
END $$;

CREATE INDEX IF NOT EXISTS ix_inscricao_checkin ON turno_inscricoes (motoboy_id, checkin_em);
