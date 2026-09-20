-- ============================================================================
--  V8 — Bloqueio de login (RF01) passa a morar no banco.
--
--  Ate aqui as tentativas ficavam num ConcurrentHashMap do AuthService:
--    - sumiam a cada restart/deploy, entao o bloqueio nao sobrevivia ao Railway;
--    - cada replica contava as proprias 5 tentativas;
--    - a chave era o e-mail DIGITADO, e um laco com e-mails inventados enchia a
--      memoria sem limite.
--
--  Duas colunas na propria linha do usuario resolvem os tres: o contador existe
--  so para conta que existe e e o mesmo para qualquer instancia.
--
--  Puramente aditiva. DEFAULT 0 com NOT NULL nao reescreve a tabela no
--  PostgreSQL 11+, e as instancias da versao anterior ignoram as colunas.
--
--  ROLLBACK: ALTER TABLE usuarios DROP COLUMN tentativas_login,
--            DROP COLUMN bloqueado_ate;
-- ============================================================================

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS tentativas_login INTEGER NOT NULL DEFAULT 0;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS bloqueado_ate    TIMESTAMP(6);
