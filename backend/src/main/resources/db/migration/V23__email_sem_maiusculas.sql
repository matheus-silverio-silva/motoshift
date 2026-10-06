-- ============================================================================
--  V23 — O e-mail deixa de diferenciar maiúsculas de minúsculas.
--
--  O DEFEITO. usuarios.email é UNIQUE, mas a comparação do PostgreSQL é exata:
--  "Claudia@Teste.com" e "claudia@teste.com" eram duas contas possíveis para a
--  mesma caixa de correio — e, do outro lado, quem se cadastrou com minúsculas
--  não entrava quando o teclado do celular punha a primeira letra em
--  maiúscula. O backend passou a normalizar o e-mail (trim + minúsculas) ao
--  gravar e ao procurar (Usuario.setEmail / AuthService); esta migração põe o
--  que já está no banco na mesma forma e fecha a regra com um índice.
--
--  1. CONFERE ANTES. Se duas contas só diferem por maiúsculas ou espaços,
--     normalizar as duas violaria a unicidade — e decidir qual delas fica
--     (ou como juntar o histórico) não é decisão de migração. Nesse caso a
--     migração FALHA, dizendo quais e-mails colidem, e nada é alterado: o
--     deploy não sobe, a versão anterior continua no ar e a correção é manual.
--  2. NORMALIZA. lower(trim(email)) nas linhas que ainda não estão assim.
--  3. FECHA. Índice único em lower(email): mesmo uma gravação que não passe
--     pelo backend não cria a segunda conta.
--
--  A restrição UNIQUE antiga (usuarios.email) fica: com tudo em minúsculas ela
--  é redundante com o índice novo, e é ela que o Hibernate espera da entidade.
--
--  ROLLBACK:
--    DROP INDEX uk_usuario_email_lower;
--    (as maiúsculas originais não voltam — e não fazem falta: e-mail não as
--     diferencia.)
-- ============================================================================

DO $$
DECLARE
    colisoes TEXT;
BEGIN
    SELECT string_agg(e || ' (' || n || ' contas)', ', ' ORDER BY e)
      INTO colisoes
      FROM (SELECT lower(trim(email)) AS e, count(*) AS n
              FROM usuarios
             GROUP BY lower(trim(email))
            HAVING count(*) > 1) d;

    IF colisoes IS NOT NULL THEN
        -- Um literal só, de propósito: o RAISE do PL/pgSQL quer o formato num
        -- literal simples.
        RAISE EXCEPTION 'V23: ha contas cujo e-mail so difere por maiusculas ou espacos: %. A migracao nao escolhe qual conta fica: resolva a mao (renomeie ou junte as contas) e rode o deploy de novo.', colisoes;
    END IF;
END $$;

UPDATE usuarios
   SET email = lower(trim(email))
 WHERE email <> lower(trim(email));

CREATE UNIQUE INDEX IF NOT EXISTS uk_usuario_email_lower ON usuarios (lower(email));
