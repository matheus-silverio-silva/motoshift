-- ============================================================================
--  V12 — ADITIVA: o dinheiro passa a ter origem, destino e rastro.
--
--  O QUE ESTAVA ERRADO. Ate aqui a liquidacao de um turno CREDITAVA o
--  entregador sem DEBITAR ninguem: o dinheiro aparecia do nada. saldo_bloqueado
--  existia desde a V4 e nunca era movimentado, nao havia recarga nem reserva, e
--  o pagamento so acontecia se as duas partes apertassem um botao. Esta
--  migracao da ao banco as colunas de que o ledger precisa para que todo
--  centavo tenha uma perna de entrada e uma de saida.
--
--  O QUE ENTRA:
--    transacoes.natureza              — credito|debito, o sinal que a tela usa
--    transacoes.operacao_id           — une os dois lados de uma transferencia
--    transacoes.saldo_*_apos          — foto do saldo depois do lancamento
--    cobrancas                        — recargas e saques no gateway simulado
--
--  NATUREZA NAO E A ARITMETICA DO SALDO. reserva e liberacao_reserva so trocam
--  dinheiro entre os dois bolsos da mesma carteira, e pagamento_enviado sai do
--  bloqueado sem encostar no disponivel. Somar valor com o sinal desta coluna
--  NAO devolve o saldo — quem sabe qual bolso se move e o LedgerService, em um
--  lugar so. A coluna existe porque o app decidia o sinal por uma lista de
--  tipos, e um tipo novo virava credito por omissao (reserva de R$ 360
--  desenhada como entrada).
--
--  BACKFILL. Das linhas que existem hoje, so 'saque' e saida; o resto do que o
--  backend chegou a emitir ('pagamento_recebido', 'bonus') e entrada. Os tipos
--  que ninguem emitiu ainda sao classificados pela definicao, nao pelos dados.
--
--  SNAPSHOT DE SALDO FICA NULL NO HISTORICO. Nao da para reconstruir o saldo
--  daquele instante: os lancamentos antigos nao formam uma serie fechada (a
--  V4 criou carteiras com saldo ja diferente de zero). Uma coluna nula diz "nao
--  sei"; um numero calculado por aproximacao diria uma mentira conferivel.
--
--  NOT VALID + VALIDATE, como nas V10/V11: o CHECK barra linha nova na hora, e
--  se alguma linha antiga violar, a migracao segue com WARNING em vez de
--  derrubar o deploy.
--
--  ROLLBACK:
--    ALTER TABLE transacoes DROP COLUMN natureza, operacao_id,
--                                       saldo_disponivel_apos, saldo_bloqueado_apos;
--    DROP TABLE cobrancas;
-- ============================================================================

-- ── 1. Colunas novas em transacoes ──────────────────────────────────────────

ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS natureza              VARCHAR(8);
ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS operacao_id           UUID;
ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS saldo_disponivel_apos NUMERIC(12,2);
ALTER TABLE transacoes ADD COLUMN IF NOT EXISTS saldo_bloqueado_apos  NUMERIC(12,2);

UPDATE transacoes
   SET natureza = CASE
         WHEN tipo IN ('saque', 'reserva', 'pagamento_enviado') THEN 'debito'
         ELSE 'credito'
       END
 WHERE natureza IS NULL;

ALTER TABLE transacoes ALTER COLUMN natureza SET NOT NULL;

-- ── 2. Cobrancas: a fronteira com o mundo de fora ───────────────────────────
--
-- Tabela propria e nao mais um campo em transacoes porque os ciclos de vida
-- sao diferentes: o lancamento e um fato consumado, a cobranca e um pedido em
-- aberto que o gateway ainda vai responder. Misturar faria o extrato ter linhas
-- de intencao, e "saldo = soma do extrato" deixaria de valer.

CREATE TABLE IF NOT EXISTS cobrancas (
    id              BIGSERIAL     PRIMARY KEY,
    usuario_id      BIGINT        NOT NULL,
    tipo            VARCHAR(16)   NOT NULL,
    valor           NUMERIC(12,2) NOT NULL,
    status          VARCHAR(16)   NOT NULL DEFAULT 'pendente',
    codigo_pix      VARCHAR(512),
    criada_em       TIMESTAMP     NOT NULL,
    concluida_em    TIMESTAMP,
    idempotency_key VARCHAR(255)  NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_cobranca_idempotency ON cobrancas (idempotency_key);
CREATE INDEX IF NOT EXISTS ix_cobranca_usuario ON cobrancas (usuario_id, criada_em);

-- ── 3. Indices do extrato ───────────────────────────────────────────────────
-- O filtro por tipo e o corte mais usado depois do periodo; operacao_id serve
-- para achar o outro lado de uma transferencia a partir de um dos lados.

CREATE INDEX IF NOT EXISTS ix_transacao_usuario_tipo ON transacoes (usuario_id, tipo, criado_em);
CREATE INDEX IF NOT EXISTS ix_transacao_operacao     ON transacoes (operacao_id);

-- ── 4. Dominio no banco ─────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_transacao_natureza') THEN
        ALTER TABLE transacoes ADD CONSTRAINT ck_transacao_natureza
            CHECK (natureza IN ('credito', 'debito')) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_cobranca_tipo') THEN
        ALTER TABLE cobrancas ADD CONSTRAINT ck_cobranca_tipo
            CHECK (tipo IN ('recarga', 'saque')) NOT VALID;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_cobranca_status') THEN
        ALTER TABLE cobrancas ADD CONSTRAINT ck_cobranca_status
            CHECK (status IN ('pendente', 'concluido', 'falhou')) NOT VALID;
    END IF;

    -- Valor de cobranca e sempre positivo: o sinal esta no tipo, nunca no numero.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_cobranca_valor') THEN
        ALTER TABLE cobrancas ADD CONSTRAINT ck_cobranca_valor
            CHECK (valor > 0) NOT VALID;
    END IF;

    BEGIN
        ALTER TABLE transacoes VALIDATE CONSTRAINT ck_transacao_natureza;
    EXCEPTION WHEN check_violation THEN
        RAISE WARNING 'V12: transacoes com natureza fora do dominio; ck_transacao_natureza barra linhas novas e segue NOT VALID ate a limpeza';
    END;

    ALTER TABLE cobrancas VALIDATE CONSTRAINT ck_cobranca_tipo;
    ALTER TABLE cobrancas VALIDATE CONSTRAINT ck_cobranca_status;
    ALTER TABLE cobrancas VALIDATE CONSTRAINT ck_cobranca_valor;
END $$;

-- ── 5. Chave estrangeira da tabela nova ─────────────────────────────────────
-- Mesmo criterio da V11: integridade no banco, ON DELETE RESTRICT, e a tabela
-- nasce vazia entao a FK ja nasce validada. transacoes.operacao_id fica de
-- fora de proposito: e um agrupamento logico, nao referencia a tabela nenhuma.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cobranca_usuario') THEN
        ALTER TABLE cobrancas ADD CONSTRAINT fk_cobranca_usuario
            FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE RESTRICT;
    END IF;
END $$;
