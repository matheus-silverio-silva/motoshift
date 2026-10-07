-- ============================================================================
--  V22 — ADITIVA: quem tirou o entregador do turno, e quando, na inscrição.
--
--  O QUE MUDOU NA REGRA. "Cancelar" era um botão só para os dois lados, e
--  fazia a mesma coisa para os dois: derrubava o turno inteiro e, se faltasse
--  menos de 1h, tirava 0,5 do score do primeiro inscrito — fosse quem fosse
--  que tivesse cancelado. A loja cancelava em cima da hora e o entregador
--  pagava; um entregador saía de um turno de três vagas e os outros dois
--  perdiam o turno. Agora são duas ações:
--    cancelar  — só o lojista dono; derruba o turno, devolve a reserva e não
--                penaliza ninguém;
--    desistir  — só o entregador inscrito; cancela a inscrição DELE, reabre a
--                vaga e penaliza só ele quando faltar menos de 1h.
--
--  O QUE ENTRA, em turno_inscricoes:
--    cancelado_por_id — quem cancelou esta inscrição: o próprio entregador
--                       (desistência) ou o lojista (cancelou o turno);
--    cancelado_em     — quando.
--  É por aqui que o selo "30 dias sem cancelar" e a análise de score passam a
--  enxergar a desistência: o turno de quem desiste não é mais cancelado, então
--  turnos.cancelado_por_id (V19) não a registra. Aquela coluna continua
--  existindo e passa a dizer só quem cancelou o TURNO — sempre o lojista.
--
--  BACKFILL. Os turnos cancelados antes desta versão, com quem cancelou
--  registrado (V19), levam o autor e a data para as inscrições canceladas
--  deles. Assim o cancelamento que um entregador fez pela regra antiga
--  continua contando contra ele — e só contra ele: as inscrições dos colegas
--  de vaga recebem o id de quem cancelou, não o próprio.
--
--  FK para usuarios, ON DELETE RESTRICT como as da V11 e da V19. Índice
--  (cancelado_por_id, cancelado_em): "cancelou algo nos últimos 30 dias?".
--
--  ROLLBACK:
--    ALTER TABLE turno_inscricoes DROP CONSTRAINT fk_inscricao_cancelado_por;
--    DROP INDEX ix_inscricao_cancelado_por;
--    ALTER TABLE turno_inscricoes DROP COLUMN cancelado_por_id, DROP COLUMN cancelado_em;
-- ============================================================================

ALTER TABLE turno_inscricoes ADD COLUMN IF NOT EXISTS cancelado_por_id BIGINT;
ALTER TABLE turno_inscricoes ADD COLUMN IF NOT EXISTS cancelado_em     TIMESTAMP(6);

UPDATE turno_inscricoes i
   SET cancelado_por_id = t.cancelado_por_id,
       cancelado_em     = t.cancelado_em
  FROM turnos t
 WHERE t.id = i.turno_id
   AND t.status = 'cancelado'
   AND t.cancelado_por_id IS NOT NULL
   AND i.status = 'cancelado'
   AND i.cancelado_por_id IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inscricao_cancelado_por') THEN
        ALTER TABLE turno_inscricoes ADD CONSTRAINT fk_inscricao_cancelado_por
            FOREIGN KEY (cancelado_por_id) REFERENCES usuarios (id) ON DELETE RESTRICT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_inscricao_cancelado_por
    ON turno_inscricoes (cancelado_por_id, cancelado_em);
