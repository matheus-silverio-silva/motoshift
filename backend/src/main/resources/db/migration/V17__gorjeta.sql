-- ============================================================================
--  V17 — ADITIVA: a gorjeta do lojista ao entregador.
--
--  O QUE ENTRA. O tipo 'bonus_enviado' no domínio de transacoes.tipo. A
--  gorjeta é uma transferência entre carteiras, com os dois lados no extrato,
--  como o pagamento de turno:
--
--    lado                tipo            disponível   natureza
--    lojista (paga)      bonus_enviado      -v        debito
--    entregador (recebe) bonus              +v        credito
--
--  POR QUE UM TIPO NOVO, e não 'bonus' com a natureza separando os lados. No
--  projeto, o TIPO decide a aritmética (service.ledger.Movimento) e a natureza
--  é só o sinal que a tela desenha — a V12 diz isso com todas as letras. Um
--  'bonus' que ora soma, ora subtrai, faria a conferência do ledger ler a
--  natureza para fazer conta, e o mesmo tipo teria dois deltas. É o mesmo par
--  de pagamento_enviado / pagamento_recebido. O 'bonus', que estava no CHECK
--  desde a V10 e nenhum fluxo emitia, passa a ser o lado de quem recebe.
--
--  Sem coluna nova: a gorjeta é o par de lançamentos, ligado ao turno por
--  transacoes.turno_id e ao entregador por contraparte_id. "Uma por entregador
--  por turno" é a chave de idempotência (gorjeta:turno:{t}:entregador:{e}:...),
--  que já é única desde a V10.
--
--  ROLLBACK: o CHECK volta à lista da V14 depois de apagar as linhas
--  bonus_enviado (e as bonus que formam par com elas).
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_transacao_tipo') THEN
        ALTER TABLE transacoes DROP CONSTRAINT ck_transacao_tipo;
    END IF;
    ALTER TABLE transacoes ADD CONSTRAINT ck_transacao_tipo CHECK (tipo IN (
        'recarga', 'reserva', 'liberacao_reserva', 'pagamento_enviado',
        'pagamento_recebido', 'saque', 'bonus', 'bonus_enviado', 'estorno',
        'retencao_iss', 'retencao_irrf'
    )) NOT VALID;

    BEGIN
        ALTER TABLE transacoes VALIDATE CONSTRAINT ck_transacao_tipo;
    EXCEPTION WHEN check_violation THEN
        RAISE WARNING 'V17: transacoes com tipo fora do dominio; ck_transacao_tipo barra linhas novas e segue NOT VALID ate a limpeza';
    END;
END $$;
