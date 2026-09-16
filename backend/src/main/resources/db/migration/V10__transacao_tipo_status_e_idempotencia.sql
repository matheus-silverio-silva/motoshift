-- ============================================================================
--  V10 — Transacao: dominio fechado para tipo e status, e chave de
--        idempotencia em toda linha.
--
--  TIPO E STATUS. Turno e inscricao ja tinham virado enum; a transacao — o
--  registro de dinheiro — seguia String livre, com duas geracoes de valor
--  convivendo: "turno" / "pagamento_recebido" e "processado" / "concluido".
--  O CarteiraService tinha duas listas so para somar as duas epocas. Aqui cada
--  conceito fica com uma palavra so e o banco passa a recusar valor fora do
--  dominio (o mesmo dos enums TipoTransacao e StatusTransacao).
--
--  IDEMPOTENCIA. A coluna existia desde a V4, mas so alguns caminhos a
--  preenchiam — campo de garantia que depende de quem lembrou de preencher.
--  Linhas antigas de pagamento de turno recebem a mesma chave que o
--  PagamentoTurnoService gera hoje (pagamento_turno:{turno}:{motoboy}), para
--  que a liquidacao de um turno antigo encontre a divida pela chave. O resto
--  recebe legado:{id}. Com tudo preenchido, a coluna vira NOT NULL.
--
--  CHECK NOT VALID + VALIDATE. Adicionar um CHECK valido falharia o deploy se
--  existisse no banco um valor que ninguem conhece. NOT VALID passa a barrar
--  linhas novas imediatamente; o VALIDATE logo abaixo confere as antigas e, se
--  alguma violar, a migracao segue com um WARNING e a restricao fica NOT VALID
--  ate a limpeza — em vez de derrubar o deploy por causa de uma linha de 2025.
--
--  ROLLBACK: DROP CONSTRAINT ck_transacao_tipo, ck_transacao_status;
--            ALTER COLUMN idempotency_key DROP NOT NULL. A troca de palavras
--            (turno -> pagamento_recebido, processado -> concluido) nao tem
--            volta automatica, e nao precisa: e so o nome do mesmo conceito.
-- ============================================================================

-- ── 1. Uma palavra por conceito ─────────────────────────────────────────────

UPDATE transacoes SET tipo   = 'pagamento_recebido' WHERE tipo   = 'turno';
UPDATE transacoes SET status = 'concluido'          WHERE status = 'processado';

-- ── 2. Chave de idempotencia em toda linha ──────────────────────────────────

-- Se um turno antigo gerou duas transacoes para o mesmo entregador (finalizado
-- duas vezes, por exemplo), so a primeira fica com a chave do pagamento; a
-- outra cai no legado:{id} abaixo. O indice unico nao aceitaria as duas.
WITH candidatas AS (
    SELECT id,
           'pagamento_turno:' || turno_id || ':' || usuario_id AS chave,
           ROW_NUMBER() OVER (PARTITION BY turno_id, usuario_id ORDER BY id) AS ordem
      FROM transacoes
     WHERE tipo = 'pagamento_recebido'
       AND turno_id IS NOT NULL
       AND idempotency_key IS NULL
)
UPDATE transacoes t
   SET idempotency_key = c.chave
  FROM candidatas c
 WHERE t.id = c.id
   AND c.ordem = 1
   AND NOT EXISTS (SELECT 1 FROM transacoes x WHERE x.idempotency_key = c.chave);

UPDATE transacoes SET idempotency_key = 'legado:' || id WHERE idempotency_key IS NULL;

ALTER TABLE transacoes ALTER COLUMN idempotency_key SET NOT NULL;

-- ── 3. O dominio no banco ───────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_transacao_tipo') THEN
        ALTER TABLE transacoes ADD CONSTRAINT ck_transacao_tipo CHECK (tipo IN (
            'recarga', 'reserva', 'liberacao_reserva', 'pagamento_enviado',
            'pagamento_recebido', 'saque', 'bonus', 'estorno'
        )) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_transacao_status') THEN
        ALTER TABLE transacoes ADD CONSTRAINT ck_transacao_status CHECK (status IN (
            'pendente', 'concluido', 'falhou', 'estornado'
        )) NOT VALID;
    END IF;

    BEGIN
        ALTER TABLE transacoes VALIDATE CONSTRAINT ck_transacao_tipo;
    EXCEPTION WHEN check_violation THEN
        RAISE WARNING 'V10: transacoes com tipo fora do dominio; ck_transacao_tipo barra linhas novas e segue NOT VALID ate a limpeza';
    END;

    BEGIN
        ALTER TABLE transacoes VALIDATE CONSTRAINT ck_transacao_status;
    EXCEPTION WHEN check_violation THEN
        RAISE WARNING 'V10: transacoes com status fora do dominio; ck_transacao_status barra linhas novas e segue NOT VALID ate a limpeza';
    END;
END $$;
