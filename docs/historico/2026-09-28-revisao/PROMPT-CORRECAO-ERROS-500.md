# Prompt — erros 500 na carteira, nos relatórios e no informe fiscal

Sintoma observado em 28/09/2026, rodando localmente (backend na porta 8080,
app Flutter web), logado como entregador (usuário id 5 = Ricardo na massa).
Quebram saldo/carteira, relatórios, notas fiscais (informe anual), saque e
depósito. O console do navegador mostrou só isto (o resto é aviso do
flutter_map):

```
GET /api/carteira/resumo                                       500
GET /api/carteira/resumo?dataInicio=2026-08-30&dataFim=2026-09-28 500
GET /api/carteira/extrato?pagina=0&tamanho=20                  500
GET /api/carteira/5                                            500
GET /api/notas-fiscais/resumo?ano=2026                         500
```

Não é erro de login: 401 e 403 não aparecem. As outras telas (turnos,
dashboard, notificações, lista de notas) carregam normalmente.

**Esse prompt é independente dos outros dois:** rode-o antes deles. Se estiver
no meio de outra branch, faça commit ou stash antes.

Cole tudo abaixo da linha no Claude Code, na raiz do repositório.

---

Você vai corrigir erros 500 no backend do MotoShift (Spring Boot 3 em
`backend/`, app Flutter em `Motoshift/`). Estou no Windows: use
`backend\mvnw.cmd`, `curl` e `netstat`/PowerShell. Leia antes
`docs/financeiro/FLUXO-FINANCEIRO.md`.

## O que sabemos

- Falham, com 500, cinco chamadas feitas pelo app logado como Ricardo
  (`ricardo@teste.com` / `senha123`, id 5 na massa de dev):
  `GET /api/carteira/{id}`, `GET /api/carteira/resumo` (com e sem datas),
  `GET /api/carteira/extrato?pagina=0&tamanho=20` e
  `GET /api/notas-fiscais/resumo?ano=2026`. Saque e depósito quebram na
  mesma tela.
- O padrão aponta para o caminho de **leitura da tabela `transacoes`**: quase
  todas carregam entidades `Transacao` ou projetam `tipo`/`natureza`/`status`
  (os três com `AttributeConverter` cujo `de()` lança
  `IllegalArgumentException` para valor desconhecido). O dashboard e as telas
  de turno, que não passam por aí, funcionam. **Isso é hipótese, não
  diagnóstico.**
- Em dev o banco é H2 em memória, com `ddl-auto=create-drop` e a massa de
  `MassaDemonstracao` criada no boot. Os testes rodam em outro H2
  (`application-test.properties`) com dados próprios. Se a suíte passa e o
  app quebra, a diferença provavelmente está nos **dados da massa** ou no
  **processo que está de fato na porta 8080**.

## Passo 1 — Garantir que o backend é o código atual

Antes de qualquer coisa, confira com `netstat -ano | findstr :8080` e o PID
qual processo está na porta. Até pouco tempo o projeto tinha outras cópias
(worktrees e uma branch antiga aberta no VS Code), e um backend velho de pé
explicaria rota que não existe caindo em erro. Se houver mais de um processo
Java, me diga qual era, encerre, suba o atual com `mvnw.cmd spring-boot:run` e
só então siga.

## Passo 2 — Reproduzir e ler o stack trace

1. Suba o backend e guarde o log num arquivo
   (`mvnw.cmd spring-boot:run > backend-run.log 2>&1`, fora do git).
2. Faça login por `curl` (`POST /api/auth/login`) como Ricardo e como Cláudia
   (lojista, `claudia@teste.com`), pegue o token e chame as cinco rotas acima
   para cada um. Chame também `POST /api/carteira/saques` e
   `POST /api/carteira/recargas` com valores válidos.
3. Para cada 500, copie a exceção raiz do log (a última linha `Caused by:`) e
   me mostre, no resumo, a tabela rota → exceção → causa.

## Passo 3 — Corrigir a causa, não o sintoma

- Corrija a causa raiz. Não resolva com `try/catch` que devolve lista vazia,
  nem com um `@ExceptionHandler(Exception.class)` genérico (o
  `ApiExceptionHandler` explica por que não existe).
- Se a causa for dado inválido gerado pela massa, corrija a massa **e** a
  regra que deixou o dado entrar (o banco ou a entidade devem recusar na
  gravação, não estourar na leitura).
- Se a causa for consulta JPQL/SQL que o H2 não aceita e o PostgreSQL aceita
  (ou o contrário), reescreva de forma portável e diga no commit qual era a
  diferença.

## Passo 4 — Suspeita adicional para confirmar

`Transacao.criadoEm` está mapeado com `@Column(nullable = false, updatable = false)`,
mas `MassaDemonstracao.redatar()` faz `tx.setCriadoEm(quando)` seguido de
`transacaoRepo.save(tx)` para datar lançamentos no passado. Com
`updatable = false`, o Hibernate omite a coluna do UPDATE: é provável que
**todo o extrato da massa fique com a data do boot**, e aí o gráfico mensal,
o "ganhos do mês" e o informe anual mostram tudo num dia só. Confirme com uma
consulta direta no H2 console (`/h2-console`, `jdbc:h2:mem:motoshiftdb`). Se
confirmar, corrija sem liberar a data para o fluxo normal. Por exemplo: a
massa passa a data já no `Movimento` antes do INSERT, ou usa um UPDATE JPQL
explícito que só ela chama. Mantenha a regra de que só a massa data no
passado.

## Passo 5 — Teste de regressão

A suíte atual passou sem pegar isso. Crie um teste de integração
(`@SpringBootTest` + `MockMvc`) que:

- popula a **massa de demonstração** (`MassaDemonstracao.popular()`), e não
  dados de teste próprios;
- autentica como um entregador e como um lojista da massa;
- chama `GET /api/carteira/{id}`, `/resumo`, `/extrato`, `/fluxo` e
  `/api/notas-fiscais/resumo`, e exige 200 com corpo coerente (saldo igual ao
  da carteira, extrato com lançamentos, informe com o total do ano);
- faz um saque e uma recarga (criar + confirmar) e exige 200/201;
- se o Passo 4 confirmar, verifica que a massa tem lançamentos em mais de um
  mês.

O teste deve falhar antes da correção e passar depois. Diga no resumo que você
viu os dois estados.

## Passo 6 — Limpeza e fechamento

- No app, confirme que um 500 nessas telas mostra a mensagem de erro com
  "Tentar novamente", e não uma tela vazia ou um spinner eterno. Corrija onde
  não mostrar.
- Opcional: o console do navegador repete dezenas de vezes a dica do
  `flutter_map` sobre `flutter_map_cancellable_tile_provider`. Se a versão
  compatível com o `flutter_map` do projeto existir, adicione-a nos
  `TileLayer` (melhora o desempenho no web e tira o ruído). Se exigir subir o
  `flutter_map`, não faça: só me avise.
- Rode `backend\mvnw.cmd test` e `flutter test`, tudo verde.
- Um commit por correção, em português, sem acento, no padrão do histórico.
- Resumo final: causa raiz de cada 500, o que mudou, o que o teste novo cobre,
  e se o Passo 1 encontrou um processo antigo na porta.
