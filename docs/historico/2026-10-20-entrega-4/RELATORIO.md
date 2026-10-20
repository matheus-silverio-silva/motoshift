# Entrega 4 — testes de ponta a ponta e correções (20/10/2026)

Projeto Integrador VI · MotoShift

## Teste de ponta a ponta

`backend/src/test/java/com/motoshift/JornadaPontaAPontaTest.java` percorre a
jornada inteira pela API HTTP, na ordem em que o app a usa:

1. Lojista e entregador se cadastram (`POST /api/auth/registro`) e fazem login (`POST /api/auth/login`).
2. Lojista recarrega R$ 300 (`POST /api/carteira/recargas` + `/confirmar`).
3. Lojista publica um turno de R$ 150 (`POST /api/turnos`) — o valor fica reservado (disponível 150, comprometido 150).
4. Entregador encontra o turno em `/api/turnos/disponiveis` e aceita (`PUT /{id}/aceitar`).
5. Finalizar antes do início é recusado com 409 (RF06).
6. O turno começa; entregador faz check-in no ponto do turno (status `em_andamento`) e check-out.
7. Lojista finaliza (`PUT /{id}/finalizar`) — repetir não paga de novo.
8. Os dois se avaliam (`POST /api/avaliacoes`).
9. Carteiras conferidas: lojista com R$ 150 disponível, R$ 0 comprometido e R$ 150 pagos;
   entregador com R$ 150 recebidos e disponível = recebido − retenções.

Um segundo caso confirma que, sem token, publicar, aceitar e ver a carteira respondem 401.

Único passo fora do HTTP: mover o início do turno para o passado (a API só publica com 2h de
antecedência e só finaliza depois do início).

## Resultado das suítes (Windows, 20/10/2026)

| Suíte | Resultado |
|---|---|
| Backend — `mvnw test` | 589 testes, 0 falhas |
| Backend — `JornadaPontaAPontaTest` | 2 testes, 0 falhas |
| App — `flutter test` (Flutter 3.41.5) | 556 passaram, 32 ignorados, 0 falhas |

## Correções

- `StatusTurno`: o comentário dizia que `EM_ANDAMENTO` nunca era gravado e que o check-in
  "ainda não existe"; o check-in existe e grava esse estado. Comentário corrigido para
  refletir o comportamento real.

## Observação de ambiente

O backend publicado (`motoshift.onrender.com/api/status`) não respondeu em 2 tentativas de 90–120 s
nesta data; o front (`motoshift-8b0d2.web.app`) respondeu 200.
