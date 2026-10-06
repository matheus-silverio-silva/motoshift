-- ============================================================================
--  V21 — A inscrição ganha o status 'faltou', e o domínio do status vai para
--        o banco.
--
--  O QUE MUDOU NA REGRA. Finalizar pagava toda inscrição aceita, com ou sem
--  check-in: o entregador aceitava um turno de amanhã, tocava "Finalizar" e
--  recebia na hora. Agora finalizar exige que o turno tenha começado e que
--  alguém tenha feito check-in, e só a inscrição com check-in é paga
--  (finalizado). A inscrição aceita e sem check-in vira 'faltou': não recebe,
--  e a parte dela volta ao lojista na mesma liberacao_reserva (motivo "sobra")
--  das vagas que ninguém preencheu.
--
--  O QUE ESTA MIGRAÇÃO FAZ. turno_inscricoes.status é VARCHAR sem CHECK desde
--  a baseline — quem guardava o domínio era só o enum StatusInscricao. Aqui o
--  banco passa a recusar valor fora dele, como já faz com transacoes.tipo
--  (V10). Nenhuma linha é alterada: 'faltou' só passa a existir daqui em
--  diante, escrito pela finalização.
--
--  NOT VALID + VALIDATE, como na V10: o CHECK barra linha nova na hora; se
--  existir linha antiga com um status que ninguém conhece, a migração segue
--  com WARNING e a restrição fica NOT VALID até a limpeza, em vez de derrubar
--  o deploy.
--
--  ROLLBACK:
--    UPDATE turno_inscricoes SET status = 'cancelado' WHERE status = 'faltou';
--    ALTER TABLE turno_inscricoes DROP CONSTRAINT ck_inscricao_status;
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_inscricao_status') THEN
        ALTER TABLE turno_inscricoes ADD CONSTRAINT ck_inscricao_status
            CHECK (status IN ('aceito', 'finalizado', 'faltou', 'cancelado')) NOT VALID;
    END IF;

    BEGIN
        ALTER TABLE turno_inscricoes VALIDATE CONSTRAINT ck_inscricao_status;
    EXCEPTION WHEN check_violation THEN
        RAISE WARNING 'V21: turno_inscricoes com status fora do dominio; ck_inscricao_status barra linhas novas e segue NOT VALID ate a limpeza';
    END;
END $$;
