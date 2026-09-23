# Prompts para o Claude Code — MotoShift

Dois prompts prontos para colar. O primeiro é mecânico (2 minutos). O segundo é a
implementação do sistema de pagamentos e é grande — leia as **decisões já tomadas**
antes de disparar, porque elas estão embutidas no prompt.

---

# Prompt 1 — Push e limpeza

> **Contexto:** os três commits já existem localmente na branch `refactor/p0-jira`.
> Não há nada a commitar. Este prompt só publica e limpa.

```text
Estou no repositório MotoShift em C:\Projetos\stitch_log_stica_urbana_agendada.

A branch refactor/p0-jira tem 3 commits locais prontos que ainda não foram publicados:

  5a1e897  chore: adiciona .gitattributes e normaliza fim de linha
  8c54d6d  docs: plano da refatoracao P0 e patch correspondente
  f0663a9  refactor(backend): destrava SCRUM-17/18/19/20 no modelo de dados

Faça o seguinte, nesta ordem:

1. Confirme que o working tree está limpo (`git status`). Se houver qualquer
   arquivo modificado, PARE e me mostre antes de continuar — não commite nada
   novo por conta própria.

2. Apague os arquivos de lock órfãos que sobraram em .git/. São arquivos vazios
   e inertes, criados porque um processo anterior não conseguiu removê-los:
     .git\index.lock.stale-claude
     .git\lock-stale-*
     .git\zz-*
   Confirme que .git\index.lock e .git\HEAD.lock NÃO existem depois disso.

3. Publique a branch:
     git push -u origin refactor/p0-jira

4. Abra um Pull Request para a branch principal com o gh CLI. Título:
     refactor(backend): destrava SCRUM-17/18/19/20 no modelo de dados
   Na descrição, resuma os 3 commits e inclua o checklist de verificação que
   está em docs/refatoracao-p0/PLANO-REFATORACAO-P0.md (seção "Checklist de
   verificação"), para quem revisar conseguir testar.

5. Rode `mvn -f backend/pom.xml clean compile` e me diga o resultado. Esse build
   completo ainda não foi executado nenhuma vez — a refatoração foi verificada
   só com javac contra stubs das anotações. Se falhar, corrija os erros de
   compilação e faça um commit adicional antes de abrir o PR.
```

---

# Prompt 2 — Pagamentos com saldo em carteira

## Decisões já tomadas

Elas estão embutidas no prompt. Se mudar de ideia em alguma, edite o prompt antes de colar.

| Decisão | Escolha |
|---|---|
| Quando o dinheiro sai do lojista | **Reserva na publicação do turno.** O valor fica bloqueado quando o turno é publicado e só troca de mãos na finalização |
| Recarga | **Gateway simulado** atrás de uma interface, pronto para trocar por Mercado Pago/Stripe |
| Tipo do dinheiro | **Migrar para `BigDecimal`** antes de automatizar |

## Três coisas para você saber antes

**1. A migração `Double` → `BigDecimal` não é automática.** Com `ddl-auto=update`, o
Hibernate **não altera o tipo de uma coluna existente**. As colunas continuam
`double precision` no Postgres e o Hibernate mapeia `BigDecimal` em cima — funciona,
mas a garantia de precisão fica só no Java, não no banco. Por isso o prompt manda
adotar Flyway agora. É o momento certo: você vai mexer no schema de dinheiro de
qualquer jeito.

**2. `Carteira` hoje é só de motoboy** (`motoboyId` com `unique`). Vai virar carteira de
qualquer usuário. Renomear coluna com `ddl-auto=update` **cria uma coluna nova e
abandona a antiga com os dados** — por isso o prompt manda migrar com backfill, não
renomear.

**3. Guardar saldo de terceiros não é só código.** No Brasil, intermediar e custodiar
dinheiro de usuários pode caracterizar arranjo de pagamento sujeito a regras do Banco
Central. Para um TCC com gateway simulado isso é irrelevante — é uma simulação. Se um
dia for para produção com dinheiro real, isso precisa de olhar jurídico antes, e o
caminho comum é usar um provedor que assume esse papel (split de pagamento) em vez de
manter saldo próprio.

## O prompt

```text
Contexto: MotoShift, em C:\Projetos\stitch_log_stica_urbana_agendada.
Backend Spring Boot 3.3.6 / Java 17 em backend/, app Flutter em Motoshift/.
Produção é PostgreSQL no Railway com ddl-auto=update; dev é H2 create-drop.

Antes de escrever qualquer código, leia estes arquivos para entender o estado atual:
  backend/src/main/java/com/motoshift/entity/{Carteira,Transacao,Turno,TurnoInscricao}.java
  backend/src/main/java/com/motoshift/service/{CarteiraService,TurnoService}.java
  backend/src/main/java/com/motoshift/controller/CarteiraController.java
  docs/refatoracao-p0/PLANO-REFATORACAO-P0.md

OBJETIVO
Substituir a confirmação manual dupla de pagamento por liquidação automática via
saldo em carteira. O lojista recarrega saldo no app; ao publicar um turno o valor é
reservado; ao finalizar, o dinheiro vai automaticamente para a carteira do motoboy.
Ninguém confirma nada à mão.

Trabalhe em etapas e PARE ao fim de cada uma para eu revisar. Não faça tudo de uma vez.

────────────────────────────────────────────────────────────
ETAPA 1 — Flyway e migração do tipo do dinheiro
────────────────────────────────────────────────────────────
1. Adicione flyway-core e flyway-database-postgresql ao pom.xml.
   Configure spring.flyway.enabled=true e mude ddl-auto para "validate" em
   application-prod.properties. Mantenha H2/create-drop em dev.
2. Crie V1__baseline.sql refletindo o schema ATUAL (gere com
   `mvn spring-boot:run` em dev + script do Hibernate, ou escreva à mão a partir
   das entidades). Use `flyway.baseline-on-migrate=true` para o banco existente
   do Railway não quebrar.
3. Crie V2__dinheiro_para_numeric.sql:
     ALTER TABLE carteiras   ALTER COLUMN saldo_atual     TYPE NUMERIC(12,2);
     ALTER TABLE carteiras   ALTER COLUMN ganhos_mensais  TYPE NUMERIC(12,2);
     ALTER TABLE transacoes  ALTER COLUMN valor           TYPE NUMERIC(12,2);
     ALTER TABLE turnos      ALTER COLUMN valor_estimado  TYPE NUMERIC(12,2);
4. Troque Double por BigDecimal nessas entidades e propague por
   CarteiraService, TurnoService, DashboardController, RelatorioController e os
   DTOs. Use BigDecimal.ZERO como default, nunca null. Compare com compareTo,
   nunca com equals. Some com add/subtract. Arredonde com
   setScale(2, RoundingMode.HALF_UP) apenas na borda de saída.
5. Rode `mvn clean compile` e corrija tudo até compilar.

PARE. Me mostre o diff.

────────────────────────────────────────────────────────────
ETAPA 2 — Carteira de qualquer usuário, com saldo bloqueado
────────────────────────────────────────────────────────────
1. Em Carteira, adicione (NÃO renomeie nada — renomear com ddl-auto perde dados):
     usuarioId (Long, unique)      -- passa a ser a chave; motoboyId vira legado
     saldoBloqueado (NUMERIC(12,2), default 0)  -- reservas de turnos publicados
     @Version Long versao          -- trava otimista, obrigatória para dinheiro
   Renomeie o CAMPO Java saldoAtual para saldoDisponivel mantendo
   @Column(name = "saldo_atual") para não mexer no banco.
2. Migração V3__carteira_usuario.sql: adiciona as colunas e faz
     UPDATE carteiras SET usuario_id = motoboy_id WHERE usuario_id IS NULL;
   Mantenha motoboyId na entidade, marcado @Deprecated, por enquanto.
3. Crie carteira automaticamente no cadastro de QUALQUER usuário (hoje só motoboy
   tem). Em AuthService, ao registrar, crie a Carteira com saldo zero.
4. Em Transacao, adicione:
     usuarioId (Long)          -- dono da transação; motoboyId vira legado
     contraparteId (Long)      -- o outro lado (lojista <-> motoboy)
     idempotencyKey (String, unique, nullable)
   Amplie o comentário de tipo para:
     recarga | reserva | liberacao_reserva | pagamento_enviado
     | pagamento_recebido | saque | bonus | estorno
   E o de status para: pendente | concluido | falhou | estornado
5. REMOVA o campo ganhosMensais da Carteira. Ele nunca é resetado — só incrementa —
   e o gráfico do CarteiraService já calcula ganho por mês a partir de Transacao.
   Substitua os usos por uma consulta sobre Transacao no mês corrente.

PARE. Me mostre o diff.

────────────────────────────────────────────────────────────
ETAPA 3 — Operações de carteira (o núcleo)
────────────────────────────────────────────────────────────
Crie CarteiraOperacaoService. TODOS os métodos @Transactional, TODOS idempotentes,
TODOS registrando Transacao. Nenhum outro service pode mexer em saldo direto.

  creditar(usuarioId, valor, tipo, descricao, idempotencyKey)
      Se já existe Transacao com essa idempotencyKey, retorna sem fazer nada.

  reservar(lojistaId, turnoId, valor)
      saldoDisponivel -= valor; saldoBloqueado += valor
      Se saldoDisponivel < valor, lança ResponseStatusException(PAYMENT_REQUIRED)
      com mensagem dizendo QUANTO falta. Registra Transacao(tipo=reserva).

  liberarReserva(lojistaId, turnoId)
      saldoBloqueado -> saldoDisponivel. Idempotente por (turnoId, tipo).

  liquidar(lojistaId, motoboyId, turnoId, valor)
      Debita saldoBloqueado do lojista, credita saldoDisponivel do motoboy.
      Gera DUAS Transacoes: pagamento_enviado (lojista) e pagamento_recebido
      (motoboy), com contraparteId cruzado e idempotencyKey
      "turno-{turnoId}-motoboy-{motoboyId}".

Regras invioláveis, escreva teste para cada uma:
  - Saldo nunca fica negativo. Nem disponível, nem bloqueado.
  - Toda alteração de saldo tem uma Transacao correspondente.
  - Chamar a mesma operação duas vezes com a mesma chave não move dinheiro duas vezes.
  - Em OptimisticLockException, tente de novo até 3 vezes com backoff curto.

PARE. Me mostre o diff e os testes passando.

────────────────────────────────────────────────────────────
ETAPA 4 — Recarga com gateway simulado
────────────────────────────────────────────────────────────
1. Interface PagamentoGateway:
     CobrancaCriada criar(BigDecimal valor, String metodo, Long usuarioId, String chave)
     StatusCobranca consultar(String gatewayId)
   metodo: "pix" | "cartao".
2. Implementação GatewayFake, ativada por
   `motoshift.pagamento.gateway=fake` (default). Gera um id, devolve um
   payload Pix copia-e-cola fictício e aprova depois de N segundos
   (`motoshift.pagamento.fake.delay-segundos=5`). NÃO chame API externa nenhuma.
3. Entidade Recarga: id, usuarioId, valor, metodo, status
   (criada|aguardando|aprovada|expirada|falhou), gatewayId (unique),
   payloadPix, criadoEm, aprovadoEm, expiraEm (criadoEm + 30 min).
4. Endpoints:
     POST /api/carteira/recarga    {usuarioId, valor, metodo} -> {recargaId, payloadPix, status}
     GET  /api/carteira/recarga/{id}  -> status (o app faz polling)
     POST /api/pagamentos/webhook  -> confirma; é por aqui que o gateway real vai entrar
   Valor mínimo de recarga R$ 10,00, máximo R$ 5.000,00.
5. Ao aprovar: creditar() com idempotencyKey = gatewayId. Um webhook repetido
   NÃO pode creditar duas vezes — escreva teste para isso.
6. Job agendado marcando como "expirada" as recargas passadas de expiraEm.
   Siga o padrão de TurnoExpiracaoService, que já existe.

PARE. Me mostre o diff e os testes passando.

────────────────────────────────────────────────────────────
ETAPA 5 — Ligar no fluxo de turno e remover a confirmação manual
────────────────────────────────────────────────────────────
Em TurnoService:

  criar()      Calcula total = valorEstimado * vagas. Chama reservar().
               Se faltar saldo, devolve 402 com quanto falta, e o turno NÃO é criado.
  aceitar()    Não mexe em dinheiro — já está reservado.
  finalizar()  Para cada inscrição ativa, chama liquidar(). Marca o turno e as
               inscrições como pagamentoStatus="pago" direto. Se um turno tem menos
               inscritos que vagas, libera a reserva das vagas não preenchidas.
  cancelar()   Chama liberarReserva(). A penalidade de score continua como está.

Em TurnoExpiracaoService (já existe): turno que vira "expirado" também libera a
reserva. Turno que vira "aceito" por início parcial libera a reserva das vagas
não preenchidas.

REMOVER, com cuidado por causa de dados legados em produção:
  - Os métodos confirmarPagamentoLojista e confirmarRecebimentoMotoboy.
  - Os endpoints PUT /{id}/confirmar-pagamento-lojista e
    PUT /{id}/confirmar-recebimento-motoboy: mantenha-os por UMA release
    devolvendo 410 GONE com mensagem explicando que o pagamento agora é
    automático, em vez de sumir e quebrar app antigo em uso.
  - NÃO derrube as colunas lojistaConfirmouEm / motoboyConfirmouEm ainda. Deixe
    na entidade, sem uso, para não perder histórico dos turnos antigos.

Turnos que já estão finalizados e pendentes de confirmação quando isso subir:
escreva um script de migração que os liquida ou os marca como "pago_legado".
Me pergunte qual antes de decidir.

Notificações (NotificacaoService já existe, use criar/criarUnica):
  recarga aprovada | saldo insuficiente ao publicar | pagamento recebido
  | reserva liberada por cancelamento

PARE. Me mostre o diff e os testes passando.

────────────────────────────────────────────────────────────
ETAPA 6 — App Flutter
────────────────────────────────────────────────────────────
  - Tela de recarga: valor, método, Pix copia-e-cola, polling do status.
  - Saldo do lojista visível no dashboard, separando disponível de bloqueado.
  - Ao publicar turno com saldo insuficiente: mensagem clara com o valor que falta
    e atalho para a recarga.
  - Extrato unificado a partir de Transacao, com rótulo por tipo.
  - Remover das telas os botões de confirmar pagamento e confirmar recebimento.

────────────────────────────────────────────────────────────
REGRAS GERAIS
────────────────────────────────────────────────────────────
- Um commit por etapa, mensagem em português, escopo convencional.
- Nada de dinheiro em Double. Nada de saldo alterado fora de CarteiraOperacaoService.
- Rode `mvn -f backend/pom.xml clean test` ao fim de cada etapa.
- Se precisar decidir algo de produto que não está aqui, PERGUNTE em vez de assumir.
- O gateway é simulado. Não escreva nada que dê a entender que processa dinheiro
  de verdade, nem na UI nem nos comentários.
```

---

## Como eu tocaria isso

As etapas 1 e 2 são as chatas e as que mais quebram coisa — são migração de tipo e de
schema, com pouco retorno visível. Valem um PR só delas, mergeado antes de começar a
3. Da 3 em diante o risco cai bastante, porque tudo passa a ser código novo atrás de
uma interface.

Se o prazo apertar, a ordem de corte é: etapa 6 vira o mínimo (só saldo e recarga),
e o extrato unificado fica para depois.
