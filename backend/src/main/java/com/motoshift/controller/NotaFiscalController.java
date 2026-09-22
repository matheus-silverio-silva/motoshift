package com.motoshift.controller;

import com.motoshift.dto.InformeAnualResponse;
import com.motoshift.dto.NotaFiscalFiltro;
import com.motoshift.dto.NotaFiscalPendenteResponse;
import com.motoshift.dto.NotaFiscalResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.NotaFiscalService;
import com.motoshift.service.fiscal.InformeRendimentosService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Nota fiscal de serviço dos turnos.
 *
 * Nenhuma rota recebe o id do usuário: quem pergunta sai do token, e é ele que
 * define o que a resposta traz — as notas em que a pessoa é prestadora ou
 * tomadora, e nada além disso.
 */
@RestController
@RequestMapping("/api/notas-fiscais")
@Tag(name = "Notas fiscais", description = "Emissão e consulta de NFS-e dos turnos concluídos")
public class NotaFiscalController {

    private final NotaFiscalService service;
    private final InformeRendimentosService informes;

    public NotaFiscalController(NotaFiscalService service, InformeRendimentosService informes) {
        this.service = service;
        this.informes = informes;
    }

    @Operation(summary = "Minhas notas fiscais (SIMULADAS)",
            description = "Notas em que o usuário é prestador (entregador) ou tomador (lojista), "
                    + "da competência mais recente para a mais antiga. Filtros: papel "
                    + "(prestador|tomador), competenciaDe/competenciaAte (data do serviço, "
                    + "yyyy-MM-dd), status (emitida|cancelada), contraparteId, turnoId. "
                    + "Paginação opcional, como no resto da API: com ?pagina=0&tamanho=20 o total "
                    + "vai no header X-Total-Count; sem pagina, a lista inteira.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Lista de notas"),
        @ApiResponse(responseCode = "400", description = "Filtro inválido")
    })
    @GetMapping
    public ResponseEntity<List<NotaFiscalResponse>> listar(
            NotaFiscalFiltro filtro,
            @RequestParam(required = false) Integer pagina,
            @RequestParam(required = false) Integer tamanho,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        Pageable pedido = Paginacao.pedido(pagina, tamanho);
        var notas = service.listar(atual.id(), filtro, pedido);
        return pedido == null ? ResponseEntity.ok(notas.getContent()) : Paginacao.resposta(notas);
    }

    @Operation(summary = "Informe anual (SIMULADO)",
            description = "Para o entregador, informe de rendimentos: o que recebeu no ano, por "
                    + "fonte pagadora e por mês, com o IRRF e o ISS retidos. Para o lojista, "
                    + "o total de serviços tomados por prestador. A base é o extrato (data do "
                    + "crédito), e não as notas: pagamento sem nota ainda conta como rendimento.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Informe do ano"),
        @ApiResponse(responseCode = "400", description = "Ano fora do intervalo")
    })
    @GetMapping("/resumo")
    public InformeAnualResponse resumo(@RequestParam(required = false) Integer ano,
                                       @AuthenticationPrincipal UsuarioAutenticado atual) {
        return informes.informe(atual.id(), atual.isLojista(), ano);
    }

    @Operation(summary = "Exportar o informe anual em CSV (SIMULADO)",
            description = "O mesmo informe de /resumo, separado por ';'.")
    @ApiResponse(responseCode = "200", description = "Arquivo CSV")
    @GetMapping("/resumo/exportar")
    public ResponseEntity<String> exportarResumo(@RequestParam(required = false) Integer ano,
                                                 @AuthenticationPrincipal UsuarioAutenticado atual) {
        int oAno = ano == null ? java.time.Year.now().getValue() : ano;
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"informe-" + oAno + ".csv\"")
                .contentType(new MediaType("text", "csv", java.nio.charset.StandardCharsets.UTF_8))
                .body(informes.exportarCsv(atual.id(), atual.isLojista(), oAno));
    }

    @Operation(summary = "Turnos a emitir",
            description = "Turnos finalizados que ainda não geraram nota. "
                    + "O lojista recebe um item por entregador do turno.")
    @ApiResponse(responseCode = "200", description = "Pendências de emissão")
    @GetMapping("/pendentes")
    public List<NotaFiscalPendenteResponse> pendentes(
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.pendentes(atual.id(), atual.isLojista());
    }

    @Operation(summary = "Emitir nota fiscal",
            description = "Emite a NFS-e do turno. Os dois lados podem emitir: o documento é "
                    + "sempre o mesmo, com o entregador como prestador e o lojista como tomador. "
                    + "Idempotente — pedir de novo devolve a nota já emitida, com 200.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Nota emitida"),
        @ApiResponse(responseCode = "200", description = "Nota já existia; devolvida como está"),
        @ApiResponse(responseCode = "403", description = "Usuário não participou do turno"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno ainda não finalizado")
    })
    @PostMapping
    public ResponseEntity<NotaFiscalResponse> emitir(
            @RequestBody Map<String, Object> body,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        Long turnoId = numero(body.get("turnoId"));
        if (turnoId == null) {
            return ResponseEntity.badRequest().build();
        }
        NotaFiscalService.Emissao r =
                service.emitir(turnoId, numero(body.get("prestadorId")), atual.id());
        return ResponseEntity
                .status(r.criada() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(r.nota());
    }

    @Operation(summary = "Consultar nota fiscal")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Nota encontrada"),
        @ApiResponse(responseCode = "403", description = "A nota não é do usuário"),
        @ApiResponse(responseCode = "404", description = "Nota não encontrada")
    })
    @GetMapping("/{id}")
    public NotaFiscalResponse buscar(@PathVariable Long id,
                                     @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.buscar(id, atual.id());
    }

    @Operation(summary = "Cancelar nota fiscal",
            description = "Só o prestador do serviço cancela a própria nota.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Nota cancelada"),
        @ApiResponse(responseCode = "403", description = "Apenas o prestador pode cancelar"),
        @ApiResponse(responseCode = "409", description = "Nota já cancelada")
    })
    @PutMapping("/{id}/cancelar")
    public NotaFiscalResponse cancelar(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body,
                                       @AuthenticationPrincipal UsuarioAutenticado atual) {
        String motivo = body == null ? null : body.get("motivo");
        return service.cancelar(id, motivo, atual.id());
    }

    /** O JSON pode trazer o id como Integer ou Long dependendo do cliente. */
    private Long numero(Object valor) {
        if (valor instanceof Number n) return n.longValue();
        if (valor instanceof String s && !s.isBlank()) {
            try {
                return Long.parseLong(s.trim());
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }
}
