-- ============================================================================
--  V11 — Chaves estrangeiras.
--
--  Ate aqui toda referencia entre tabelas era um BIGINT solto. O DER chamava de
--  "FK logica", e na pratica o banco aceitava turno com lojista inexistente,
--  avaliacao de turno apagado e carteira de usuario que nao existe. Quem
--  garantia a integridade era so o codigo — e codigo novo esquece.
--
--  POR QUE FK NO BANCO E NAO @ManyToOne NAS ENTIDADES. Sao duas decisoes
--  separadas. A integridade e do banco: vale para o app, para um script de
--  manutencao e para um INSERT na mao. Ja as entidades continuam com ids
--  (Long) de proposito: o app nunca navega turno.getLojista().getCarteira(), e
--  relacionamento JPA traria carga preguicosa, N+1 escondido em getter e
--  serializacao recursiva no JSON — custo sem uso. Uma coisa nao depende da
--  outra.
--
--  ON DELETE RESTRICT. Nenhum dado de dinheiro, avaliacao ou nota fiscal some
--  em cascata porque alguem apagou um usuario. Apagar e decisao explicita, na
--  ordem certa (e o que a MassaDemonstracao.resetar() faz).
--
--  NOT VALID + VALIDATE. Uma FK valida falharia o deploy se o banco do Railway
--  tiver uma unica linha orfa de antes. NOT VALID passa a barrar referencia
--  quebrada em linha nova na hora; o VALIDATE confere as antigas e, se houver
--  orfa, a migracao segue com WARNING e aquela FK fica NOT VALID ate a limpeza.
--  Para conferir depois:
--      SELECT conname FROM pg_constraint WHERE contype = 'f' AND NOT convalidated;
--
--  DE FORA, DE PROPOSITO:
--    - carteiras.motoboy_id e transacoes.motoboy_id: colunas legadas, ninguem
--      mais escreve (substituidas por usuario_id na V4);
--    - notificacoes.referencia_id: aponta para turno, avaliacao ou nota fiscal
--      conforme referencia_tipo. Referencia polimorfica nao cabe numa FK.
--
--  INDICES. O PostgreSQL nao indexa a coluna da FK sozinho, e sem indice cada
--  DELETE na tabela referenciada varre a filha inteira para conferir. As
--  colunas de FK ja indexadas pelas migracoes anteriores ficam como estao; as
--  duas que sao consultadas pelo app e nao tinham indice proprio ganham um.
--
--  ROLLBACK: ALTER TABLE <tabela> DROP CONSTRAINT <fk_...> para cada linha da
--            lista abaixo; DROP INDEX ix_inscricao_motoboy, ix_avaliacao_avaliador.
-- ============================================================================

CREATE INDEX IF NOT EXISTS ix_inscricao_motoboy   ON turno_inscricoes (motoboy_id, status);
CREATE INDEX IF NOT EXISTS ix_avaliacao_avaliador ON avaliacoes (avaliador_id);

DO $$
DECLARE
    fk RECORD;
BEGIN
    FOR fk IN
        SELECT * FROM (VALUES
            -- tabela            nome da restricao                  coluna            referencia
            ('turnos',           'fk_turno_lojista',                'lojist_id',      'usuarios'),
            ('turnos',           'fk_turno_motoboy',                'motoboy_id',     'usuarios'),
            ('turno_inscricoes', 'fk_inscricao_turno',              'turno_id',       'turnos'),
            ('turno_inscricoes', 'fk_inscricao_motoboy',            'motoboy_id',     'usuarios'),
            ('carteiras',        'fk_carteira_usuario',             'usuario_id',     'usuarios'),
            ('transacoes',       'fk_transacao_usuario',            'usuario_id',     'usuarios'),
            ('transacoes',       'fk_transacao_contraparte',        'contraparte_id', 'usuarios'),
            ('transacoes',       'fk_transacao_turno',              'turno_id',       'turnos'),
            ('avaliacoes',       'fk_avaliacao_turno',              'turno_id',       'turnos'),
            ('avaliacoes',       'fk_avaliacao_avaliador',          'avaliador_id',   'usuarios'),
            ('avaliacoes',       'fk_avaliacao_avaliado',           'avaliado_id',    'usuarios'),
            ('notificacoes',     'fk_notificacao_usuario',          'usuario_id',     'usuarios'),
            ('notas_fiscais',    'fk_nota_turno',                   'turno_id',       'turnos'),
            ('notas_fiscais',    'fk_nota_prestador',               'prestador_id',   'usuarios'),
            ('notas_fiscais',    'fk_nota_tomador',                 'tomador_id',     'usuarios'),
            ('notas_fiscais',    'fk_nota_emitida_por',             'emitida_por_id', 'usuarios')
        ) AS lista (tabela, nome, coluna, referencia)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = fk.nome) THEN
            EXECUTE format(
                'ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I (id) '
                || 'ON DELETE RESTRICT NOT VALID',
                fk.tabela, fk.nome, fk.coluna, fk.referencia);
        END IF;

        BEGIN
            EXECUTE format('ALTER TABLE %I VALIDATE CONSTRAINT %I', fk.tabela, fk.nome);
        EXCEPTION WHEN foreign_key_violation THEN
            RAISE WARNING 'V11: %.% tem linhas orfas; % barra linhas novas e segue NOT VALID ate a limpeza',
                fk.tabela, fk.coluna, fk.nome;
        END;
    END LOOP;
END $$;
