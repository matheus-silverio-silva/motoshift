-- ============================================================================
--  V6 — CONTRACT: derruba a dupla confirmacao do turno.
--
--  ⚠️  NAO APLIQUE ESTA MIGRACAO NO MESMO DEPLOY DA V5.
--
--  Esta e a segunda metade do expand/contract. A V5 (deploy anterior) copiou a
--  confirmacao de cada turno legado para a sua inscricao; esta remove a origem.
--  Entre um deploy e outro tem de haver uma confirmacao humana de que o
--  backfill rodou — rode a consulta comentada no fim da V5 e exija ZERO nas
--  duas colunas antes de deixar esta migracao subir.
--
--  POR QUE DUAS MIGRACOES, E NAO UMA: enquanto a V5 sobe, ainda ha instancias
--  do backend rodando a versao ANTERIOR do codigo, que le e escreve
--  lojista_confirmou_em/motoboy_confirmou_em. Se o DROP viesse junto, essas
--  instancias comecariam a falhar no meio do deploy — e o Hibernate roda com
--  ddl-auto=validate em producao, entao a instancia antiga nem sobe com o
--  schema novo. Separando, cada deploy e compativel com o codigo dos dois
--  lados: a V5 so acrescenta, e quando a V6 chega ninguem mais usa as colunas.
--
--  ROLLBACK: um ALTER TABLE ADD COLUMN traz as colunas de volta, mas VAZIAS —
--  o dado ficou nas inscricoes. Por isso a confirmacao antes, e nao depois.
-- ============================================================================

ALTER TABLE turnos DROP COLUMN IF EXISTS lojista_confirmou_em;
ALTER TABLE turnos DROP COLUMN IF EXISTS motoboy_confirmou_em;
