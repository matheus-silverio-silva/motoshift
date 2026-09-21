-- ============================================================================
--  V14 — ADITIVA: a nota fiscal passa a apontar para o dinheiro que documenta.
--
--  O QUE ESTAVA ERRADO. A NFS-e (V7) era ligada ao turno, não ao pagamento: a
--  base de cálculo vinha do valor estimado do turno, e nada garantia que o
--  valor documentado fosse o que de fato entrou na carteira. Pior, a nota
--  descontava ISS e IRRF no valor líquido, enquanto a liquidação (V12)
--  creditava o valor cheio — nota e extrato contavam histórias diferentes
--  sobre o mesmo dinheiro.
--
--  O QUE ENTRA:
--    notas_fiscais.transacao_id      — o pagamento_recebido que a nota documenta
--    notas_fiscais.operacao_id       — a operação do extrato (liga os dois lados)
--    notas_fiscais.competencia       — data do serviço, gravada na emissão
--    notas_fiscais.tributos_retidos  — se os tributos saíram do dinheiro ou são
--                                      só informativos (Lei 12.741/2012)
--    transacoes.tipo ganha 'retencao_iss' e 'retencao_irrf'
--
--  UMA NOTA POR PAGAMENTO. O índice único parcial em transacao_id é o que torna
--  a emissão idempotente pelo lado do extrato; a unicidade (turno_id,
--  prestador_id) da V7 continua, e as duas dizem a mesma coisa por caminhos
--  diferentes. Parcial porque notas antigas cujo pagamento não existe mais no
--  extrato ficam com transacao_id nulo — não há o que apontar.
--
--  BACKFILL:
--    * transacao_id/operacao_id: o pagamento_recebido concluído do mesmo turno
--      e do mesmo prestador. Se houver mais de um (não deveria), fica o mais
--      antigo.
--    * competencia: o início do turno, que era de onde a tela já a lia.
--    * valor_liquido = valor_servico e tributos_retidos = false em TODAS as
--      notas existentes. Nenhuma retenção aconteceu de fato até aqui — o
--      entregador recebeu o valor cheio em todos os pagamentos —, então o
--      líquido que as notas mostravam era falso. Os valores de ISS e IRRF ficam
--      como estavam e passam a ser lidos como "valor aproximado dos tributos".
--      Reescrever o documento é aceitável porque ele é SIMULADO e declara isso;
--      com NFS-e de verdade o caminho seria cancelar e substituir.
--
--  NOT VALID + VALIDATE, como nas V10/V11/V12.
--
--  ROLLBACK:
--    ALTER TABLE notas_fiscais DROP COLUMN transacao_id, operacao_id,
--                                          competencia, tributos_retidos;
--    (o CHECK de transacoes.tipo volta à lista da V10 depois de apagar as
--     linhas de retenção — que só existem com a retenção ligada)
-- ============================================================================

-- ── 1. Colunas novas em notas_fiscais ───────────────────────────────────────

ALTER TABLE notas_fiscais ADD COLUMN IF NOT EXISTS transacao_id     BIGINT;
ALTER TABLE notas_fiscais ADD COLUMN IF NOT EXISTS operacao_id      UUID;
ALTER TABLE notas_fiscais ADD COLUMN IF NOT EXISTS competencia      TIMESTAMP;
ALTER TABLE notas_fiscais ADD COLUMN IF NOT EXISTS tributos_retidos BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 2. Backfill ─────────────────────────────────────────────────────────────

UPDATE notas_fiscais n
   SET transacao_id = t.id,
       operacao_id  = t.operacao_id
  FROM (SELECT DISTINCT ON (turno_id, usuario_id) id, turno_id, usuario_id, operacao_id
          FROM transacoes
         WHERE tipo = 'pagamento_recebido' AND status = 'concluido'
         ORDER BY turno_id, usuario_id, criado_em, id) t
 WHERE n.transacao_id IS NULL
   AND t.turno_id   = n.turno_id
   AND t.usuario_id = n.prestador_id;

UPDATE notas_fiscais n
   SET competencia = tu.data_inicio
  FROM turnos tu
 WHERE n.competencia IS NULL
   AND tu.id = n.turno_id;

UPDATE notas_fiscais SET competencia = emitida_em WHERE competencia IS NULL;
ALTER TABLE notas_fiscais ALTER COLUMN competencia SET NOT NULL;

UPDATE notas_fiscais
   SET valor_liquido    = valor_servico,
       tributos_retidos = FALSE
 WHERE valor_liquido <> valor_servico;

-- ── 3. Índices ──────────────────────────────────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS uk_nota_transacao
    ON notas_fiscais (transacao_id) WHERE transacao_id IS NOT NULL;

-- Filtro por período de competência na tela de notas.
CREATE INDEX IF NOT EXISTS ix_nota_competencia ON notas_fiscais (competencia);

-- ── 4. Domínio e integridade ────────────────────────────────────────────────

DO $$
BEGIN
    -- O CHECK de tipo é recriado com os dois tipos de retenção. DROP + ADD na
    -- mesma transação: não há janela em que o banco aceite qualquer valor.
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_transacao_tipo') THEN
        ALTER TABLE transacoes DROP CONSTRAINT ck_transacao_tipo;
    END IF;
    ALTER TABLE transacoes ADD CONSTRAINT ck_transacao_tipo CHECK (tipo IN (
        'recarga', 'reserva', 'liberacao_reserva', 'pagamento_enviado',
        'pagamento_recebido', 'saque', 'bonus', 'estorno',
        'retencao_iss', 'retencao_irrf'
    )) NOT VALID;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_nota_transacao') THEN
        ALTER TABLE notas_fiscais ADD CONSTRAINT fk_nota_transacao
            FOREIGN KEY (transacao_id) REFERENCES transacoes (id) ON DELETE RESTRICT NOT VALID;
    END IF;

    BEGIN
        ALTER TABLE transacoes VALIDATE CONSTRAINT ck_transacao_tipo;
    EXCEPTION WHEN check_violation THEN
        RAISE WARNING 'V14: transacoes com tipo fora do dominio; ck_transacao_tipo barra linhas novas e segue NOT VALID ate a limpeza';
    END;

    -- O backfill só aponta para transações que existem, então a FK valida.
    ALTER TABLE notas_fiscais VALIDATE CONSTRAINT fk_nota_transacao;
END $$;
