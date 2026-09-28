-- ============================================================================
--  V18 — ADITIVA: os entregadores favoritos de cada loja.
--
--  O QUE ENTRA. Uma tabela nova, favoritos (lojista_id, motoboy_id,
--  criado_em). O par é a chave primária — a mesma loja não favorita o mesmo
--  entregador duas vezes, nem em corrida de dois cliques: quem barra é o
--  banco. As duas colunas apontam para usuarios (ON DELETE RESTRICT, como
--  todas as FKs da V11).
--
--  Quem é loja e quem é entregador é regra do FavoritoService (só o lojista
--  favorita, e só entregador é favoritado); o CHECK aqui só impede a conta de
--  favoritar a si mesma.
--
--  Índice (motoboy_id): "as lojas que favoritaram este entregador" — o selo
--  "Loja que já te chamou" na lista de disponíveis.
--
--  Nada existente muda: tabela nova, sem backfill.
--
--  ROLLBACK:
--    DROP TABLE favoritos;
-- ============================================================================

CREATE TABLE IF NOT EXISTS favoritos (
    lojista_id  BIGINT       NOT NULL,
    motoboy_id  BIGINT       NOT NULL,
    criado_em   TIMESTAMP(6) NOT NULL DEFAULT now(),

    CONSTRAINT pk_favoritos PRIMARY KEY (lojista_id, motoboy_id),
    CONSTRAINT fk_favorito_lojista FOREIGN KEY (lojista_id) REFERENCES usuarios (id) ON DELETE RESTRICT,
    CONSTRAINT fk_favorito_motoboy FOREIGN KEY (motoboy_id) REFERENCES usuarios (id) ON DELETE RESTRICT,
    CONSTRAINT ck_favorito_nao_a_si_mesmo CHECK (lojista_id <> motoboy_id)
);

CREATE INDEX IF NOT EXISTS ix_favorito_motoboy ON favoritos (motoboy_id);
