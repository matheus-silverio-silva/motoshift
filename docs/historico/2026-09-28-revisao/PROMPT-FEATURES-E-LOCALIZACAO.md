# Prompt — localização, correções e novas features

Revisão feita em 28/09/2026 pela leitura do código de `feat/fiscal-extrato`
(`826580e`). Não rodei o app. Os achados estão no próprio prompt, em cada
fase, com arquivo e trecho.

**Ordem:** rode este prompt **depois** do `PROMPT-CLAUDE-CODE.md` (papéis,
nova massa e PDF). As duas coisas mexem na massa, nas notificações e na
exportação.

Cole tudo abaixo da linha no Claude Code, na raiz do repositório.

---

Você vai trabalhar no MotoShift (TCC; backend Spring Boot 3 em `backend/`, app
Flutter em `Motoshift/`). Estou no Windows: use `backend\mvnw.cmd` e `flutter`.
Leia antes: `README.md`, `docs/README.md`, `docs/financeiro/FLUXO-FINANCEIRO.md`,
`docs/financeiro/FISCAL.md` e `docs/ux/NAVEGACAO.md`.

## Como trabalhar

- Parta da branch em que o prompt anterior terminou
  (`feat/revisao-papeis-e-massa`) e crie `feat/localizacao-e-features`. Se
  aquela branch não existir, pare e me avise.
- Uma fase = um commit (ou poucos, se ficar grande), com mensagem em
  português, sem acento, no padrão do histórico. Ao fim de cada fase, rode
  `backend\mvnw.cmd test` e `flutter test` em `Motoshift/`, e só avance com
  tudo verde.
- Migrações Flyway: use o próximo número livre. Uma migração por fase que
  precisar dela, sempre aditiva (colunas novas anuláveis ou com default), sem
  reescrever migração existente.
- O dinheiro passa **só** pelo `LedgerService`/`Movimento`, como o resto do
  app. A massa termina passando em `ConsistenciaService.verificarConsistencia()`.
- Goldens: o CI roda em `windows-latest` com Flutter **3.41.5**. Regrave apenas
  os goldens de mudanças intencionais, nessa versão, e liste-os no commit.
- A regra de papéis do prompt anterior continua valendo: o entregador é
  prestador de serviço, o lojista é uma loja. Nenhum dos dois vê o que é do
  outro.
- Pacote novo permitido: `url_launcher`, e um pacote para salvar arquivo, se
  realmente precisar (veja a Fase 2). Nenhum outro sem me perguntar.
- Atualize README, `docs/ux/NAVEGACAO.md`, GUIA_DEFESA.md e o DER quando a fase
  mudar o que eles descrevem.
- No final, me entregue um resumo por fase: o que mudou, o que você decidiu
  sozinho, o que testou de verdade e o que não conseguiu testar.

## Fase 1 — Localização: auditoria e correção

A localização "parece bugada", mas não sei onde. Primeiro confirme ou descarte
cada suspeita abaixo **com um teste que falha antes da correção**. Depois
corrija o que for confirmado. No commit, liste as suspeitas confirmadas e as
descartadas.

Suspeitas encontradas na leitura:

1. **Publicar turno, corrida entre GPS e toque**
   (`agendar_turno_screen.dart`, `_definirPontoInicial` e `_escolherPonto`): o
   GPS responde depois e sobrescreve `_centro` mesmo que o lojista já tenha
   tocado o mapa (`_origem == escolhido`). O ponto escolhido se perde sem
   aviso.
2. **O pino não é a loja.** O turno é gravado com a coordenada do GPS de onde
   o lojista está publicando (casa, celular), ou com o centro da cidade, mas
   o texto `regiao`/`endereco` é o endereço comercial da loja. Pino e endereço
   podem apontar para lugares diferentes, e o entregador vai para o lugar
   errado. Correção proposta: o lojista guarda a coordenada da loja no
   cadastro (colunas `latitude`/`longitude` em `usuarios`, marcadas uma vez no
   mapa em "Dados pessoais"). A publicação passa a partir dela, na ordem: loja
   cadastrada, depois GPS, depois cidade. O lojista continua podendo ajustar o
   pino no turno.
3. **Publicar sem ponto confirmado.** Sem cidade conhecida e sem GPS,
   `_centro` fica em `GeoReferencia.padrao` (marco zero de Curitiba) e o turno é
   publicado lá, em silêncio. Nesse caso, exija que o lojista toque o mapa ou
   confirme o ponto antes de publicar.
4. **"Perto de mim" que não filtra** (`meus_turnos_screen.dart`,
   `_carregarDisponiveis`): se a chamada com filtros falha, o `catch (_)` chama
   `provider.carregarDisponiveis()`, que traz a lista **sem filtro**, enquanto a
   tela continua dizendo "perto de mim". Mostre o erro com opção de tentar de
   novo, nunca a lista errada.
5. **GPS sem tempo limite** (`localizacao_service.dart`): `getCurrentPosition`
   não tem `timeLimit`. No web, um aviso de permissão ignorado deixa a tela
   "buscando localização" para sempre. Coloque um tempo limite (15 s, por
   exemplo), trate como `FalhaLocalizacao.erro` com a mensagem certa e considere
   `getLastKnownPosition` como tentativa rápida em mobile.
6. **Web fora de HTTPS**: geolocalização no navegador só funciona em contexto
   seguro (HTTPS ou `localhost`). Se o app for aberto por IP da rede, falha
   sem explicar nada. Detecte e mostre uma mensagem clara.
7. **Contas de demonstração em outra cidade**: `lojista@teste.com` e
   `motoboy@teste.com` são de São Paulo, e toda a massa é de Curitiba. Na
   demonstração, "perto de mim" e o ponto inicial do mapa ficam longe de tudo.
   Mude as duas contas para Curitiba na massa, mantendo e-mail e senha.
8. **Backend**: revise `GeoUtils`, `TurnoConsultaService.disponiveisComFiltros`
   e `TurnoRepository.findAbertosNaArea`. A leitura não mostrou erro, mas
   escreva testes para os casos de borda: raio de 1 km e de 30 km, turno
   exatamente na borda, coordenadas negativas (Brasil) e turno sem coordenada.
   Confira também que `raioMaxKm` (raio de entrega do turno) e `raioKm`
   (distância até o entregador) não se confundem na tela de filtros; hoje os
   dois aparecem como "raio".
9. Confira que a distância mostrada no card, no detalhe e no pino do mapa é a
   mesma e vem do backend (`distanciaKm`), sem recálculo divergente no app.

Entregue também um roteiro curto de teste manual no README (seção de
desenvolvimento): como simular posição no Chrome (DevTools → Sensors →
Location) com coordenadas da massa, e o que deve acontecer em cada tela.

## Fase 2 — Correções rápidas

1. **Exportar planilha não baixa arquivo.** `utils/exportar_csv.dart` copia o
   CSV para a área de transferência e pede para colar numa planilha. Faça o
   botão **baixar um arquivo `.csv`** de verdade (no web, com Blob e âncora de
   download; no mobile, pela folha de compartilhar). Crie um utilitário único
   `baixarArquivo(bytes, nome, mime)` que o CSV, o PDF da fase anterior (se
   ainda não usar o `printing`) e o `.ics` da Fase 7 reaproveitam. O CSV sai
   em UTF-8 com BOM, para o Excel em português abrir os acentos certos.
2. Rode `flutter analyze` e o build do backend com avisos ligados. Corrija os
   avisos reais e liste os que ficarem, com o motivo.

## Fase 3 — Check-in e check-out do entregador

Hoje não existe horário real de início. `StatusTurno.EM_ANDAMENTO` existe e o
app já o desenha, mas nenhum ponto do backend o grava (o comentário do enum
diz que ele espera o check-in). A pontualidade foi removida do perfil por
falta desse dado (`perfil_screen.dart`, comentário nos cartões).

- **Onde gravar:** em `turno_inscricoes`, porque cada entregador de um turno
  multivaga faz o próprio check-in: `checkin_em`, `checkin_latitude`,
  `checkin_longitude` e `checkout_em`.
- **Endpoints:** `PUT /api/turnos/{id}/checkin` (com lat/lng) e
  `PUT /api/turnos/{id}/checkout`, só para o entregador inscrito e aceito.
- **Regras:**
  - check-in liberado de 30 min antes do início até o fim do turno;
  - distância até a coordenada do turno de no máximo
    `motoshift.checkin.raio-metros` (padrão 500);
  - a trava de proximidade pode ser desligada por
    `motoshift.checkin.exigir-proximidade=false`, para a apresentação feita
    de casa. Documente isso no README;
  - o check-out só vale depois do check-in.
- **Status:** o primeiro check-in leva o turno de `ACEITO` a `EM_ANDAMENTO`.
  Procure todos os usos de `StatusTurno.ACEITO` e decida, caso a caso, se
  `EM_ANDAMENTO` também deve entrar: finalizar, cancelar, vencimento,
  contagem de ativos, agenda, dashboards e "o que falta". O turno em
  andamento **não pode** vencer nem ser cancelado como se não tivesse
  começado.
- **Lojista:** recebe a notificação "Ricardo chegou às 14:03 (3 min antes)" e
  vê, na tela do turno, a chegada e a saída de cada entregador.
- **Pontualidade:** percentual de check-ins até 10 min após o início, nos
  últimos 90 dias. Aparece no perfil do entregador (volta ao cartão de onde
  saiu) e no perfil público. Sem check-ins, mostre "Sem histórico", nunca
  100%.
- **App:** no detalhe do turno do entregador, um botão "Cheguei" / "Encerrar
  turno" que usa o `LocalizacaoService` da Fase 1, com as mensagens de falha
  que ele já tem e com a distância na mensagem de erro ("Você está a 1,2 km
  do local").
- **Testes:** as regras de janela, distância e papel, a transição de status,
  e o cancelamento/vencimento bloqueados em andamento.

## Fase 4 — Gorjeta

`TipoTransacao.BONUS` existe e o CHECK do banco o aceita (V10/V14), mas nenhum
fluxo o gera. Use-o para a gorjeta.

- **Na avaliação do entregador**, o lojista pode dar uma gorjeta opcional:
  R$ 5, R$ 10, R$ 20 ou outro valor (máximo configurável, padrão R$ 50).
- **Regras:**
  - só o lojista do turno;
  - só para turno finalizado e entregador que trabalhou nele;
  - uma gorjeta por entregador por turno;
  - só com saldo disponível;
  - idempotente: repetir a requisição não cobra duas vezes (use o padrão de
    `idempotency_key` que o projeto já tem).
- **Ledger:** um `Movimento.gorjeta(...)` novo, com débito no disponível do
  lojista e crédito no disponível do entregador, os dois ligados ao turno.
  Decida como separar os dois lados (tipo `bonus` com natureza, ou tipo novo)
  e justifique no commit. Se precisar de tipo novo, a migração amplia o CHECK.
- **Fiscal:** a gorjeta gera **comprovante**, não NFS-e. Atualize FISCAL.md e o
  `ComprovanteService`.
- **Aparece em:** extrato e filtros por papel, relatórios, exportações e
  notificação para o entregador ("Você recebeu uma gorjeta de R$ 10 da
  Hamburgueria da Cláudia").
- **Testes:** as regras acima, a idempotência e a consistência do ledger
  depois de gorjetas.

## Fase 5 — Repetir turno

- Um botão "Publicar de novo" em turno finalizado, cancelado ou expirado do
  lojista (lista de turnos e detalhe).
- Abre o formulário de publicar já preenchido (título, descrição, região,
  pino, raio, valor, vagas e duração), com a data movida para o mesmo dia da
  semana na próxima semana e o mesmo horário.
- Nada é publicado sem a confirmação de custo que já existe. As regras de
  antecedência e saldo continuam valendo.
- Só no app. Não precisa de endpoint novo se o formulário aceitar um turno de
  origem.

## Fase 6 — Entregadores favoritos

- Tabela `favoritos (lojista_id, motoboy_id, criado_em)`, com chave única no
  par e FKs.
- O lojista favorita um entregador por um coração no perfil público dele, na
  tela de avaliar entregadores e no detalhe do turno finalizado. A lista
  "Meus entregadores favoritos" fica no perfil do lojista.
- Ao publicar um turno, os favoritos daquele lojista recebem a notificação "A
  Hamburgueria da Cláudia publicou um turno para amanhã, 18h".
- Na lista de turnos disponíveis, os turnos de lojas que favoritaram o
  entregador ganham o selo "Loja que já te chamou". Ordenar por isso é
  opcional; não quebre as ordenações existentes.
- Endpoints: favoritar, desfavoritar e listar (só o lojista). Testes de papel
  e de duplicidade.

## Fase 7 — Rápidas

1. **Abrir rota:** no detalhe do turno do entregador, "Abrir rota" com
   `url_launcher`, levando para Google Maps (e Waze, se instalado no mobile),
   com destino na coordenada do turno.
2. **Adicionar à agenda:** "Adicionar ao calendário" baixa um `.ics`
   (RFC 5545, fuso `America/Sao_Paulo`, título, endereço, descrição e alarme
   de 1 h), usando o `baixarArquivo` da Fase 2. Disponível para o entregador
   (turnos aceitos) e para o lojista (turnos publicados).
3. **Lembrete 1 h antes:** um job `@Scheduled` (no padrão do
   `TurnoExpiracaoService`) avisa o entregador e o lojista de turno aceito que
   começa em até 1 h. Sem duplicar: garanta um lembrete por pessoa por turno,
   com coluna de controle ou consulta à notificação existente. Tipo novo
   `turno_lembrete`, que o app sabe desenhar e abrir.
4. **Meta do mês (entregador):** o entregador define uma meta mensal (coluna
   `meta_mensal` em `usuarios`, editável no perfil). O dashboard mostra a
   barra "R$ 1.340 de R$ 2.000 (67%)" com os ganhos reais do mês, vindos dos
   `pagamento_recebido` e das gorjetas. Sem meta, mostre um convite para
   definir, nunca uma barra zerada.
5. **Selos de reputação:** calculados no backend a partir dos dados, sem
   tabela nova, e devolvidos no perfil público. Mostre no perfil público e no
   próprio perfil, com o critério ao tocar. Sugestões (ajuste os limites à
   massa):
   - entregador: "25 turnos concluídos", "30 dias sem cancelar", "Nota acima
     de 4,8" (com pelo menos 10 avaliações) e "Pontual" (≥ 90%, com pelo
     menos 10 check-ins);
   - lojista: "Paga gorjeta", "Nota acima de 4,8" e "Contrata toda semana".

## Fase 8 — Massa e documentação

- A massa (`MassaDemonstracao`) passa a exercitar tudo isto:
  - check-ins pontuais e atrasados, que resultam em pontualidades diferentes
    entre os entregadores;
  - um turno `EM_ANDAMENTO` com check-in feito;
  - gorjetas em alguns turnos;
  - favoritos;
  - metas definidas para alguns entregadores;
  - lembretes e notificações de chegada recentes;
  - selos que aparecem em alguns perfis e não em outros.
- Tudo pelos serviços reais sempre que der, e a massa continua fechando em
  `verificarConsistencia()`.
- Atualize o DER (`docs/DER/der_motoshift.mmd` e `DER_MotoShift.md`) com as
  colunas e a tabela novas, a tabela de contas do README e o GUIA_DEFESA.md,
  com uma seção curta por feature explicando a regra e onde ela está no
  código.

## Fora do escopo

Chat entre as partes, pagamento real, editar turno publicado, bloquear
usuário, tema escuro e mudança de navegação. Se alguma fase parecer exigir
algo disso, pare e me pergunte.
