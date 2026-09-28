-- ============================================================================
--  V20 — ADITIVA: a NFS-e ganha a chave de acesso do padrão nacional.
--
--  O QUE ENTRA. notas_fiscais.chave_acesso — os 50 dígitos que o DANFSe (o
--  documento auxiliar da NFS-e, leiaute da NT SE/CGNFS-e nº 008/2026) mostra
--  no topo: município IBGE, ambiente gerador, inscrição federal do emitente,
--  número da nota, ano/mês da emissão, código numérico e DV. SIMULADA, como
--  a nota inteira — ver docs/financeiro/FISCAL.md e ChaveDeAcessoNfse.java.
--
--  Gravada na emissão, e não calculada na leitura, pelo mesmo motivo da
--  competência na V14: a chave leva o município do prestador, e mudar a
--  cidade no perfil depois não pode mudar um documento já emitido.
--
--  SEM BACKFILL. As notas anteriores ficam com a coluna nula e ganham, na
--  leitura, uma chave derivada pela mesma regra (LeiauteDanfse.chaveDe). O
--  cálculo usa módulo 11 e SHA-256 — trazê-lo para SQL seria duplicar a regra
--  num lugar onde ninguém a testa.
--
--  UNICIDADE: índice único parcial, como o de transacao_id na V14 — duas
--  notas com a mesma chave seriam o mesmo documento duas vezes.
--
--  ROLLBACK:
--    DROP INDEX uk_nota_chave_acesso;
--    ALTER TABLE notas_fiscais DROP COLUMN chave_acesso;
-- ============================================================================

ALTER TABLE notas_fiscais ADD COLUMN IF NOT EXISTS chave_acesso VARCHAR(50);

CREATE UNIQUE INDEX IF NOT EXISTS uk_nota_chave_acesso
    ON notas_fiscais (chave_acesso) WHERE chave_acesso IS NOT NULL;
