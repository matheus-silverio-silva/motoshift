# Revisão do MotoShift — 16/09/2026

Leitura do código em `main` (`cefbb5f`), sem alterar nenhum arquivo do projeto.

> **Atenção antes de começar:** o working tree está em
> `feat/carteira-liquidacao-automatica`, que já foi mergeada e está **3 commits
> atrás de `main`** (falta `811debe` mapa/menu/nota fiscal, `d774eaf` CI/mvnw e o
> merge `cefbb5f`). Qualquer correção daqui deve sair de `main` atualizada, senão
> nasce conflitada. Também há coisa não versionada: `docs/DER/`, `.githooks/` e
> `scripts/push_branches_jira.sh`.

Os níveis abaixo são sobre **risco de defesa e de produção**, não sobre esforço.

---

## P0 — arrumaria antes da banca

### 1. `GET /api/usuarios/{id}` entrega documento, CNH e dados pessoais de qualquer um

`UsuarioController.buscar` não faz nenhuma checagem — e o `UsuarioResponse` carrega
`documentoFederal` (CPF/CNPJ), `cnhNumero`, `cnhValidade`, `dataNascimento`, `email`,
`telefone` e `enderecoComercial`. Qualquer conta autenticada lê o perfil completo de
qualquer outra iterando ids.

A intenção declarada no comentário está certa ("perfil alheio se lê, o lojista precisa
ver quem aceitou o turno") — o que falta é o perfil **reduzido**. Sugestão: um
`PerfilPublicoResponse` (nome, foto, tipo, cidade, score, média, veículo modelo/cor)
para id ≠ token, e o response completo só para o próprio usuário.

É o achado com maior chance de virar pergunta de banca, porque LGPD é pauta óbvia num
TCC que guarda CNH e CNPJ.

### 2. Login ainda aceita senha em texto puro

`AuthService.senhaConfere` tem o ramo legado: se o hash no banco não começa com `$2a/$2b/$2y`,
ele compara **em texto puro** e migra. A justificativa original era não trancar contas
antigas do Railway — mas isso mantém vivo, no caminho crítico de autenticação, um
comparador de senha em claro.

Amarra direto com o reset de banco: **depois do reset, não existe mais conta legada** —
dá para apagar o ramo inteiro e ficar só com BCrypt.

### 3. Comentário que documenta o contrário do que o código faz

`Usuario.senha`:

```java
// Senha armazenada em texto simples apenas para ambiente de dev/H2.
// Em produção substitua por BCrypt + Spring Security.
```

Não é mais verdade (o seed e o cadastro usam `PasswordEncoder`). Um avaliador que abrir
a entidade lê "senha em texto simples" na entidade de usuário. É uma linha para apagar e
o ganho é desproporcional.

### 4. Bloqueio de login (RF01) tem os três defeitos que o JWT veio consertar

`ConcurrentHashMap<String, AttemptInfo> tentativas` em memória:

- some a cada restart/deploy — o bloqueio não sobrevive ao ciclo do Railway;
- não vale entre instâncias — com réplica, 5 tentativas viram 5 por instância;
- **cresce sem limite**: a chave é o e-mail *informado*, não um usuário existente, então
  um laço com e-mails inventados enche a memória;
- e é chave de negação de serviço: sei seu e-mail, erro a senha 5 vezes, você fica 15 min fora.

O próprio `JwtService` documenta esse raciocínio para a sessão. O mesmo argumento vale
aqui: ou persiste as tentativas (coluna em `usuarios` ou tabela própria), ou assume por
escrito que a proteção é por instância e efêmera.

### 5. CORS em produção cai em `*` por omissão

`motoshift.cors.origins=${MOTOSHIFT_CORS_ORIGINS:*}`. Se a variável não estiver setada no
serviço Back-End, produção sobe liberando qualquer origem. Como `allowCredentials=false`,
o estrago é limitado, mas o default devia ser o oposto: sem variável, só a origem do front.

---

## P1 — modelagem e banco (o terreno das perguntas de banca)

### 6. Nenhuma foreign key, nenhuma relação JPA

Zero `@ManyToOne`/`@JoinColumn` no código e zero `FOREIGN KEY` nas migrações V1–V7. Tudo
é `Long` solto. O DER é honesto ao chamá-las de "FK lógica", mas na prática o banco aceita
turno com `lojist_id` inexistente, avaliação órfã e carteira de usuário apagado.

Duas saídas legítimas — escolher uma e sustentar:

- **V8 aditiva** com as FKs (com `ON DELETE RESTRICT`), aproveitando que o reset do banco
  vai deixar os dados consistentes;
- ou manter e ter a justificativa escrita (acoplamento, custo de migração), porque
  "por que não tem FK?" vai ser perguntado.

### 7. O DER do artigo está desatualizado

`docs/DER/DER_MotoShift.md` diz "7 tabelas" e "migrações V1 a V6". `main` já tem
`notas_fiscais` e a V7. O apêndice do artigo usa esse diagrama.

### 8. `Transacao.tipo` e `Transacao.status` continuam String livre

Turno e inscrição viraram enum com converter (`StatusTurnoConverter` etc.), mas a transação
— justamente o registro de dinheiro — segue com strings mágicas e **duas gerações convivendo**:
`"turno"`/`"pagamento_recebido"` e `"pendente"`/`"processado"`/`"concluido"`. `CarteiraService`
tem duas listas constantes só para reconciliar isso, e `PagamentoTurnoService.marcarTransacaoProcessada`
compara `"pendente"` na mão.

Depois do reset o histórico legado deixa de existir → dá para fechar em dois enums
(`TipoTransacao`, `StatusTransacao`) e apagar as listas de compatibilidade.

### 9. `idempotency_key` existe mas não é preenchida em todo caminho

O próprio `ApiExceptionHandler` admite isso ao justificar por que não usa `@Retryable`.
Ou preenche em todos os caminhos de escrita de transação, ou o campo é decoração.

---

## P2 — desempenho e escala

### 10. N+1 em praticamente toda listagem

- `TurnoMapper.toResponse` faz um `countByTurnoIdAndStatus` **por turno** — cada listagem de
  N turnos dispara N+1 queries;
- `TurnoConsultaService.listarPorMotoboy` e `TurnoService.temConflitoDeAgenda` fazem
  `findById` dentro de laço;
- `listarInscritos` busca o nome de cada inscrito individualmente;
- `NotaFiscalService.pendentes` consulta nota e chama `nomeDe()` por item.

Interessante: `NotaFiscalService.listarDoUsuario` já resolve certo (`carregarPessoas`/`carregarTurnos`
com `findAllById`). O padrão bom existe no projeto — falta aplicar nos outros pontos.

### 11. Nenhuma listagem tem paginação

`listarDisponiveis`, `listarPorLojista`, `listarPorMotoboy`, extrato da carteira, notificações:
todas devolvem tudo. Com o `Pageable` do Spring Data isso é barato e responde de véspera à
pergunta "e com 10 mil turnos?".

### 12. `CarteiraService.grafico` agrupa em memória

Carrega todas as transações do usuário e filtra mês a mês no stream. Um `GROUP BY` no
repositório resolve — e é o mesmo dado do `ganhosDoMes`, que já usa `somarPorTipoDesde`.

### 13. `cobrarFinalizacaoPendente` varre um conjunto que só cresce

O job roda a cada 5 min sobre todos os turnos ACEITO/EM_ANDAMENTO com `dataFim` no passado.
Nada tira o turno desse estado (finalizar é decisão humana, por design), então o conjunto
cresce para sempre e é reprocessado indefinidamente. O `criarUnica` evita o spam de
notificação, mas não o trabalho. Um corte por janela (ex.: só os últimos 7 dias) resolve.

### 14. Os três `@Scheduled` rodam em toda instância

Com réplica no Railway, os jobs duplicam. Hoje é inofensivo pelo `criarUnica`, mas é bom
saber a resposta se perguntarem.

---

## P3 — integração com IA

### 15. `AnthropicService` sem timeout, bloqueando a thread do servlet

`WebClient` sem `responseTimeout` + `.block()`. Se a API demorar, a thread fica presa até
o timeout padrão do cliente HTTP. Três telas chamam isso. Um `HttpClient.responseTimeout`
de ~20s (o mesmo que o app Flutter usa) fecha o buraco.

Detalhe menor: `new RuntimeException("Erro na API Anthropic (...): " + e.getResponseBodyAsString())`
joga o corpo bruto da resposta na mensagem da exceção e daí para o log.

### 16. Sem cache: cada F5 é uma chamada paga

Score, relatório do motoboy e relatório do lojista chamam a API a cada request. Um cache
curto por usuário (ex.: 15 min, ou por mês de referência no caso do relatório) corta custo
e latência sem mudar nada visível.

### 17. `ScoreService` devolve 503 mesmo tendo as métricas prontas

Todas as métricas (score, variação, classificação, eventos) são calculadas localmente antes
da chamada. Se a IA falha, o endpoint inteiro cai. Degradar — devolver os números com
`analise: null` e a tela mostrando "análise indisponível" — é mais robusto e melhor de demonstrar.

### 18. `scoreAnterior` é estimativa apresentada como dado

`scoreAtual + cancelamentosTardios * 0.5`. Sem histórico de score não dá para fazer melhor,
e o código é transparente sobre isso ("Estima o score de 30 dias atras revertendo as
penalizacoes"), mas o app e o artigo apresentam como medição. Ou rotula ("estimado"), ou
cria uma tabela `score_eventos` — que, de quebra, daria substância à tela de análise.

---

## P4 — higiene

19. `DataInitializer.emitirNota` usa `System.out.println` no catch; o resto do projeto usa SLF4J.
20. `TurnoInscricao` guarda a dupla confirmação, e o comentário de `PagamentoTurnoService`
    ainda fala em "V6 as remove num deploy posterior" — a V6 já rodou. Vale uma passada nos
    comentários que envelheceram junto com as migrações.
21. `lib/views/stubs/stub_screens.dart` e `lib/dev/shell_preview_main.dart` entram no bundle
    de produção. São pequenos, mas são código de dev publicado.
22. Duas telas passaram de 800 linhas (`meus_turnos_screen.dart`, `agendar_turno_screen.dart`).
    O padrão de quebra já existe no projeto (`historico_*` e `turnos_conteudo_desktop`) —
    é replicar.
23. Os goldens rodam só em `windows-latest` por causa da fonte. Está documentado no workflow,
    mas amarra o CI a um runner. Empacotar a fonte no teste destravaria o Ubuntu.

---

## O que já está bom (e vale dizer na defesa)

- Autorização consistente: `exigirMesmoUsuario` em dashboard, carteira, score e relatório;
  identidade sempre do JWT, nunca do corpo.
- Contrato de erro único (`ErroResponse`) valendo tanto no MVC quanto no filtro do Security.
- Dinheiro em `BigDecimal` com `@Version` na carteira, e o 409 de conflito otimista tratado
  em vez de virar 500.
- Expand/contract de verdade nas migrações V5/V6, com o motivo escrito no arquivo.
- 72 testes no backend e ~99 no app, rodando em CI a cada push.
- Os comentários explicam *por quê*, não *o quê*. É raro, e num TCC conta muito.
