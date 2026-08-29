-- ============================================================================
--  V5 — Backfill: todo turno com entregador passa a ter uma inscricao.
--
--  POR QUE: o pagamento tem hoje dois caminhos para a mesma regra. O caminho
--  novo passa por turno_inscricoes (uma linha por entregador, com dupla
--  confirmacao); o antigo grava lojista_confirmou_em/motoboy_confirmou_em no
--  proprio turno, para os turnos aceitos antes do sistema de vagas. Toda regra
--  de dinheiro existe em duplicata, e o dia em que so uma for corrigida e o dia
--  do bug de dinheiro.
--
--  Esta e a fase EXPAND do expand/contract: ela so ACRESCENTA dados. Depois que
--  ela rodar, todo turno com motoboy tem inscricao, e o codigo do fallback pode
--  morrer (vai no mesmo commit). As colunas do turno continuam existindo e
--  populadas — quem estiver rodando a versao anterior do backend nao quebra.
--  Quem as remove e a V6, num deploy posterior.
--
--  IDEMPOTENTE: o NOT EXISTS deixa rodar duas vezes sem duplicar. Vale tambem
--  como rede contra o uk_turno_motoboy (turno_id, motoboy_id), que abortaria a
--  migracao inteira em caso de duplicata.
-- ============================================================================

INSERT INTO turno_inscricoes (
    turno_id,
    motoboy_id,
    status,
    pagamento_status,
    lojista_confirmou_em,
    motoboy_confirmou_em,
    criado_em
)
SELECT
    t.id,
    t.motoboy_id,

    -- Traducao de StatusTurno para StatusInscricao, que tem so tres valores.
    -- Copiar cru quebraria a leitura: 'expirado' e 'em_andamento' nao existem
    -- do lado da inscricao e o converter lancaria excecao ao ler a linha.
    --
    -- So os dois estados terminais tem correspondencia direta. Todo o resto
    -- vira 'aceito', que e o que a inscricao de fato registra: este entregador
    -- esta neste turno. O ciclo de vida continua sendo do turno.
    CASE t.status
        WHEN 'finalizado' THEN 'finalizado'
        WHEN 'cancelado'  THEN 'cancelado'
        ELSE 'aceito'
    END,

    -- Mesmo dominio dos dois lados (null | pendente | pago): copia direta.
    t.pagamento_status,

    -- O que o fallback gravava no turno passa a viver na inscricao. Sem isto,
    -- um turno em que o lojista ja confirmou perderia essa confirmacao e a
    -- pessoa teria de confirmar de novo.
    t.lojista_confirmou_em,
    t.motoboy_confirmou_em,

    -- A inscricao nao existia antes; a data do turno e a aproximacao honesta e,
    -- por ser deterministica, mantem a migracao idempotente de verdade.
    t.criado_em
FROM turnos t
WHERE t.motoboy_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM turno_inscricoes i
      WHERE i.turno_id = t.id
  );

-- ── Conferencia ─────────────────────────────────────────────────────────────
-- Rodar depois do deploy. O esperado e 0 nas duas colunas; qualquer numero
-- diferente de zero significa que o fallback ainda tem populacao e que a V6
-- NAO pode ser aplicada.
--
--   SELECT
--       (SELECT COUNT(*) FROM turnos t
--         WHERE t.motoboy_id IS NOT NULL
--           AND NOT EXISTS (SELECT 1 FROM turno_inscricoes i
--                            WHERE i.turno_id = t.id)) AS turnos_sem_inscricao,
--       (SELECT COUNT(*) FROM turnos t
--         WHERE (t.lojista_confirmou_em IS NOT NULL
--                OR t.motoboy_confirmou_em IS NOT NULL)
--           AND NOT EXISTS (SELECT 1 FROM turno_inscricoes i
--                            WHERE i.turno_id = t.id)) AS confirmacoes_orfas;
