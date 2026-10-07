-- ============================================================================
--  V24 — Códigos de recuperação de senha (SCRUM-32).
--
--  O QUE FALTAVA. Quem esquecia a senha não tinha caminho: a tela "Esqueci
--  minha senha" só orientava a procurar o suporte. Agora o backend gera um
--  código de 6 dígitos, válido por 15 minutos, e o app troca a senha com ele.
--
--  O QUE ESTA TABELA GUARDA — E O QUE NÃO GUARDA.
--    * codigo_hash é o BCrypt do código, nunca o código. Seis dígitos são um
--      segredo curto: em claro, quem lesse o banco (um backup, um SELECT de
--      suporte) trocaria a senha de qualquer conta com pedido aberto. Com o
--      hash, o banco só sabe CONFERIR um código, não dizê-lo.
--    * tentativas conta quantas vezes ESTE código foi conferido. No quinto
--      erro ele deixa de valer, mesmo que o sexto palpite acerte: é o que
--      impede varrer os 1.000.000 de códigos possíveis em 15 minutos.
--    * expira_em é gravado, e não calculado na leitura: mudar o prazo no
--      código não estica nem encurta os pedidos que já existem.
--
--  UM CÓDIGO VALE POR VEZ. O backend apaga os códigos anteriores da conta ao
--  gerar um novo e ao concluir a troca. Não há UNIQUE em usuario_id porque
--  dois pedidos simultâneos são legítimos (toque duplo em "Enviar código") e
--  não devem virar erro: vale o mais recente, e a consulta ordena por id.
--
--  ON DELETE CASCADE. É a única FK do schema que apaga em cascata, e de
--  propósito: o código não é histórico de ninguém — é uma credencial de 15
--  minutos que não significa nada sem a conta. As demais FKs são RESTRICT
--  porque guardam dinheiro, turno e avaliação.
--
--  ROLLBACK:
--    DROP TABLE codigos_recuperacao_senha;
-- ============================================================================

CREATE TABLE IF NOT EXISTS codigos_recuperacao_senha (
    id           BIGSERIAL PRIMARY KEY,

    usuario_id   BIGINT       NOT NULL,
    codigo_hash  VARCHAR(100) NOT NULL,
    criado_em    TIMESTAMP(6) NOT NULL,
    expira_em    TIMESTAMP(6) NOT NULL,
    tentativas   INTEGER      NOT NULL DEFAULT 0,

    CONSTRAINT fk_codigo_recuperacao_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE,
    CONSTRAINT ck_codigo_recuperacao_tentativas CHECK (tentativas >= 0)
);

-- "O código mais recente desta conta" — a única consulta que a tabela recebe.
CREATE INDEX IF NOT EXISTS ix_codigo_recuperacao_usuario
    ON codigos_recuperacao_senha (usuario_id, id);
