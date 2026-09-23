# Prompt — reset leve do banco com massa atualizada

Cole o bloco abaixo no Claude Code, **com a branch `main` atualizada e o working tree
limpo**. O prompt é autocontido: descreve o estado atual, o alvo e o que não pode acontecer.

---

```
Contexto do repositório
-----------------------
MotoShift, monorepo em C:\Projetos\stitch_log_stica_urbana_agendada.
- backend/  → Spring Boot 3.3.6, Java 17. Dev = H2 em memória com ddl-auto=create-drop
              e Flyway DESLIGADO. Prod = PostgreSQL no Railway com ddl-auto=validate e
              Flyway ligado (migrações V1..V7, baseline-on-migrate).
- Motoshift/ → app Flutter.
- Produção no Railway: projeto "MotoShift", serviços Front-End, Back-End e Postgres,
  ambiente production. O backend sobe com SPRING_PROFILES_ACTIVE=prod.

O problema
----------
Toda a massa de demonstração vive em backend/src/main/java/com/motoshift/config/DataInitializer.java,
que é @Profile("!prod") e só roda "if (usuarioRepo.count() == 0)". Consequências:

1. Em produção ela NUNCA roda. O banco do Railway tem o que foi cadastrado à mão, com
   datas que envelheceram: turnos "abertos" cujo início já passou, carteiras e extratos
   parados, notificações antigas. É o banco que aparece numa demonstração ao vivo.
2. Em desenvolvimento ela só roda com o banco vazio, então não há como regerar a massa
   sem derrubar tudo.
3. As datas do seed são relativas a LocalDateTime.now() (bom), mas, uma vez gravadas,
   nada as atualiza.

O que eu quero
--------------
Um "reset leve": reconstruir a massa de demonstração com datas ancoradas em AGORA,
SEM tocar no schema, nas migrações nem no histórico do Flyway, e usando o MESMO código
de seed em desenvolvimento e em produção.

Trabalho a fazer
----------------
1. Extrair a massa do DataInitializer para um serviço próprio — sugestão:
   config/MassaDemonstracao.java — com dois métodos públicos:
     - popular()  → cria a massa (o que o DataInitializer faz hoje)
     - resetar()  → limpa a massa anterior e chama popular()
   O DataInitializer passa a ser só o gatilho de dev e continua @Profile("!prod").

2. resetar() limpa APENAS a massa de demonstração, não o banco inteiro:
     - identifica as contas de demonstração pelo sufixo de e-mail "@teste.com"
       (constante única, não string espalhada);
     - apaga, nesta ordem, tudo que pertence a elas: notas_fiscais, avaliacoes,
       transacoes, turno_inscricoes, notificacoes, turnos, carteiras, usuarios;
     - contas reais cadastradas por terceiros e o que pertence a elas ficam intactas
       (é isso que faz o reset ser "leve");
     - tudo numa transação só; se qualquer passo falhar, nada é apagado;
     - ao final, loga via SLF4J um resumo por tabela (quantos apagados, quantos criados).

3. Acionamento, com trava explícita:
     - dev: continua automático quando o banco está vazio (comportamento atual);
     - qualquer ambiente, inclusive prod: roda somente se a variável de ambiente
       MOTOSHIFT_SEED_RESET tiver exatamente o valor "confirmo". Qualquer outro valor,
       ou variável ausente, não executa nada e não loga erro;
     - o componente que lê essa variável NÃO pode ser @Profile("!prod") — ele é
       justamente o caminho de produção. Mas o valor da trava é a única porta:
       sem ele, o boot em prod é idêntico ao de hoje;
     - depois de rodar, loga em WARN que a variável deve ser removida.

4. Datas: toda data da massa é derivada de LocalDateTime.now() no momento da execução.
   Nada de data fixa em código. Confira que a matriz de cenários continua coerente
   depois do reset:
     - turnos ABERTOS começando daqui a 3h, 5h, amanhã de manhã, amanhã à noite e
       depois de amanhã;
     - um turno ACEITO em andamento (começou há pouco) e um ACEITO para amanhã;
     - concluídos PAGOS com as duas avaliações, com só uma avaliação e sem nenhuma;
     - finalizados com pagamento PENDENTE nas quatro combinações de quem já confirmou;
     - dois cancelados (um deles tardio, para o score do Thiago fazer sentido);
     - notas fiscais emitidas só para parte dos concluídos, para a tela abrir com as
       duas metades preenchidas (é o que o seed já faz hoje);
     - carteiras com saldo e extrato compatíveis com as transações criadas;
     - notificações recentes o bastante para a tela não abrir vazia.

5. Senhas sempre pelo PasswordEncoder (a massa continua com "senha123"). Nenhum hash
   escrito à mão no código.

6. Sequences: depois de apagar as linhas em PostgreSQL, os ids continuam de onde pararam.
   Não tente resetar as sequences — não é necessário e mexer nisso em produção é risco
   sem retorno. Se algum teste depender de id fixo, corrija o teste.

Restrições — não negociáveis
----------------------------
- NÃO criar migração Flyway para dados. Migração é schema; massa de demonstração é código.
- NÃO alterar as migrações existentes (V1..V7) nem a tabela flyway_schema_history.
- NÃO usar DROP, TRUNCATE sem WHERE, nem ddl-auto diferente do atual em nenhum perfil.
- NÃO mudar regra de negócio para acomodar a massa. Se algum cenário não for mais
  possível pelas regras atuais (ex.: turno com início a menos de 2h), gere a linha pelo
  repositório em vez de relaxar a validação do serviço — e comente por quê.
- NÃO commitar nenhuma credencial. A trava é variável de ambiente.
- A emissão das notas fiscais continua passando pelo NotaFiscalService (a massa deve usar
  a mesma conta de tributos do app), mantendo o catch que impede o seed de derrubar o boot
  — mas trocando o System.out.println por log SLF4J.

Testes que devem existir ao final
---------------------------------
- reset sem a variável MOTOSHIFT_SEED_RESET não apaga nem cria nada;
- rodar resetar() duas vezes seguidas deixa o banco no mesmo estado (idempotência);
- resetar() não toca em um usuário cujo e-mail não termina em "@teste.com", nem nos
  turnos/transações/avaliações dele;
- todas as datas da massa recém-criada são posteriores/anteriores a now() conforme o
  cenário — nada de data fixa.
Rode `./mvnw -B test` em backend/ e mostre o resultado.

Entregáveis
-----------
- Branch nova a partir de main (ex.: chore/reset-massa-demo), commits pequenos e em
  português, no estilo do repositório (mensagem explicando o porquê, não o quê).
- Um trecho de README (ou docs/) explicando o procedimento em produção:
    1. setar MOTOSHIFT_SEED_RESET=confirmo no serviço Back-End do Railway
    2. redeploy
    3. conferir o resumo no log
    4. REMOVER a variável
  Deixe explícito que o passo 4 não é opcional.
- Ao final, me diga o que ficou de fora e o que você mudaria numa segunda passada.

Antes de escrever código, leia DataInitializer.java, NotaFiscalService.java,
PagamentoTurnoService.java e as migrações V5/V6/V7 — a massa precisa nascer no formato
pós-V5 (todo turno com entregador tem inscrição), senão a confirmação de pagamento
estoura 500.
```

---

## Depois que o reset estiver no ar

Dois itens da revisão ficam triviais quando não existe mais conta legada no banco e valem
o mesmo PR ou o seguinte:

1. apagar o ramo de senha em texto puro do `AuthService.senhaConfere` (e o comentário
   obsoleto em `Usuario.senha`);
2. fechar `Transacao.tipo`/`Transacao.status` em enums com converter, eliminando as listas
   `TIPOS_GANHO`/`STATUS_LIQUIDADO` de compatibilidade no `CarteiraService`.
