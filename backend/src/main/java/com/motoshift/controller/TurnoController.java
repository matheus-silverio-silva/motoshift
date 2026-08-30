package com.motoshift.controller;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.PagamentoTurnoService;
import com.motoshift.service.TurnoConsultaService;
import com.motoshift.service.TurnoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/turnos")
@Tag(name = "Turnos", description = "Gerenciamento de turnos de entrega (RF04-RF07)")
public class TurnoController {

    // Tres servicos e nao um: o TurnoService de 604 linhas foi dividido por
    // responsabilidade, e o controller passa a dizer qual delas esta chamando.
    private final TurnoService service;
    private final TurnoConsultaService consultas;
    private final PagamentoTurnoService pagamentos;

    public TurnoController(TurnoService service,
                           TurnoConsultaService consultas,
                           PagamentoTurnoService pagamentos) {
        this.service = service;
        this.consultas = consultas;
        this.pagamentos = pagamentos;
    }

    @Operation(summary = "Publicar turno", description = "Lojista cria turno com antecedência mínima de 2h (RF04).")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Turno criado"),
        @ApiResponse(responseCode = "400", description = "Antecedência insuficiente ou dados inválidos")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TurnoResponse criar(@Valid @RequestBody TurnoRequest req,
                               @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("lojista");
        return service.criar(req, atual.id());
    }

    @Operation(summary = "Listar turnos", description = "Filtra por lojistId, motoboyId ou retorna todos disponíveis.")
    @ApiResponse(responseCode = "200", description = "Lista de turnos")
    @GetMapping
    public List<TurnoResponse> listar(
            @RequestParam(required = false) Long lojistId,
            @RequestParam(required = false) Long motoboyId,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        // A agenda de alguem e dado privado: o filtro so aceita o proprio id.
        if (lojistId != null) {
            atual.exigirMesmoUsuario(lojistId);
            return consultas.listarPorLojista(lojistId);
        }
        if (motoboyId != null) {
            atual.exigirMesmoUsuario(motoboyId);
            return consultas.listarPorMotoboy(motoboyId);
        }
        return consultas.listarDisponiveis();
    }

    @Operation(summary = "Listar turnos disponíveis",
            description = "Turnos abertos com filtros opcionais de horário, dia da semana, "
                    + "período e proximidade. Informe lat+lng+raioKm para filtrar por "
                    + "distância real do usuário; a resposta traz distanciaKm em cada turno.")
    @ApiResponse(responseCode = "200", description = "Turnos disponíveis")
    @GetMapping("/disponiveis")
    public List<TurnoResponse> disponiveis(
            @RequestParam(required = false) String horarioInicio,
            @RequestParam(required = false) String horarioFim,
            @RequestParam(required = false) Integer diaSemana,
            @RequestParam(required = false) Double raioMaxKm,
            @RequestParam(required = false) String dataInicio,
            @RequestParam(required = false) String dataFim,
            @RequestParam(required = false) String ordenarPor,
            // SCRUM-18: posição do usuário (GPS do app) + raio de busca em km.
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lng,
            @RequestParam(required = false) Double raioKm) {

        boolean hasFilter = horarioInicio != null || horarioFim != null || diaSemana != null
                || raioMaxKm != null || dataInicio != null || dataFim != null
                || ordenarPor != null || lat != null || lng != null || raioKm != null;

        if (hasFilter) {
            return consultas.listarDisponiveisComFiltros(horarioInicio, horarioFim,
                    diaSemana, raioMaxKm, dataInicio, dataFim, ordenarPor, lat, lng, raioKm);
        }
        return consultas.listarDisponiveis();
    }

    @Operation(summary = "Buscar turno por ID")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno encontrado"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado")
    })
    @GetMapping("/{id}")
    public TurnoResponse buscar(@PathVariable Long id) {
        return consultas.buscarPorId(id);
    }

    @Operation(summary = "Aceitar turno", description = "Motoboy aceita turno disponível. Valida conflito de agenda (RF05).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno aceito"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno indisponível ou conflito de horário")
    })
    @PutMapping("/{id}/aceitar")
    public TurnoResponse aceitar(@PathVariable Long id,
                                 @AuthenticationPrincipal UsuarioAutenticado atual) {
        // O motoboyId que vinha no corpo era o furo mais direto da API:
        // trocar o numero aceitava o turno no lugar de outra pessoa.
        atual.exigirTipo("motoboy");
        return service.aceitar(id, atual.id());
    }

    @Operation(summary = "Finalizar turno", description = "Marca turno como finalizado e credita valor na carteira (RF06).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno finalizado"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno já encerrado")
    })
    @PutMapping("/{id}/finalizar")
    public TurnoResponse finalizar(@PathVariable Long id,
                                   @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.finalizar(id, atual.id());
    }

    @Operation(summary = "Cancelar turno", description = "Cancela turno. Penaliza score do motoboy se < 1h antes do início (RF07).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno cancelado"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno já encerrado")
    })
    @PutMapping("/{id}/cancelar")
    public TurnoResponse cancelar(@PathVariable Long id,
                                  @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.cancelar(id, atual.id());
    }

    @Operation(summary = "Lojista confirma pagamento",
            description = "Lojista declara que enviou o pagamento. Efetiva quando motoboy também confirmar.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Confirmação registrada"),
        @ApiResponse(responseCode = "403", description = "Usuário não é o lojista do turno"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno não finalizado, já pago ou já confirmado")
    })
    @PutMapping("/{id}/confirmar-pagamento-lojista")
    public TurnoResponse confirmarPagamentoLojista(
            @PathVariable Long id,
            @RequestBody Map<String, Long> body,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        // Quem confirma vem do token; do corpo sobra so o motoboyId, que aqui
        // nao e identidade e sim qual entregador do turno esta sendo pago.
        atual.exigirTipo("lojista");
        return pagamentos.confirmarPagamentoLojista(
                id, atual.id(), body.get("motoboyId"));
    }

    @Operation(summary = "Listar inscritos do turno",
            description = "Entregadores inscritos no turno, com status de pagamento de cada um.")
    @GetMapping("/{id}/inscritos")
    public List<Map<String, Object>> inscritos(@PathVariable Long id,
                                               @AuthenticationPrincipal UsuarioAutenticado atual) {
        return consultas.listarInscritos(id, atual.id());
    }

    @Operation(summary = "Motoboy confirma recebimento",
            description = "Motoboy declara que recebeu. Efetiva quando lojista também confirmar.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Confirmação registrada"),
        @ApiResponse(responseCode = "403", description = "Usuário não é o motoboy do turno"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno não finalizado, já pago ou já confirmado")
    })
    @PutMapping("/{id}/confirmar-recebimento-motoboy")
    public TurnoResponse confirmarRecebimentoMotoboy(
            @PathVariable Long id,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("motoboy");
        return pagamentos.confirmarRecebimentoMotoboy(id, atual.id());
    }
}
