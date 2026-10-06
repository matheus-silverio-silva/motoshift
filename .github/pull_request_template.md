<!--
  Título do PR: tipo(escopo): o que muda (SCRUM-NN)
  A chave no título é o que liga o PR ao card no Jira.
-->

## Card

SCRUM-

## O que mudou

<!-- O comportamento que muda, e por quê. O "como" está no diff. -->

-

## Como testar

<!-- O caminho que um revisor segue para ver a mudança funcionando. -->

1.

## Checklist

**Testes**

- [ ] `backend\mvnw.cmd test` verde
- [ ] `flutter analyze` sem avisos
- [ ] `flutter test` verde
- [ ] A regra nova tem teste — e ele falha sem a mudança

**Goldens**

- [ ] Nenhuma tela mudou de aparência, **ou**
- [ ] Os goldens que mudaram de propósito foram regravados no Windows com Flutter 3.41.5, e a lista (com o motivo) está na mensagem do commit

**Banco**

- [ ] Sem mudança de schema, **ou**
- [ ] A mudança entrou como migração Flyway nova (nenhuma antiga foi editada), a entidade reflete a mudança e o `MigracoesPostgresTest` cobre

**Documentação**

- [ ] README, `docs/GUIA_DEFESA.md` e `docs/REQUIREMENTS.md` batem com o comportamento novo
- [ ] Comentários de classe que ficaram desatualizados foram corrigidos
- [ ] Variável de ambiente nova está na tabela do README
