-- ============================================================================
--  V15 — ADITIVA: a loja passa a ter um ponto no mapa.
--
--  O QUE ESTAVA ERRADO. O turno era gravado com a coordenada do GPS de onde o
--  lojista estava publicando (a casa dele, o celular na rua) ou com o centro da
--  cidade — e com o endereço comercial da loja no texto. Pino e endereço podiam
--  apontar para lugares diferentes, e o entregador ia para o lugar errado.
--
--  O QUE ENTRA:
--    usuarios.latitude / usuarios.longitude — o ponto da loja, marcado uma vez
--    no mapa em "Dados pessoais". A publicação de turno parte dele (depois do
--    GPS e da cidade, nessa ordem de preferência), e o lojista ainda pode
--    ajustar o pino no turno.
--
--  Anuláveis de propósito: quem ainda não marcou a loja continua publicando
--  como antes, pelo GPS ou pela cidade. Só o lojista as preenche; o entregador
--  não tem "loja" e as colunas ficam nulas nele.
--
--  Mesmo tipo das colunas do turno (V2), FLOAT(53) = double precision.
--
--  ROLLBACK: ALTER TABLE usuarios DROP COLUMN latitude, DROP COLUMN longitude;
-- ============================================================================

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS latitude  FLOAT(53);
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS longitude FLOAT(53);
