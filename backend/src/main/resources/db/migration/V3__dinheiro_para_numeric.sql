-- ============================================================================
--  V3 — Dinheiro sai de ponto flutuante e vira NUMERIC(12,2).
--
--  As colunas de dinheiro eram FLOAT(53) (double precision), porque as
--  entidades usavam Double. Ponto flutuante binario nao representa decimais
--  exatos: 0.1 + 0.2 nao da 0.3, e somas de saldo acumulam erro. Com a
--  liquidacao automatica via carteira isso deixa de ser aceitavel — saldo
--  precisa fechar na casa dos centavos.
--
--  NUMERIC(12,2) suporta ate 9.999.999.999,99, folga larga para o dominio.
--  A conversao de double precision para numeric usa o cast de atribuicao do
--  proprio PostgreSQL; nao precisa de USING. Valores existentes sao
--  arredondados para 2 casas.
--
--  As entidades declaram precision=12/scale=2 para que o ddl-auto=validate
--  reconheca exatamente este tipo.
-- ============================================================================

ALTER TABLE carteiras  ALTER COLUMN saldo_atual    TYPE NUMERIC(12,2);
ALTER TABLE carteiras  ALTER COLUMN ganhos_mensais TYPE NUMERIC(12,2);
ALTER TABLE transacoes ALTER COLUMN valor          TYPE NUMERIC(12,2);
ALTER TABLE turnos     ALTER COLUMN valor_estimado TYPE NUMERIC(12,2);
