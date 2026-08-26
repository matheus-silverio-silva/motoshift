# MotoShift — Plano de refatoração P0

**Objetivo:** destravar SCRUM-17, SCRUM-18, SCRUM-19 e SCRUM-20 sem reescrever o modelo.
**Escopo:** apenas o que bloqueia esses cards. Enums, `BigDecimal`, Flyway e consolidação
do estado de pagamento ficam para uma rodada seguinte (ver "Fora de escopo" no fim).

**Status desta proposta:** todo o Java abaixo foi compilado (`javac`, Java 17/21) contra
stubs das anotações Jakarta/Spring. `GeoUtils` foi testado numericamente. Nada foi
alterado no seu repositório — os diffs são para você revisar e aplicar.

> ⚠️ Os arquivos do projeto usam **CRLF**. Ao aplicar os patches, preserve o final de linha
> (`git apply --whitespace=nowarn`, ou copie os blocos manualmente).

---

## Como aplicar

Junto deste documento vai `refatoracao-p0.patch`, um patch git com **todos** os passos
(16 arquivos: 10 alterados, 6 novos). Da raiz do repositório:

```bash
git checkout -b refactor/p0-jira
git apply --check --whitespace=nowarn docs/refatoracao-p0/refatoracao-p0.patch  # confere
git apply --whitespace=nowarn docs/refatoracao-p0/refatoracao-p0.patch          # aplica
```

Testado: aplica limpo sobre o estado atual do repositório, preservando o CRLF de cada
arquivo. Os avisos de *trailing whitespace* são os próprios `\r` — pode ignorar.

Para aplicar **um passo de cada vez**, use os diffs individuais nas seções abaixo em vez
do patch inteiro. Se optar por isso, respeite a dependência: o Passo 5 não compila sem o
Passo 4 (`TurnoExpiracaoService` injeta `NotificacaoService`), e o `TurnoService` precisa
do Passo 4 pelo mesmo motivo.

---

## Ordem de execução

Os passos são independentes entre si, **exceto** o 5, que depende do 4
(`TurnoExpiracaoService` chama `NotificacaoService`). Sugestão de ordem por risco crescente:

| # | Passo | Card | Arquivos | Risco |
|---|-------|------|----------|-------|
| 1 | Avaliação multi-vaga | SCRUM-17 | 3 alterados | Baixo — mas exige checagem de dados em prod |
| 2 | NPE do raio + erro de parse | SCRUM-18 | 1 alterado | Nenhum — só correção |
| 3 | Geolocalização real | SCRUM-18 | 1 novo, 5 alterados | Médio — muda contrato da API |
| 4 | Entidade de notificação | SCRUM-20 | 4 novos | Baixo — tudo aditivo |
| 5 | Vencimento automático | SCRUM-19 | 1 novo, 2 alterados | Médio — job mexe em status |
| 6 | Índices | todos | incluído nos passos acima | Baixo |

**Sobre migração:** todas as colunas novas são **nullable**, e todos os índices novos são
não-únicos, exceto a `uk_avaliacao_turno_avaliador_avaliado` do Passo 1 (que tem um
pré-requisito descrito lá). Com `ddl-auto=update` no Postgres de produção, isso sobe sem
downtime e sem quebrar as linhas existentes — a mesma restrição que motivou o comentário
do campo `vagas`.

> Aliás, aquele comentário diz "o MySQL não consegue…" mas `application-prod.properties`
> aponta para **PostgreSQL**. O diff do Passo 3 corrige o texto.

---

## Passo 1 — Avaliação mútua em turno multi-vaga (SCRUM-17)

### O problema

Dois bugs no mesmo fluxo, ambos só aparecem quando o turno tem mais de uma vaga:

1. **`existsByTurnoIdAndAvaliadorId(turnoId, avaliadorId)`** trava o lojista depois da
   primeira avaliação. Turno com 3 entregadores: ele avalia um, os outros dois retornam
   `400 Você já avaliou este turno`.
2. **A checagem de participação** olha só `turno.getMotoboyId()` — que é o *primeiro*
   inscrito. Um entregador que entrou por vaga extra recebe `403 Avaliador não participou
   deste turno` e nunca consegue avaliar ninguém.

O endpoint `GET /turno/{turnoId}/pendentes/{usuarioId}` sofre dos dois.

### Pré-requisito antes de subir

A unique nova só é criada se não houver duplicatas. Rode em produção **antes** do deploy:

```sql
SELECT turno_id, avaliador_id, avaliado_id, COUNT(*)
FROM avaliacoes
GROUP BY turno_id, avaliador_id, avaliado_id
HAVING COUNT(*) > 1;
```

Se retornar linhas, remova as repetidas mantendo a mais recente. Se vier vazio (o cenário
provável, já que a trava antiga era *mais* restritiva), pode seguir. Se a criação do índice
falhar, o Hibernate loga o erro e **continua subindo** — confira o log do primeiro boot.

### Diffs

#### `entity/Avaliacao.java`

```diff
--- a/com/motoshift/entity/Avaliacao.java
+++ b/com/motoshift/entity/Avaliacao.java
@@ -4,7 +4,19 @@
 import java.time.LocalDateTime;
 
 @Entity
-@Table(name = "avaliacoes")
+@Table(
+    name = "avaliacoes",
+    uniqueConstraints = @UniqueConstraint(
+        // A chave é o TRIO. Com (turnoId, avaliadorId) o lojista de um turno
+        // multi-vaga ficaria travado após avaliar o primeiro entregador.
+        name = "uk_avaliacao_turno_avaliador_avaliado",
+        columnNames = {"turnoId", "avaliadorId", "avaliadoId"}
+    ),
+    indexes = {
+        @Index(name = "ix_avaliacao_avaliado", columnList = "avaliadoId"),
+        @Index(name = "ix_avaliacao_turno",    columnList = "turnoId")
+    }
+)
 public class Avaliacao {
 
     @Id
```

#### `repository/AvaliacaoRepository.java`

```diff
--- a/com/motoshift/repository/AvaliacaoRepository.java
+++ b/com/motoshift/repository/AvaliacaoRepository.java
@@ -9,8 +9,19 @@
 
     List<Avaliacao> findByAvaliadoIdOrderByCriadoEmDesc(Long avaliadoId);
 
+    /**
+     * @deprecated trava o avaliador no primeiro alvo em turnos multi-vaga.
+     *             Use {@link #existsByTurnoIdAndAvaliadorIdAndAvaliadoId}.
+     */
+    @Deprecated
     boolean existsByTurnoIdAndAvaliadorId(Long turnoId, Long avaliadorId);
 
+    // Duplicata real: mesmo avaliador, mesmo turno, MESMO avaliado.
+    boolean existsByTurnoIdAndAvaliadorIdAndAvaliadoId(
+            Long turnoId, Long avaliadorId, Long avaliadoId);
+
+    List<Avaliacao> findByTurnoIdAndAvaliadorId(Long turnoId, Long avaliadorId);
+
     List<Avaliacao> findByTurnoId(Long turnoId);
 
     List<Avaliacao> findByAvaliadorId(Long avaliadorId);
```

#### `controller/AvaliacaoController.java`

```diff
--- a/com/motoshift/controller/AvaliacaoController.java
+++ b/com/motoshift/controller/AvaliacaoController.java
@@ -2,8 +2,10 @@
 
 import com.motoshift.entity.Avaliacao;
 import com.motoshift.entity.Turno;
+import com.motoshift.entity.TurnoInscricao;
 import com.motoshift.entity.Usuario;
 import com.motoshift.repository.AvaliacaoRepository;
+import com.motoshift.repository.TurnoInscricaoRepository;
 import com.motoshift.repository.TurnoRepository;
 import com.motoshift.repository.UsuarioRepository;
 import io.swagger.v3.oas.annotations.Operation;
@@ -25,13 +27,16 @@
     private final AvaliacaoRepository avaliacaoRepo;
     private final TurnoRepository turnoRepo;
     private final UsuarioRepository usuarioRepo;
+    private final TurnoInscricaoRepository inscricaoRepo;
 
     public AvaliacaoController(AvaliacaoRepository avaliacaoRepo,
                                 TurnoRepository turnoRepo,
-                                UsuarioRepository usuarioRepo) {
+                                UsuarioRepository usuarioRepo,
+                                TurnoInscricaoRepository inscricaoRepo) {
         this.avaliacaoRepo = avaliacaoRepo;
         this.turnoRepo = turnoRepo;
         this.usuarioRepo = usuarioRepo;
+        this.inscricaoRepo = inscricaoRepo;
     }
 
     // ─────────────────────────────────────────────────────────
@@ -56,18 +61,24 @@
                     "Só é possível avaliar turnos finalizados.");
         }
 
-        // Valida participação
-        boolean participou = avaliadorId.equals(turno.getLojistId())
-                || avaliadorId.equals(turno.getMotoboyId());
-        if (!participou) {
+        // Valida participação do AVALIADOR.
+        // Antes só olhava turno.motoboyId; entregador que entrou por vaga extra
+        // tomava 403 e nunca conseguia avaliar.
+        if (!participou(turno, avaliadorId)) {
             throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                     "Avaliador não participou deste turno.");
         }
+        // O alvo também precisa ter participado, e ninguém avalia a si mesmo.
+        if (avaliadoId == null || avaliadorId.equals(avaliadoId) || !participou(turno, avaliadoId)) {
+            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
+                    "Avaliado inválido para este turno.");
+        }
 
-        // Valida duplicata
-        if (avaliacaoRepo.existsByTurnoIdAndAvaliadorId(turnoId, avaliadorId)) {
+        // Duplicata é o TRIO. Com (turno, avaliador) o lojista de um turno
+        // multi-vaga era barrado depois de avaliar o primeiro entregador.
+        if (avaliacaoRepo.existsByTurnoIdAndAvaliadorIdAndAvaliadoId(turnoId, avaliadorId, avaliadoId)) {
             throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
-                    "Você já avaliou este turno.");
+                    "Você já avaliou este participante neste turno.");
         }
 
         // Valida nota
@@ -163,22 +174,59 @@
     // GET /api/avaliacoes/turno/{turnoId}/pendentes/{usuarioId}
     // ─────────────────────────────────────────────────────────
 
-    @Operation(summary = "Verifica se usuário precisa avaliar o turno")
+    @Operation(summary = "Quem o usuário ainda precisa avaliar neste turno",
+            description = "Em turno multi-vaga o lojista avalia cada entregador. "
+                    + "Mantém 'precisaAvaliar' por compatibilidade e acrescenta a lista 'pendentes'.")
     @GetMapping("/turno/{turnoId}/pendentes/{usuarioId}")
-    public Map<String, Boolean> pendente(@PathVariable Long turnoId,
-                                          @PathVariable Long usuarioId) {
+    public Map<String, Object> pendente(@PathVariable Long turnoId,
+                                        @PathVariable Long usuarioId) {
         Turno turno = turnoRepo.findById(turnoId)
                 .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Turno não encontrado."));
 
-        boolean participou = usuarioId.equals(turno.getLojistId())
-                || usuarioId.equals(turno.getMotoboyId());
+        List<Map<String, Object>> pendentes = new ArrayList<>();
+        if (participou(turno, usuarioId) && "finalizado".equals(turno.getStatus())) {
+            for (Long alvo : alvosDeAvaliacao(turno, usuarioId)) {
+                if (avaliacaoRepo.existsByTurnoIdAndAvaliadorIdAndAvaliadoId(turnoId, usuarioId, alvo)) {
+                    continue;
+                }
+                Map<String, Object> m = new LinkedHashMap<>();
+                m.put("usuarioId", alvo);
+                m.put("nome", usuarioRepo.findById(alvo).map(Usuario::getNome).orElse("Usuário"));
+                pendentes.add(m);
+            }
+        }
+
+        Map<String, Object> resp = new LinkedHashMap<>();
+        resp.put("precisaAvaliar", !pendentes.isEmpty());
+        resp.put("pendentes", pendentes);
+        return resp;
+    }
 
-        boolean jaAvaliou = avaliacaoRepo.existsByTurnoIdAndAvaliadorId(turnoId, usuarioId);
-        boolean precisaAvaliar = participou
-                && "finalizado".equals(turno.getStatus())
-                && !jaAvaliou;
+    /** Participou do turno como lojista, motoboy principal ou inscrito. */
+    private boolean participou(Turno turno, Long usuarioId) {
+        if (usuarioId == null) return false;
+        if (usuarioId.equals(turno.getLojistId())) return true;
+        if (usuarioId.equals(turno.getMotoboyId())) return true;
+        return inscricaoRepo.findByTurnoIdAndMotoboyId(turno.getId(), usuarioId)
+                .filter(i -> !"cancelado".equals(i.getStatus()))
+                .isPresent();
+    }
 
-        return Map.of("precisaAvaliar", precisaAvaliar);
+    /** Lojista avalia todos os entregadores; entregador avalia o lojista. */
+    private List<Long> alvosDeAvaliacao(Turno turno, Long usuarioId) {
+        if (!usuarioId.equals(turno.getLojistId())) {
+            return turno.getLojistId() == null ? List.of() : List.of(turno.getLojistId());
+        }
+        List<Long> ids = inscricaoRepo.findByTurnoId(turno.getId()).stream()
+                .filter(i -> !"cancelado".equals(i.getStatus()))
+                .map(TurnoInscricao::getMotoboyId)
+                .distinct()
+                .collect(Collectors.toList());
+        // Legado: turno aceito antes do sistema de vagas não tem inscrição.
+        if (ids.isEmpty() && turno.getMotoboyId() != null) {
+            ids = List.of(turno.getMotoboyId());
+        }
+        return ids;
     }
 
     // ── Helpers ──────────────────────────────────────────────
```

### Impacto no app Flutter

`GET /api/avaliacoes/turno/{turnoId}/pendentes/{usuarioId}` muda de
`{"precisaAvaliar": true}` para:

```json
{
  "precisaAvaliar": true,
  "pendentes": [
    {"usuarioId": 7,  "nome": "Carlos Souza"},
    {"usuarioId": 12, "nome": "Ana Lima"}
  ]
}
```

`precisaAvaliar` continua existindo com o mesmo significado — **o app atual não quebra**.
Mas para o lojista avaliar todo mundo, a tela precisa iterar `pendentes` e mandar um POST
por entregador, cada um com o `avaliadoId` correto.

---

## Passo 2 — NPE no filtro de raio e erro de parse (SCRUM-18)

### O problema

`raioEntregaKm` é nullable (`private Double raioEntregaKm;` sem `@Column(nullable=false)`),
mas `listarDisponiveisComFiltros` faz unboxing direto em dois lugares:

```java
stream = stream.filter(t -> t.getRaioEntregaKm() <= raioMaxKm);   // NPE
case "raioAsc" -> Comparator.comparingDouble(Turno::getRaioEntregaKm);  // NPE
```

Um único turno sem raio derruba a listagem inteira com `500`. E `LocalTime.parse` /
`LocalDate.parse` com formato inválido também vira `500`, quando deveria ser `400`.

A correção entra junto com o Passo 3, no mesmo método — o diff completo está lá.
O essencial:

```java
// null-safe no filtro
if (raioMaxKm != null) {
    stream = stream.filter(t -> t.getRaioEntregaKm() != null
            && t.getRaioEntregaKm() <= raioMaxKm);
}

// null-safe na ordenação
case "raioAsc" -> Comparator.comparing(Turno::getRaioEntregaKm,
                      Comparator.nullsLast(Comparator.naturalOrder()));

// parse inválido = erro do cliente, não do servidor
} catch (DateTimeParseException e) {
    throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
            "Formato de data/hora inválido. Use HH:mm para horários e yyyy-MM-dd para datas.");
}
```

> Se você quiser fechar SCRUM-18 em duas entregas, **este passo sozinho já é um PR válido** —
> corrige um `500` em produção sem mexer no contrato da API.

---

## Passo 3 — Raio de verdade: geolocalização (SCRUM-18)

### O problema

O card pede "filtrar turnos por período e **raio**". Hoje o filtro é:

```java
stream.filter(t -> t.getRaioEntregaKm() <= raioMaxKm);
```

Isso filtra *turnos cuja área de entrega é pequena* — não *turnos perto do motoboy*.
São coisas diferentes: um turno com raio de 3 km a 40 km de distância passa no filtro atual.
E não há como corrigir só no service: **nem `Turno` nem `Usuario` têm coordenada**.

### A solução

- `Turno` ganha `latitude`, `longitude` e `endereco` (todos nullable).
- `raioEntregaKm` **permanece** com o significado atual (área de atuação do turno) —
  o comentário no campo passa a deixar isso explícito.
- A posição do motoboy vem do GPS do app, como query params `lat` / `lng` / `raioKm`.
  Não precisa guardar posição de usuário no banco (e é melhor não guardar).
- Nova classe `GeoUtils` com Haversine.
- Pré-filtro por *bounding box* **no banco** (usa o índice `ix_turno_geo`), refino exato
  por Haversine em memória. Isso também resolve o "carrega todos os turnos abertos para a
  memória" que existe hoje.
- Nova ordenação `distanciaAsc`, e cada turno da resposta passa a trazer `distanciaKm`.

Turnos legados sem coordenada simplesmente não aparecem quando o filtro geográfico está
ligado — e continuam aparecendo normalmente quando não está.

### Arquivo novo: `util/GeoUtils.java`

```java
package com.motoshift.util;

/**
 * Cálculos geográficos usados pelo filtro de turnos por raio (SCRUM-18).
 *
 * Usa a fórmula de Haversine, que assume a Terra como esfera. O erro é da
 * ordem de 0,5% — irrelevante para raios urbanos de 1 a 50 km.
 */
public final class GeoUtils {

    /** Raio médio da Terra em km (IUGG mean radius). */
    private static final double RAIO_TERRA_KM = 6371.0088;

    /** Aproximação de 1 grau de latitude em km. Constante em qualquer latitude. */
    private static final double KM_POR_GRAU_LAT = 111.32;

    private GeoUtils() {}

    /**
     * Distância em km entre dois pontos. Devolve {@code null} se qualquer
     * coordenada estiver ausente — quem chama decide se isso exclui ou não o
     * registro (turnos legados não têm coordenada).
     */
    public static Double distanciaKm(Double lat1, Double lon1, Double lat2, Double lon2) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return null;

        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                 * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return RAIO_TERRA_KM * c;
    }

    public static boolean coordenadaValida(Double lat, Double lng) {
        return lat != null && lng != null
                && lat >= -90.0 && lat <= 90.0
                && lng >= -180.0 && lng <= 180.0;
    }

    /**
     * Meia-altura (em graus de latitude) de uma bounding box que contém o
     * círculo de raio {@code raioKm}. Usado como pré-filtro no banco.
     */
    public static double deltaLatitude(double raioKm) {
        return raioKm / KM_POR_GRAU_LAT;
    }

    /**
     * Meia-largura (em graus de longitude) da mesma bounding box. Depende da
     * latitude: perto dos polos, 1 grau de longitude vale menos km.
     */
    public static double deltaLongitude(double raioKm, double latitude) {
        double cos = Math.cos(Math.toRadians(latitude));
        if (cos < 0.01) cos = 0.01; // evita divisão por ~zero perto dos polos
        return raioKm / (KM_POR_GRAU_LAT * cos);
    }

    /** Arredonda para 1 casa decimal, preservando null. */
    public static Double arredondar1(Double v) {
        if (v == null) return null;
        return Math.round(v * 10.0) / 10.0;
    }
}
```

Conferido numericamente: Av. Paulista → Praça da Sé = **2,6 km**; Praça da Sé → GRU =
**20,7 km** (linha reta). Coordenada ausente devolve `null` em vez de estourar.

### Diffs

#### `entity/Turno.java`

```diff
--- a/com/motoshift/entity/Turno.java
+++ b/com/motoshift/entity/Turno.java
@@ -4,7 +4,18 @@
 import java.time.LocalDateTime;
 
 @Entity
-@Table(name = "turnos")
+@Table(
+    name = "turnos",
+    indexes = {
+        // Listagem de disponíveis e job de expiração (SCRUM-18 / SCRUM-19).
+        @Index(name = "ix_turno_status_inicio", columnList = "status, dataInicio"),
+        @Index(name = "ix_turno_status_fim",    columnList = "status, dataFim"),
+        // Pré-filtro por bounding box no filtro de raio (SCRUM-18).
+        @Index(name = "ix_turno_geo",           columnList = "status, latitude, longitude"),
+        @Index(name = "ix_turno_lojista",       columnList = "lojistId"),
+        @Index(name = "ix_turno_motoboy",       columnList = "motoboyId")
+    }
+)
 public class Turno {
 
     @Id
@@ -32,19 +43,34 @@
     @Column(nullable = false)
     private Double valorEstimado;
 
+    // Raio de atuação declarado pelo lojista (quão longe o entregador vai rodar).
+    // NÃO é a distância até o motoboy — para isso existem latitude/longitude abaixo.
     private Double raioEntregaKm;
 
+    // ── Geolocalização do ponto de partida (SCRUM-18) ──────────────────────
+    // Nullable de propósito: turnos criados antes desta versão não têm
+    // coordenada e simplesmente ficam de fora do filtro por raio, sem quebrar
+    // as listagens existentes.
+    private Double latitude;
+    private Double longitude;
+
+    @Column(length = 200)
+    private String endereco;
+
     // Número de vagas de entregador para este turno (lojista pode precisar de vários).
-    // IMPORTANTE: coluna nullable de propósito. Com ddl-auto=update, o MySQL não
+    // IMPORTANTE: coluna nullable de propósito. Com ddl-auto=update, o banco não
     // consegue adicionar uma coluna NOT NULL a uma tabela que já tem linhas — isso
     // quebraria as consultas de turno em produção. Sendo nullable, a migração
     // ocorre sem erro; linhas antigas ficam NULL e o getter devolve 1 (default).
     private Integer vagas;
 
-    // aberto | aceito | em_andamento | finalizado | cancelado
+    // aberto | aceito | em_andamento | finalizado | cancelado | expirado
     @Column(nullable = false)
     private String status = "aberto";
 
+    // Preenchido pelo job de vencimento quando o turno passa a "expirado" (SCRUM-19).
+    private LocalDateTime expiradoEm;
+
     // null (não finalizado) | pendente | pago
     // "pago" só quando AMBOS confirmaram (lojista pagou + motoboy recebeu)
     private String pagamentoStatus;
@@ -100,6 +126,18 @@
     public Double getRaioEntregaKm() { return raioEntregaKm; }
     public void setRaioEntregaKm(Double raioEntregaKm) { this.raioEntregaKm = raioEntregaKm; }
 
+    public Double getLatitude() { return latitude; }
+    public void setLatitude(Double latitude) { this.latitude = latitude; }
+
+    public Double getLongitude() { return longitude; }
+    public void setLongitude(Double longitude) { this.longitude = longitude; }
+
+    public String getEndereco() { return endereco; }
+    public void setEndereco(String endereco) { this.endereco = endereco; }
+
+    public LocalDateTime getExpiradoEm() { return expiradoEm; }
+    public void setExpiradoEm(LocalDateTime expiradoEm) { this.expiradoEm = expiradoEm; }
+
     public Integer getVagas() { return vagas == null ? 1 : vagas; }
     public void setVagas(Integer vagas) { this.vagas = vagas; }
 
```

#### `dto/TurnoRequest.java`

```diff
--- a/com/motoshift/dto/TurnoRequest.java
+++ b/com/motoshift/dto/TurnoRequest.java
@@ -28,6 +28,12 @@
 
     private Double raioEntregaKm;
 
+    // Ponto de partida do turno (SCRUM-18). Opcional: sem coordenada o turno
+    // continua sendo criado, só não aparece no filtro por raio.
+    private Double latitude;
+    private Double longitude;
+    private String endereco;
+
     // Número de vagas de entregador (opcional; default 1 no serviço).
     private Integer vagas;
 
@@ -55,6 +61,15 @@
     public Double getRaioEntregaKm() { return raioEntregaKm; }
     public void setRaioEntregaKm(Double raioEntregaKm) { this.raioEntregaKm = raioEntregaKm; }
 
+    public Double getLatitude() { return latitude; }
+    public void setLatitude(Double latitude) { this.latitude = latitude; }
+
+    public Double getLongitude() { return longitude; }
+    public void setLongitude(Double longitude) { this.longitude = longitude; }
+
+    public String getEndereco() { return endereco; }
+    public void setEndereco(String endereco) { this.endereco = endereco; }
+
     public Integer getVagas() { return vagas; }
     public void setVagas(Integer vagas) { this.vagas = vagas; }
 }
```

#### `dto/TurnoResponse.java`

```diff
--- a/com/motoshift/dto/TurnoResponse.java
+++ b/com/motoshift/dto/TurnoResponse.java
@@ -16,6 +16,13 @@
     private LocalDateTime dataFim;
     private Double valorEstimado;
     private Double raioEntregaKm;
+    private Double latitude;
+    private Double longitude;
+    private String endereco;
+    // Distância do usuário até o turno, em km. Só vem preenchida quando a
+    // requisição informou lat/lng; null caso contrário.
+    private Double distanciaKm;
+    private LocalDateTime expiradoEm;
     private Integer vagas;
     private Integer vagasPreenchidas;
     private String status;
@@ -37,6 +44,10 @@
         r.dataFim = t.getDataFim();
         r.valorEstimado = t.getValorEstimado();
         r.raioEntregaKm = t.getRaioEntregaKm();
+        r.latitude = t.getLatitude();
+        r.longitude = t.getLongitude();
+        r.endereco = t.getEndereco();
+        r.expiradoEm = t.getExpiradoEm();
         r.vagas = t.getVagas();
         r.vagasPreenchidas = 0; // atualizado pelo serviço via setVagasPreenchidas
         r.status = t.getStatus();
@@ -58,6 +69,12 @@
     public LocalDateTime getDataFim() { return dataFim; }
     public Double getValorEstimado() { return valorEstimado; }
     public Double getRaioEntregaKm() { return raioEntregaKm; }
+    public Double getLatitude() { return latitude; }
+    public Double getLongitude() { return longitude; }
+    public String getEndereco() { return endereco; }
+    public Double getDistanciaKm() { return distanciaKm; }
+    public void setDistanciaKm(Double d) { this.distanciaKm = d; }
+    public LocalDateTime getExpiradoEm() { return expiradoEm; }
     public Integer getVagas() { return vagas; }
     public Integer getVagasPreenchidas() { return vagasPreenchidas; }
     public void setVagasPreenchidas(Integer v) { this.vagasPreenchidas = v; }
```

#### `repository/TurnoRepository.java`

```diff
--- a/com/motoshift/repository/TurnoRepository.java
+++ b/com/motoshift/repository/TurnoRepository.java
@@ -40,4 +40,26 @@
             @Param("usuarioId") Long usuarioId,
             @Param("inicio") LocalDateTime inicio,
             @Param("fim") LocalDateTime fim);
+
+    // ── SCRUM-18: pré-filtro geográfico ───────────────────────────────────
+    // Bounding box no banco (usa ix_turno_geo) para não carregar todos os
+    // turnos abertos na memória; o refino exato por Haversine é feito depois.
+    @Query("SELECT t FROM Turno t WHERE t.status = 'aberto' " +
+           "AND t.latitude IS NOT NULL AND t.longitude IS NOT NULL " +
+           "AND t.latitude BETWEEN :latMin AND :latMax " +
+           "AND t.longitude BETWEEN :lngMin AND :lngMax")
+    List<Turno> findAbertosNaArea(
+            @Param("latMin") double latMin, @Param("latMax") double latMax,
+            @Param("lngMin") double lngMin, @Param("lngMax") double lngMax);
+
+    // ── SCRUM-19: vencimento ──────────────────────────────────────────────
+    // Turnos ainda abertos cujo horário de início já passou.
+    List<Turno> findByStatusAndDataInicioBefore(String status, LocalDateTime limite);
+
+    // Turnos em andamento/aceitos cujo fim já passou e ninguém finalizou.
+    List<Turno> findByStatusInAndDataFimBefore(List<String> statuses, LocalDateTime limite);
+
+    // Turnos que começam dentro de uma janela (aviso de "vai vencer").
+    List<Turno> findByStatusAndDataInicioBetween(
+            String status, LocalDateTime de, LocalDateTime ate);
 }
```

#### `controller/TurnoController.java`

```diff
--- a/com/motoshift/controller/TurnoController.java
+++ b/com/motoshift/controller/TurnoController.java
@@ -48,7 +48,10 @@
         return service.listarDisponiveis();
     }
 
-    @Operation(summary = "Listar turnos disponíveis", description = "Retorna turnos abertos com filtros opcionais de horário, dia da semana, raio e datas.")
+    @Operation(summary = "Listar turnos disponíveis",
+            description = "Turnos abertos com filtros opcionais de horário, dia da semana, "
+                    + "período e proximidade. Informe lat+lng+raioKm para filtrar por "
+                    + "distância real do usuário; a resposta traz distanciaKm em cada turno.")
     @ApiResponse(responseCode = "200", description = "Turnos disponíveis")
     @GetMapping("/disponiveis")
     public List<TurnoResponse> disponiveis(
@@ -58,14 +61,19 @@
             @RequestParam(required = false) Double raioMaxKm,
             @RequestParam(required = false) String dataInicio,
             @RequestParam(required = false) String dataFim,
-            @RequestParam(required = false) String ordenarPor) {
+            @RequestParam(required = false) String ordenarPor,
+            // SCRUM-18: posição do usuário (GPS do app) + raio de busca em km.
+            @RequestParam(required = false) Double lat,
+            @RequestParam(required = false) Double lng,
+            @RequestParam(required = false) Double raioKm) {
 
         boolean hasFilter = horarioInicio != null || horarioFim != null || diaSemana != null
-                || raioMaxKm != null || dataInicio != null || dataFim != null || ordenarPor != null;
+                || raioMaxKm != null || dataInicio != null || dataFim != null
+                || ordenarPor != null || lat != null || lng != null || raioKm != null;
 
         if (hasFilter) {
             return service.listarDisponiveisComFiltros(horarioInicio, horarioFim,
-                    diaSemana, raioMaxKm, dataInicio, dataFim, ordenarPor);
+                    diaSemana, raioMaxKm, dataInicio, dataFim, ordenarPor, lat, lng, raioKm);
         }
         return service.listarDisponiveis();
     }
```

> O diff de `TurnoRepository.java` acima já inclui as consultas do Passo 5 (vencimento) —
> são adições ao mesmo arquivo, e separá-las só geraria conflito de patch.
> O `TurnoService.java` é tocado pelos passos 2, 3 e 5; o diff dele está consolidado
> na seção **"Diff consolidado — TurnoService"**, mais abaixo.

### Impacto no app Flutter

`GET /api/turnos/disponiveis` ganha três query params **opcionais**:

| Param | Tipo | Descrição |
|-------|------|-----------|
| `lat` | double | Latitude do motoboy (GPS) |
| `lng` | double | Longitude do motoboy (GPS) |
| `raioKm` | double | Raio de busca em km |

Os três só têm efeito juntos. Exemplo:

```
GET /api/turnos/disponiveis?lat=-23.5614&lng=-46.6559&raioKm=8&ordenarPor=distanciaAsc
```

`POST /api/turnos` aceita `latitude`, `longitude` e `endereco` (opcionais; se `latitude`
ou `longitude` vier, ambas precisam ser válidas ou é `400`).

`TurnoResponse` ganha `latitude`, `longitude`, `endereco`, `expiradoEm` e `distanciaKm`
(esta só vem preenchida quando a requisição mandou `lat`/`lng`; `null` caso contrário).
Campos aditivos — o app atual ignora e segue funcionando.

### Não esqueça do seed

`DataInitializer.java` cria turnos sem coordenada. Enquanto ele não setar `latitude`/
`longitude`, **o filtro por raio vai devolver lista vazia em desenvolvimento** e parecer
quebrado. Espalhe os turnos de exemplo em torno de um ponto (ex.: Av. Paulista,
`-23.5614, -46.6559`) variando ±0,05 grau.

---

## Passo 4 — Entidade de notificação (SCRUM-20)

O card pede notificações para **vencimento, cancelamento e demora na troca de status**.
Não existe nada disso hoje — é criação, não refatoração. Quatro arquivos novos, zero
alteração em arquivo existente (os *hooks* que disparam notificação estão no Passo 5 e no
diff consolidado do `TurnoService`).

### Decisões de modelagem

- **`(usuarioId, tipo, referenciaId)` como chave de deduplicação.** Sem isso, um job que
  roda de 5 em 5 minutos gera 12 notificações por hora do mesmo evento. `NotificacaoService`
  expõe `criar()` (sempre grava — para eventos disparados por ação do usuário) e
  `criarUnica()` (só grava se não existir — **é esta que os jobs devem usar**).
- **`referenciaTipo` + `referenciaId`** em vez de FK, para manter o padrão do projeto e
  permitir deep link no app (`turno` / `carteira` / `avaliacao`).
- **Índice composto `(usuarioId, lida, criadoEm)`** — a consulta do sino é sempre essa.
- **Sem push/FCM.** In-app primeiro. Quando entrar push, a entidade não muda: só se
  acrescenta um `deviceToken` em `Usuario` e um listener sobre `NotificacaoService.criar`.

### `entity/Notificacao.java` (novo)

```java
package com.motoshift.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Notificação in-app de um usuário (SCRUM-20).
 *
 * Cobre vencimento, cancelamento, demora na troca de status e pagamento.
 * O par ({@code tipo}, {@code referenciaId}) serve para deduplicação: um job
 * que roda a cada 5 minutos não pode gerar a mesma notificação 12 vezes por hora.
 */
@Entity
@Table(
    name = "notificacoes",
    indexes = {
        // Listagem do sino: "minhas notificações, não lidas primeiro".
        @Index(name = "ix_notificacao_usuario", columnList = "usuarioId, lida, criadoEm"),
        // Deduplicação nos jobs agendados.
        @Index(name = "ix_notificacao_dedup",   columnList = "usuarioId, tipo, referenciaId")
    }
)
public class Notificacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long usuarioId;

    // turno_expirado | turno_vencendo | turno_aceito | turno_lotado
    // | turno_cancelado | turno_pendente_finalizacao | pagamento_pendente
    // | pagamento_confirmado | avaliacao_pendente
    @Column(nullable = false, length = 40)
    private String tipo;

    @Column(nullable = false, length = 120)
    private String titulo;

    @Column(nullable = false, length = 255)
    private String mensagem;

    // Deep link no app: "turno" | "avaliacao" | "carteira"
    @Column(length = 20)
    private String referenciaTipo;

    private Long referenciaId;

    @Column(nullable = false)
    private Boolean lida = false;

    private LocalDateTime lidaEm;

    @Column(nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @PrePersist
    private void prePersist() {
        criadoEm = LocalDateTime.now();
        if (lida == null) lida = false;
    }

    public Long getId() { return id; }

    public Long getUsuarioId() { return usuarioId; }
    public void setUsuarioId(Long usuarioId) { this.usuarioId = usuarioId; }

    public String getTipo() { return tipo; }
    public void setTipo(String tipo) { this.tipo = tipo; }

    public String getTitulo() { return titulo; }
    public void setTitulo(String titulo) { this.titulo = titulo; }

    public String getMensagem() { return mensagem; }
    public void setMensagem(String mensagem) { this.mensagem = mensagem; }

    public String getReferenciaTipo() { return referenciaTipo; }
    public void setReferenciaTipo(String referenciaTipo) { this.referenciaTipo = referenciaTipo; }

    public Long getReferenciaId() { return referenciaId; }
    public void setReferenciaId(Long referenciaId) { this.referenciaId = referenciaId; }

    public Boolean getLida() { return lida != null && lida; }
    public void setLida(Boolean lida) { this.lida = lida; }

    public LocalDateTime getLidaEm() { return lidaEm; }
    public void setLidaEm(LocalDateTime lidaEm) { this.lidaEm = lidaEm; }

    public LocalDateTime getCriadoEm() { return criadoEm; }
}
```

### `repository/NotificacaoRepository.java` (novo)

```java
package com.motoshift.repository;

import com.motoshift.entity.Notificacao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface NotificacaoRepository extends JpaRepository<Notificacao, Long> {

    List<Notificacao> findTop50ByUsuarioIdOrderByCriadoEmDesc(Long usuarioId);

    List<Notificacao> findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(Long usuarioId);

    long countByUsuarioIdAndLidaFalse(Long usuarioId);

    // Deduplicação: evita que um job agendado repita a mesma notificação.
    boolean existsByUsuarioIdAndTipoAndReferenciaId(
            Long usuarioId, String tipo, Long referenciaId);

    // Limpeza periódica do histórico.
    List<Notificacao> findByLidaTrueAndCriadoEmBefore(LocalDateTime limite);
}
```

### `service/NotificacaoService.java` (novo)

```java
package com.motoshift.service;

import com.motoshift.entity.Notificacao;
import com.motoshift.repository.NotificacaoRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Criação e leitura de notificações in-app (SCRUM-20).
 *
 * Ponto único de entrada: nenhum outro service deve instanciar Notificacao
 * diretamente, para que a deduplicação valha para todo mundo.
 */
@Service
public class NotificacaoService {

    private final NotificacaoRepository repo;

    public NotificacaoService(NotificacaoRepository repo) {
        this.repo = repo;
    }

    /** Cria sempre — para eventos disparados por ação do usuário. */
    @Transactional
    public Notificacao criar(Long usuarioId, String tipo, String titulo,
                             String mensagem, String referenciaTipo, Long referenciaId) {
        if (usuarioId == null) return null;
        Notificacao n = new Notificacao();
        n.setUsuarioId(usuarioId);
        n.setTipo(tipo);
        n.setTitulo(titulo);
        n.setMensagem(truncar(mensagem, 255));
        n.setReferenciaTipo(referenciaTipo);
        n.setReferenciaId(referenciaId);
        return repo.save(n);
    }

    /**
     * Cria só se ainda não existir uma notificação do mesmo tipo para a mesma
     * referência. É esta a versão que os jobs agendados devem usar — sem ela,
     * um job de 5 em 5 minutos gera 12 notificações por hora do mesmo evento.
     */
    @Transactional
    public Notificacao criarUnica(Long usuarioId, String tipo, String titulo,
                                  String mensagem, String referenciaTipo, Long referenciaId) {
        if (usuarioId == null) return null;
        if (referenciaId != null
                && repo.existsByUsuarioIdAndTipoAndReferenciaId(usuarioId, tipo, referenciaId)) {
            return null;
        }
        return criar(usuarioId, tipo, titulo, mensagem, referenciaTipo, referenciaId);
    }

    public List<Notificacao> listar(Long usuarioId, boolean apenasNaoLidas) {
        return apenasNaoLidas
                ? repo.findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(usuarioId)
                : repo.findTop50ByUsuarioIdOrderByCriadoEmDesc(usuarioId);
    }

    public long contarNaoLidas(Long usuarioId) {
        return repo.countByUsuarioIdAndLidaFalse(usuarioId);
    }

    @Transactional
    public void marcarComoLida(Long id) {
        repo.findById(id).ifPresent(n -> {
            if (!n.getLida()) {
                n.setLida(true);
                n.setLidaEm(LocalDateTime.now());
                repo.save(n);
            }
        });
    }

    @Transactional
    public int marcarTodasComoLidas(Long usuarioId) {
        List<Notificacao> naoLidas = repo.findByUsuarioIdAndLidaFalseOrderByCriadoEmDesc(usuarioId);
        LocalDateTime agora = LocalDateTime.now();
        for (Notificacao n : naoLidas) {
            n.setLida(true);
            n.setLidaEm(agora);
            repo.save(n);
        }
        return naoLidas.size();
    }

    private String truncar(String s, int max) {
        if (s == null) return "";
        return s.length() <= max ? s : s.substring(0, max);
    }
}
```

### `controller/NotificacaoController.java` (novo)

```java
package com.motoshift.controller;

import com.motoshift.entity.Notificacao;
import com.motoshift.service.NotificacaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/notificacoes")
@CrossOrigin(origins = "*", allowedHeaders = "*")
@Tag(name = "Notificacoes", description = "Notificacoes in-app do usuario (RF09 / SCRUM-20)")
public class NotificacaoController {

    private final NotificacaoService service;

    public NotificacaoController(NotificacaoService service) {
        this.service = service;
    }

    @Operation(summary = "Listar notificacoes do usuario")
    @GetMapping
    public List<Map<String, Object>> listar(
            @RequestParam Long usuarioId,
            @RequestParam(required = false, value = "apenasNaoLidas") Boolean apenasNaoLidas) {
        boolean somenteNaoLidas = apenasNaoLidas != null && apenasNaoLidas;
        return service.listar(usuarioId, somenteNaoLidas).stream()
                .map(this::toMap)
                .collect(Collectors.toList());
    }

    @Operation(summary = "Contagem de nao lidas (badge do sino)")
    @GetMapping("/contagem")
    public Map<String, Object> contagem(@RequestParam Long usuarioId) {
        return Map.of("naoLidas", service.contarNaoLidas(usuarioId));
    }

    @Operation(summary = "Marcar uma notificacao como lida")
    @PutMapping("/{id}/lida")
    public Map<String, Object> marcarLida(@PathVariable Long id) {
        service.marcarComoLida(id);
        return Map.of("ok", true);
    }

    @Operation(summary = "Marcar todas como lidas")
    @PutMapping("/marcar-todas-lidas")
    public Map<String, Object> marcarTodas(@RequestParam Long usuarioId) {
        return Map.of("atualizadas", service.marcarTodasComoLidas(usuarioId));
    }

    private Map<String, Object> toMap(Notificacao n) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", n.getId());
        m.put("tipo", n.getTipo());
        m.put("titulo", n.getTitulo());
        m.put("mensagem", n.getMensagem());
        m.put("referenciaTipo", n.getReferenciaTipo());
        m.put("referenciaId", n.getReferenciaId());
        m.put("lida", n.getLida());
        m.put("criadoEm", n.getCriadoEm());
        return m;
    }
}
```

### Endpoints novos

| Método | Rota | Uso |
|--------|------|-----|
| `GET` | `/api/notificacoes?usuarioId=1` | Últimas 50 |
| `GET` | `/api/notificacoes?usuarioId=1&apenasNaoLidas=true` | Só não lidas |
| `GET` | `/api/notificacoes/contagem?usuarioId=1` | `{"naoLidas": 3}` — badge do sino |
| `PUT` | `/api/notificacoes/{id}/lida` | Marca uma |
| `PUT` | `/api/notificacoes/marcar-todas-lidas?usuarioId=1` | Marca todas |

---

## Passo 5 — Vencimento automático de turnos (SCRUM-19)

### Regras propostas

A parte delicada deste card é decidir **o que o job pode mudar sozinho**. Proposta:

| Situação | Ação do job | Por quê |
|----------|-------------|---------|
| `aberto`, início já passou, **0 inscritos** | vira `expirado` + notifica lojista | Ninguém pegou; o turno morreu |
| `aberto`, início já passou, **parcialmente preenchido** | vira `aceito` + notifica lojista | Fecha vagas restantes; quem entrou continua valendo |
| `aberto`, começa em < 1h, ainda com vaga | **só notifica** | Ainda dá tempo de alguém aceitar |
| `aceito`/`em_andamento`, fim já passou | **só notifica** lojista e entregadores | Finalizar dispara transação e crédito em carteira — isso é decisão humana, não de cron |

A última linha é a mais importante: **o job não finaliza turno**. Finalizar cria `Transacao`
e muda `pagamentoStatus`; um bug no agendador viraria dinheiro errado na carteira.

### Pré-requisitos

1. `@EnableScheduling` na aplicação:

```diff
--- a/com/motoshift/MotoshiftApplication.java
+++ b/com/motoshift/MotoshiftApplication.java
 import org.springframework.boot.SpringApplication;
 import org.springframework.boot.autoconfigure.SpringBootApplication;
+import org.springframework.scheduling.annotation.EnableScheduling;
 
 @SpringBootApplication
+@EnableScheduling
 public class MotoshiftApplication {
```

2. Intervalo configurável em `application.properties` (e no `-prod`):

```properties
# --- Vencimento automático de turnos (SCRUM-19) ---
# Intervalo entre execuções, em ms. 300000 = 5 min.
motoshift.expiracao.intervalo-ms=300000
```

3. O novo status `expirado` precisa ser tratado no app e nos dashboards. Um `grep` por
   `"cancelado"` no `DashboardController` e no `RelatorioController` mostra onde a contagem
   por status vai precisar de mais um caso.

### `service/TurnoExpiracaoService.java` (novo)

```java
package com.motoshift.service;

import com.motoshift.entity.Turno;
import com.motoshift.entity.TurnoInscricao;
import com.motoshift.repository.TurnoInscricaoRepository;
import com.motoshift.repository.TurnoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Vencimento automático de turnos (SCRUM-19).
 *
 * Regras deliberadas:
 *  - Turno "aberto" que ninguém aceitou e cujo início já passou → "expirado".
 *  - Turno "aberto" parcialmente preenchido cujo início já passou → "aceito"
 *    (fecha as vagas remanescentes; quem já entrou continua valendo).
 *  - Turno "aceito"/"em_andamento" cujo fim já passou → NÃO muda de status.
 *    Finalizar dispara transação e pagamento; isso é decisão humana, o job só
 *    cobra o lojista via notificação.
 */
@Service
public class TurnoExpiracaoService {

    private static final Logger log = LoggerFactory.getLogger(TurnoExpiracaoService.class);

    private final TurnoRepository turnoRepo;
    private final TurnoInscricaoRepository inscricaoRepo;
    private final NotificacaoService notificacoes;

    public TurnoExpiracaoService(TurnoRepository turnoRepo,
                                 TurnoInscricaoRepository inscricaoRepo,
                                 NotificacaoService notificacoes) {
        this.turnoRepo = turnoRepo;
        this.inscricaoRepo = inscricaoRepo;
        this.notificacoes = notificacoes;
    }

    /** Turnos abertos cujo horário de início já passou. */
    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void expirarTurnosNaoPreenchidos() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> candidatos = turnoRepo.findByStatusAndDataInicioBefore("aberto", agora);
        int expirados = 0, fechados = 0;

        for (Turno t : candidatos) {
            long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), "aceito");

            if (ativas == 0) {
                t.setStatus("expirado");
                t.setExpiradoEm(agora);
                turnoRepo.save(t);
                expirados++;
                notificacoes.criarUnica(t.getLojistId(), "turno_expirado",
                        "Turno expirou sem entregador",
                        "O turno \"" + t.getTitulo() + "\" venceu sem ninguem aceitar. "
                                + "Republique com mais antecedencia ou revise o valor.",
                        "turno", t.getId());
            } else {
                // Parcialmente preenchido: fecha para novos aceites, mas o turno vale.
                t.setStatus("aceito");
                turnoRepo.save(t);
                fechados++;
                notificacoes.criarUnica(t.getLojistId(), "turno_lotado",
                        "Turno iniciado com vagas em aberto",
                        "O turno \"" + t.getTitulo() + "\" comecou com " + ativas
                                + " de " + t.getVagas() + " vagas preenchidas.",
                        "turno", t.getId());
            }
        }
        if (expirados > 0 || fechados > 0) {
            log.info("[expiracao] {} turnos expirados, {} fechados por inicio", expirados, fechados);
        }
    }

    /** Aviso 1h antes: turno ainda aberto e com vaga sobrando. */
    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void avisarTurnosProximosDoVencimento() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> proximos = turnoRepo.findByStatusAndDataInicioBetween(
                "aberto", agora, agora.plusHours(1));

        for (Turno t : proximos) {
            long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), "aceito");
            if (ativas >= t.getVagas()) continue;
            notificacoes.criarUnica(t.getLojistId(), "turno_vencendo",
                    "Turno comeca em menos de 1 hora",
                    "O turno \"" + t.getTitulo() + "\" ainda tem "
                            + (t.getVagas() - ativas) + " vaga(s) em aberto.",
                    "turno", t.getId());
        }
    }

    /** Turno que já terminou e ninguém finalizou: cobra o lojista. */
    @Scheduled(fixedDelayString = "${motoshift.expiracao.intervalo-ms:300000}")
    @Transactional
    public void cobrarFinalizacaoPendente() {
        LocalDateTime agora = LocalDateTime.now();
        List<Turno> vencidos = turnoRepo.findByStatusInAndDataFimBefore(
                List.of("aceito", "em_andamento"), agora);

        for (Turno t : vencidos) {
            notificacoes.criarUnica(t.getLojistId(), "turno_pendente_finalizacao",
                    "Turno terminou e aguarda finalizacao",
                    "O turno \"" + t.getTitulo() + "\" ja terminou. "
                            + "Finalize para liberar o pagamento dos entregadores.",
                    "turno", t.getId());

            for (TurnoInscricao ins : inscricaoRepo.findByTurnoIdAndStatus(t.getId(), "aceito")) {
                notificacoes.criarUnica(ins.getMotoboyId(), "turno_pendente_finalizacao",
                        "Turno terminou",
                        "O turno \"" + t.getTitulo() + "\" terminou e aguarda a "
                                + "finalizacao do lojista.",
                        "turno", t.getId());
            }
        }
    }
}
```

### Aviso sobre múltiplas instâncias

`@Scheduled` roda em **toda** instância da aplicação. Se em algum momento você subir mais
de um pod/dyno, os três jobs rodam em paralelo e podem duplicar notificação (a dedup de
`criarUnica` reduz, mas há corrida). Enquanto for instância única, está tudo bem — quando
escalar, use ShedLock ou mova para um job externo.

### Diff de `TurnoRepository.java`

As consultas deste passo (`findByStatusAndDataInicioBefore`,
`findByStatusInAndDataFimBefore`, `findByStatusAndDataInicioBetween`) já estão no diff
apresentado no Passo 3.

---

## Diff consolidado — `service/TurnoService.java`

Este arquivo é tocado pelos passos 2 (NPE), 3 (geo) e 5 (hooks de notificação).
O construtor ganha `NotificacaoService`, o que é uma mudança de assinatura — se você tiver
teste que instancia `TurnoService` na mão, ele precisa do parâmetro novo.

```diff
--- a/com/motoshift/service/TurnoService.java
+++ b/com/motoshift/service/TurnoService.java
@@ -12,6 +12,7 @@
 import com.motoshift.repository.TurnoInscricaoRepository;
 import com.motoshift.repository.TurnoRepository;
 import com.motoshift.repository.UsuarioRepository;
+import com.motoshift.util.GeoUtils;
 import org.springframework.http.HttpStatus;
 import org.springframework.stereotype.Service;
 import org.springframework.transaction.annotation.Transactional;
@@ -21,6 +22,7 @@
 import java.time.LocalDateTime;
 import java.time.LocalTime;
 import java.time.format.DateTimeFormatter;
+import java.time.format.DateTimeParseException;
 import java.util.Comparator;
 import java.util.List;
 import java.util.stream.Collectors;
@@ -34,17 +36,20 @@
     private final CarteiraRepository carteiraRepo;
     private final TransacaoRepository transacaoRepo;
     private final TurnoInscricaoRepository inscricaoRepo;
+    private final NotificacaoService notificacoes;
 
     public TurnoService(TurnoRepository turnoRepo,
                         UsuarioRepository usuarioRepo,
                         CarteiraRepository carteiraRepo,
                         TransacaoRepository transacaoRepo,
-                        TurnoInscricaoRepository inscricaoRepo) {
+                        TurnoInscricaoRepository inscricaoRepo,
+                        NotificacaoService notificacoes) {
         this.turnoRepo = turnoRepo;
         this.usuarioRepo = usuarioRepo;
         this.carteiraRepo = carteiraRepo;
         this.transacaoRepo = transacaoRepo;
         this.inscricaoRepo = inscricaoRepo;
+        this.notificacoes = notificacoes;
     }
 
     /**
@@ -53,9 +58,19 @@
      * todas as listagens exponham a ocupação real do turno.
      */
     private TurnoResponse toResponse(Turno t) {
+        return toResponse(t, null, null);
+    }
+
+    /**
+     * Igual ao anterior, mas preenche {@code distanciaKm} quando a requisição
+     * informou a posição do usuário (SCRUM-18).
+     */
+    private TurnoResponse toResponse(Turno t, Double origemLat, Double origemLng) {
         TurnoResponse r = TurnoResponse.from(t);
         long ativas = inscricaoRepo.countByTurnoIdAndStatus(t.getId(), "aceito");
         r.setVagasPreenchidas((int) ativas);
+        r.setDistanciaKm(GeoUtils.arredondar1(
+                GeoUtils.distanciaKm(origemLat, origemLng, t.getLatitude(), t.getLongitude())));
         return r;
     }
 
@@ -81,6 +96,18 @@
         t.setDataFim(req.getDataFim());
         t.setValorEstimado(req.getValorEstimado());
         t.setRaioEntregaKm(req.getRaioEntregaKm());
+
+        // Geolocalização (SCRUM-18): opcional, mas se vier tem que ser válida.
+        if (req.getLatitude() != null || req.getLongitude() != null) {
+            if (!GeoUtils.coordenadaValida(req.getLatitude(), req.getLongitude())) {
+                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
+                        "Latitude/longitude inválidas.");
+            }
+            t.setLatitude(req.getLatitude());
+            t.setLongitude(req.getLongitude());
+        }
+        t.setEndereco(req.getEndereco());
+
         int vagas = req.getVagas() == null ? 1 : req.getVagas();
         if (vagas < 1) vagas = 1;
         if (vagas > 20) vagas = 20; // teto de segurança
@@ -137,7 +164,18 @@
         if (ocupadas >= vagas) {
             turno.setStatus("aceito");
         }
-        return toResponse(turnoRepo.save(turno));
+        turnoRepo.save(turno);
+
+        // SCRUM-20: lojista é avisado de cada aceite.
+        String nomeMotoboy = usuarioRepo.findById(motoboyId)
+                .map(Usuario::getNome).orElse("Um entregador");
+        notificacoes.criar(turno.getLojistId(), "turno_aceito",
+                "Vaga preenchida",
+                nomeMotoboy + " aceitou o turno \"" + turno.getTitulo() + "\" ("
+                        + ocupadas + "/" + vagas + " vagas).",
+                "turno", turno.getId());
+
+        return toResponse(turno);
     }
 
     /**
@@ -192,9 +230,28 @@
             }
         }
 
+        for (Long destinatario : participantesDoTurno(turno)) {
+            notificacoes.criar(destinatario, "avaliacao_pendente",
+                    "Turno finalizado",
+                    "O turno \"" + turno.getTitulo() + "\" foi finalizado. "
+                            + "Confirme o pagamento e avalie a outra parte.",
+                    "turno", turno.getId());
+        }
+
         return toResponse(turno);
     }
 
+    /** Lojista + todos os entregadores não cancelados do turno. */
+    private List<Long> participantesDoTurno(Turno turno) {
+        java.util.LinkedHashSet<Long> ids = new java.util.LinkedHashSet<>();
+        if (turno.getLojistId() != null) ids.add(turno.getLojistId());
+        if (turno.getMotoboyId() != null) ids.add(turno.getMotoboyId());
+        for (TurnoInscricao ins : inscricaoRepo.findByTurnoId(turno.getId())) {
+            if (!"cancelado".equals(ins.getStatus())) ids.add(ins.getMotoboyId());
+        }
+        return new java.util.ArrayList<>(ids);
+    }
+
     private void criarTransacaoPendente(Turno turno, Long motoboyId) {
         if (motoboyId == null) return;
         Transacao tx = new Transacao();
@@ -291,6 +348,11 @@
         inscricaoRepo.save(ins);
         creditarCarteira(ins.getMotoboyId(), turno.getValorEstimado());
         marcarTransacaoProcessada(ins.getMotoboyId(), turno.getId());
+
+        notificacoes.criar(ins.getMotoboyId(), "pagamento_confirmado",
+                "Pagamento confirmado",
+                "O pagamento do turno \"" + turno.getTitulo() + "\" foi creditado na sua carteira.",
+                "carteira", turno.getId());
     }
 
     /** Turno vira "pago" quando todas as inscrições finalizadas foram pagas. */
@@ -384,7 +446,17 @@
         }
 
         turno.setStatus("cancelado");
-        return toResponse(turnoRepo.save(turno));
+        turnoRepo.save(turno);
+
+        // SCRUM-20: todo mundo que estava no turno precisa saber.
+        for (Long destinatario : participantesDoTurno(turno)) {
+            notificacoes.criar(destinatario, "turno_cancelado",
+                    "Turno cancelado",
+                    "O turno \"" + turno.getTitulo() + "\" foi cancelado.",
+                    "turno", turno.getId());
+        }
+
+        return toResponse(turno);
     }
 
     public List<TurnoResponse> listarDisponiveis() {
@@ -395,43 +467,85 @@
 
     public List<TurnoResponse> listarDisponiveisComFiltros(
             String horarioInicio, String horarioFim, Integer diaSemana,
-            Double raioMaxKm, String dataInicio, String dataFim, String ordenarPor) {
+            Double raioMaxKm, String dataInicio, String dataFim, String ordenarPor,
+            Double lat, Double lng, Double raioKm) {
+
+        // Filtro geográfico só liga se houver posição do usuário E raio.
+        final boolean geo = GeoUtils.coordenadaValida(lat, lng) && raioKm != null && raioKm > 0;
+
+        // Pré-filtro no banco: bounding box (usa índice) em vez de carregar
+        // todos os turnos abertos para a memória.
+        List<Turno> base;
+        if (geo) {
+            double dLat = GeoUtils.deltaLatitude(raioKm);
+            double dLng = GeoUtils.deltaLongitude(raioKm, lat);
+            base = turnoRepo.findAbertosNaArea(lat - dLat, lat + dLat, lng - dLng, lng + dLng);
+        } else {
+            base = turnoRepo.findByStatus("aberto");
+        }
 
         DateTimeFormatter hmFmt = DateTimeFormatter.ofPattern("HH:mm");
-        Stream<Turno> stream = turnoRepo.findByStatus("aberto").stream();
+        Stream<Turno> stream = base.stream();
 
-        if (horarioInicio != null && !horarioInicio.isBlank()) {
-            LocalTime hiTime = LocalTime.parse(horarioInicio, hmFmt);
-            stream = stream.filter(t -> !t.getDataInicio().toLocalTime().isBefore(hiTime));
-        }
-        if (horarioFim != null && !horarioFim.isBlank()) {
-            LocalTime hfTime = LocalTime.parse(horarioFim, hmFmt);
-            stream = stream.filter(t -> !t.getDataFim().toLocalTime().isAfter(hfTime));
+        try {
+            if (horarioInicio != null && !horarioInicio.isBlank()) {
+                LocalTime hiTime = LocalTime.parse(horarioInicio, hmFmt);
+                stream = stream.filter(t -> !t.getDataInicio().toLocalTime().isBefore(hiTime));
+            }
+            if (horarioFim != null && !horarioFim.isBlank()) {
+                LocalTime hfTime = LocalTime.parse(horarioFim, hmFmt);
+                stream = stream.filter(t -> !t.getDataFim().toLocalTime().isAfter(hfTime));
+            }
+            if (dataInicio != null && !dataInicio.isBlank()) {
+                LocalDate di = LocalDate.parse(dataInicio);
+                stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isBefore(di));
+            }
+            if (dataFim != null && !dataFim.isBlank()) {
+                LocalDate df = LocalDate.parse(dataFim);
+                stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isAfter(df));
+            }
+        } catch (DateTimeParseException e) {
+            // Antes isso virava 500. Formato ruim é erro do cliente.
+            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
+                    "Formato de data/hora inválido. Use HH:mm para horários e yyyy-MM-dd para datas.");
         }
+
         if (diaSemana != null) {
             stream = stream.filter(t -> t.getDataInicio().getDayOfWeek().getValue() == diaSemana);
         }
+
+        // raioEntregaKm é nullable: sem o teste de null isto lançava NPE no
+        // unboxing e derrubava a listagem inteira.
         if (raioMaxKm != null) {
-            stream = stream.filter(t -> t.getRaioEntregaKm() <= raioMaxKm);
+            stream = stream.filter(t -> t.getRaioEntregaKm() != null
+                    && t.getRaioEntregaKm() <= raioMaxKm);
         }
-        if (dataInicio != null && !dataInicio.isBlank()) {
-            LocalDate di = LocalDate.parse(dataInicio);
-            stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isBefore(di));
-        }
-        if (dataFim != null && !dataFim.isBlank()) {
-            LocalDate df = LocalDate.parse(dataFim);
-            stream = stream.filter(t -> !t.getDataInicio().toLocalDate().isAfter(df));
+
+        // Refino exato do raio: a bounding box é um quadrado, o raio é um círculo.
+        if (geo) {
+            stream = stream.filter(t -> {
+                Double d = GeoUtils.distanciaKm(lat, lng, t.getLatitude(), t.getLongitude());
+                return d != null && d <= raioKm;
+            });
         }
 
         Comparator<Turno> comparator = switch (ordenarPor != null ? ordenarPor : "") {
-            case "valorDesc"  -> Comparator.comparingDouble(Turno::getValorEstimado).reversed();
-            case "raioAsc"    -> Comparator.comparingDouble(Turno::getRaioEntregaKm);
-            case "dataInicio" -> Comparator.comparing(Turno::getDataInicio);
-            default           -> Comparator.comparingDouble(Turno::getValorEstimado);
+            case "valorDesc"    -> Comparator.comparing(Turno::getValorEstimado,
+                                       Comparator.nullsLast(Comparator.reverseOrder()));
+            case "raioAsc"      -> Comparator.comparing(Turno::getRaioEntregaKm,
+                                       Comparator.nullsLast(Comparator.naturalOrder()));
+            case "dataInicio"   -> Comparator.comparing(Turno::getDataInicio);
+            case "distanciaAsc" -> Comparator.comparingDouble((Turno t) -> {
+                                       Double d = GeoUtils.distanciaKm(
+                                               lat, lng, t.getLatitude(), t.getLongitude());
+                                       return d == null ? Double.MAX_VALUE : d;
+                                   });
+            default             -> Comparator.comparing(Turno::getValorEstimado,
+                                       Comparator.nullsLast(Comparator.naturalOrder()));
         };
 
         return stream.sorted(comparator)
-                .map(this::toResponse)
+                .map(t -> toResponse(t, geo ? lat : null, geo ? lng : null))
                 .collect(Collectors.toList());
     }
 
```

---

## Passo 6 — Índices

Não é um passo separado: as anotações `@Index` já estão nos diffs de `Turno` e `Avaliacao`
e no código novo de `Notificacao`. Consolidado aqui só para conferência.

| Tabela | Índice | Para quê |
|--------|--------|----------|
| `turnos` | `ix_turno_status_inicio (status, dataInicio)` | Listagem de disponíveis; job de expiração |
| `turnos` | `ix_turno_status_fim (status, dataFim)` | Job de cobrança de finalização |
| `turnos` | `ix_turno_geo (status, latitude, longitude)` | Pré-filtro por bounding box |
| `turnos` | `ix_turno_lojista (lojistId)` | `findByLojistId` |
| `turnos` | `ix_turno_motoboy (motoboyId)` | `findByMotoboyId`, `findConflitos` |
| `avaliacoes` | `uk_avaliacao_turno_avaliador_avaliado` (única) | Duplicata real |
| `avaliacoes` | `ix_avaliacao_avaliado (avaliadoId)` | Cálculo de média |
| `avaliacoes` | `ix_avaliacao_turno (turnoId)` | Avaliações do turno |
| `notificacoes` | `ix_notificacao_usuario (usuarioId, lida, criadoEm)` | Consulta do sino |
| `notificacoes` | `ix_notificacao_dedup (usuarioId, tipo, referenciaId)` | Deduplicação nos jobs |

> **Confira no primeiro boot.** O `columnList` usa os nomes de campo em camelCase, seguindo
> o padrão que o projeto já usa em `TurnoInscricao`. O Hibernate resolve isso pela naming
> strategy do Spring Boot (`dataInicio` → `data_inicio`), mas vale olhar os `CREATE INDEX`
> no log com `spring.jpa.show-sql=true` na primeira subida.

---

## Checklist de verificação

Depois de aplicar, confira nesta ordem:

**Passo 1 — avaliação**

- [ ] Turno com 2 vagas, finalizado: lojista consegue avaliar **os dois** entregadores
- [ ] Entregador que entrou na 2ª vaga consegue avaliar o lojista (antes: `403`)
- [ ] Avaliar o mesmo par duas vezes retorna `400`
- [ ] `avaliadorId == avaliadoId` retorna `400`
- [ ] O `CREATE UNIQUE INDEX` aparece no log sem erro

**Passos 2 e 3 — filtros**

- [ ] Turno com `raioEntregaKm` nulo na base: `GET /disponiveis?raioMaxKm=10` responde `200` (antes: `500`)
- [ ] `GET /disponiveis?ordenarPor=raioAsc` com turno de raio nulo responde `200`
- [ ] `GET /disponiveis?dataInicio=31-12-2026` responde `400`, não `500`
- [ ] `lat`/`lng`/`raioKm` devolvem só o que está dentro do raio, com `distanciaKm` batendo
- [ ] Sem `lat`/`lng`, a listagem continua idêntica à de antes

**Passo 4 — notificações**

- [ ] Aceitar um turno gera notificação para o lojista
- [ ] Cancelar gera notificação para lojista **e** todos os inscritos
- [ ] `GET /api/notificacoes/contagem` bate com o número de não lidas

**Passo 5 — vencimento**

- [ ] Turno aberto com `dataInicio` no passado e sem inscrito vira `expirado`
- [ ] Turno aberto parcialmente preenchido vira `aceito`, **não** `expirado`
- [ ] Turno `aceito` com `dataFim` no passado **continua** `aceito` (só notifica)
- [ ] Rodar o job duas vezes seguidas **não** duplica notificação

Para testar o job sem esperar 5 minutos, baixe o intervalo em
`application.properties` (`motoshift.expiracao.intervalo-ms=15000`) e crie turnos com data
no passado direto pelo H2 Console.

---

## Fora de escopo (próxima rodada)

Ficou de fora de propósito, com a razão:

| Item | Por que não agora |
|------|-------------------|
| Enums de status | Toca service, controllers e `DataInitializer`. Vale muito, mas é uma rodada só dele |
| `BigDecimal` no dinheiro | Mesma coisa, e mexe em `Carteira`, `Transacao`, dashboards e relatórios |
| Flyway | A adoção certa é *depois* das mudanças de schema acima, não durante |
| `@ManyToOne` no lugar dos `Long xxxId` | Alto custo, ganho baixo para estes 5 cards |
| Consolidar pagamento só em `TurnoInscricao` | Precisa de migração de dados dos turnos legados |
| `@Version` no `Turno` | `aceitar()` faz contar-depois-inserir sem lock: duas pessoas simultâneas estouram as vagas. Real, mas raro no volume atual |
| `ganhosMensais` na `Carteira` | Nunca é resetado — só incrementa. O certo é derivar de `Transacao` (o `grafico()` do `CarteiraService` já faz isso) e apagar o campo |

Duas coisas que notei e não entram em nenhum passo, mas ficam registradas:

- **`toResponse` faz um `COUNT` por turno.** Listar 200 turnos abertos = 201 queries. Vale
  trocar por um `GROUP BY` único quando a base crescer.
- **Senha em texto simples** em `Usuario` (o comentário no campo reconhece isso). Não é
  um dos cards do Jira, mas é o item de maior risco do backend hoje.
