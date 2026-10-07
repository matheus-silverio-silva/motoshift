-- ============================================================================
--  V25 — Lançamentos gerenciais: o que o usuário informa para a DRE (SCRUM-47).
--
--  O QUE FALTAVA. O ledger registra só o dinheiro que passa pela carteira. Para
--  o entregador, "ganhos" era faturamento bruto: combustível, manutenção, o DAS
--  do MEI e os custos fixos não apareciam em lugar nenhum, e o app não sabia
--  dizer se ele teve lucro. O lojista via quanto gastou com entregas, mas não
--  quanto elas renderam. Esta tabela guarda o que falta para a conta fechar:
--  custos e receitas que aconteceram FORA da plataforma e que a pessoa informa.
--
--  O QUE ESTA TABELA NÃO É. Não é extrato. Um lançamento gerencial não move
--  saldo, não entra em `transacoes`, não gera documento fiscal e não participa
--  das invariantes do ledger: a plataforma não viu esse dinheiro passar, só
--  ouviu falar dele. Misturar os dois faria o "carteira = extrato" depender de
--  um número que alguém digitou.
--
--  SEM COLUNA "TIPO". Se é receita ou custo, e em que linha da DRE entra, sai
--  da categoria (enum CategoriaLancamento: cada uma sabe o papel e o grupo). O
--  valor é sempre positivo; o sinal é do grupo.
--
--  REGIME DE CAIXA. `data` é o dia em que o dinheiro saiu ou entrou — o mesmo
--  critério do informe anual, que conta o pagamento pelo dia em que foi
--  creditado.
--
--  RECORRÊNCIA. `recorrente = true` é uma regra, não uma linha por mês: vale
--  uma vez por mês, no dia do mês de `data` (ou no último dia, se o mês for
--  mais curto), de `data` até `recorrente_ate` — ou sem fim. A DRE conta as
--  ocorrências que caem no período. Gravar uma linha por mês obrigaria a criar
--  linhas no futuro ou a rodar um job para inventá-las.
--
--  FKs: ON DELETE RESTRICT, como as da V11. O reset da massa apaga os
--  lançamentos das contas da massa e solta o `turno_id` dos demais.
--
--  ROLLBACK:
--    DROP TABLE lancamentos_gerenciais;
-- ============================================================================

CREATE TABLE IF NOT EXISTS lancamentos_gerenciais (
    id              BIGSERIAL PRIMARY KEY,

    usuario_id      BIGINT        NOT NULL,
    categoria       VARCHAR(40)   NOT NULL,
    valor           NUMERIC(12,2) NOT NULL,
    data            DATE          NOT NULL,
    recorrente      BOOLEAN       NOT NULL DEFAULT false,
    recorrente_ate  DATE,
    turno_id        BIGINT,
    km              NUMERIC(8,1),
    descricao       VARCHAR(200),
    criado_em       TIMESTAMP(6)  NOT NULL,
    atualizado_em   TIMESTAMP(6)  NOT NULL,

    CONSTRAINT fk_lancamento_gerencial_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE RESTRICT,
    CONSTRAINT fk_lancamento_gerencial_turno
        FOREIGN KEY (turno_id) REFERENCES turnos (id) ON DELETE RESTRICT,

    -- A lista do enum CategoriaLancamento. Categoria nova entra aqui por
    -- migração, como os tipos de transação.
    CONSTRAINT ck_lancamento_gerencial_categoria CHECK (categoria IN (
        'combustivel', 'manutencao', 'das_mei', 'celular_internet', 'seguro',
        'parcela_ou_aluguel_veiculo', 'outra_despesa_entregador',
        'taxa_de_entrega_cobrada', 'entrega_fora_do_app', 'outra_despesa_entrega')),
    CONSTRAINT ck_lancamento_gerencial_valor CHECK (valor > 0),
    CONSTRAINT ck_lancamento_gerencial_km CHECK (km IS NULL OR km > 0),
    -- "Até quando" só faz sentido para o que se repete, e nunca antes do começo.
    CONSTRAINT ck_lancamento_gerencial_recorrencia CHECK (
        recorrente_ate IS NULL OR (recorrente AND recorrente_ate >= data))
);

-- A consulta da DRE e da lista: "os lançamentos deste usuário neste período".
CREATE INDEX IF NOT EXISTS ix_lancamento_gerencial_usuario_data
    ON lancamentos_gerenciais (usuario_id, data);
