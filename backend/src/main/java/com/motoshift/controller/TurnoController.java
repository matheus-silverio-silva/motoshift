package com.motoshift.controller;

import com.motoshift.dto.TurnoRequest;
import com.motoshift.dto.TurnoResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.TurnoConsultaService;
import com.motoshift.service.TurnoService;
import com.motoshift.service.ledger.RetentativaOtimista;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/turnos")
@Tag(name = "Turnos", description = "Gerenciamento de turnos de entrega (RF04-RF07)")
public class TurnoController {

    // Dois servicos e nao um: o TurnoService de 604 linhas foi dividido por
    // responsabilidade, e o controller passa a dizer qual delas esta chamando.
    private final TurnoService service;
    private final TurnoConsultaService consultas;

    /**
     * As tres rotas que movem dinheiro passam por aqui.
     *
     * <p>O retry mora no controller porque e ele que abre a transacao: quando o
     * @Version da carteira falha, a transacao inteira ja esta condenada, e
     * repetir so o trecho do ledger commitaria uma metade. Ver
     * {@link RetentativaOtimista}.
     */
    private final RetentativaOtimista retentativa;

    public TurnoController(TurnoService service,
                           TurnoConsultaService consultas,
                           RetentativaOtimista retentativa) {
        this.service = service;
        this.consultas = consultas;
        this.retentativa = retentativa;
    }

    @Operation(summary = "Publicar turno",
            description = "Lojista cria turno com antecedência mínima de 2h (RF04). "
                    + "Publicar RESERVA o custo total (valor × vagas): o dinheiro sai do "
                    + "saldo disponível e fica bloqueado até o turno ser finalizado, "
                    + "cancelado ou expirar. Turno sem lastro não é publicado.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Turno criado e valor reservado"),
        @ApiResponse(responseCode = "400", description = "Antecedência insuficiente ou dados inválidos"),
        @ApiResponse(responseCode = "422", description = "Saldo insuficiente para reservar o turno — "
                + "a mensagem diz quanto falta")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TurnoResponse criar(@Valid @RequestBody TurnoRequest req,
                               @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirTipo("lojista");
        return retentativa.executar("publicar turno", () -> service.criar(req, atual.id()));
    }

    @Operation(summary = "Listar turnos",
            description = "Filtra por lojistId, motoboyId ou retorna todos disponíveis. "
                    + "Informe pagina (e opcionalmente tamanho) para paginar; sem pagina, "
                    + "a lista vem inteira. O total vai no header X-Total-Count.")
    @ApiResponse(responseCode = "200", description = "Lista de turnos")
    @GetMapping
    public ResponseEntity<List<TurnoResponse>> listar(
            @RequestParam(required = false) Long lojistId,
            @RequestParam(required = false) Long motoboyId,
            @RequestParam(required = false) Integer pagina,
            @RequestParam(required = false) Integer tamanho,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        Pageable pedido = Paginacao.pedido(pagina, tamanho);

        // A agenda de alguem e dado privado: o filtro so aceita o proprio id.
        if (lojistId != null) {
            atual.exigirMesmoUsuario(lojistId);
            return Paginacao.resposta(consultas.listarPorLojista(lojistId, pedido));
        }
        if (motoboyId != null) {
            atual.exigirMesmoUsuario(motoboyId);
            return Paginacao.resposta(consultas.listarPorMotoboy(motoboyId, pedido));
        }
        return Paginacao.resposta(consultas.listarDisponiveis(pedido));
    }

    @Operation(summary = "Listar turnos disponíveis",
            description = "Turnos abertos com filtros opcionais de horário, dia da semana, "
                    + "período e proximidade. Informe lat+lng+raioKm para filtrar por "
                    + "distância real do usuário; a resposta traz distanciaKm em cada turno.")
    @ApiResponse(responseCode = "200", description = "Turnos disponíveis")
    @GetMapping("/disponiveis")
    public ResponseEntity<List<TurnoResponse>> disponiveis(
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
            @RequestParam(required = false) Double raioKm,
            @RequestParam(required = false) Integer pagina,
            @RequestParam(required = false) Integer tamanho) {

        boolean hasFilter = horarioInicio != null || horarioFim != null || diaSemana != null
                || raioMaxKm != null || dataInicio != null || dataFim != null
                || ordenarPor != null || lat != null || lng != null || raioKm != null;

        Pageable pedido = Paginacao.pedido(pagina, tamanho);
        if (hasFilter) {
            // Parte dos filtros (horário, dia da semana, raio exato) roda em
            // memória, então a página é cortada depois deles.
            return Paginacao.fatia(consultas.listarDisponiveisComFiltros(horarioInicio, horarioFim,
                    diaSemana, raioMaxKm, dataInicio, dataFim, ordenarPor, lat, lng, raioKm), pedido);
        }
        return Paginacao.resposta(consultas.listarDisponiveis(pedido));
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

    @Operation(summary = "Finalizar turno",
            description = "Encerra o turno e LIQUIDA o pagamento na mesma transação: para cada "
                    + "entregador que trabalhou, o valor sai do saldo bloqueado do lojista e "
                    + "entra no disponível do entregador. O que foi reservado para vagas não "
                    + "preenchidas volta ao disponível do lojista. Qualquer um dos dois "
                    + "participantes pode finalizar — o dinheiro já estava reservado desde a "
                    + "publicação, então finalizar só transfere o que o lojista comprometeu. "
                    + "Repetir a chamada não paga duas vezes (RF06).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno finalizado e pagamentos liquidados"),
        @ApiResponse(responseCode = "403", description = "Usuário não participa do turno"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno já encerrado")
    })
    @PutMapping("/{id}/finalizar")
    public TurnoResponse finalizar(@PathVariable Long id,
                                   @AuthenticationPrincipal UsuarioAutenticado atual) {
        return retentativa.executar("finalizar turno", () -> service.finalizar(id, atual.id()));
    }

    @Operation(summary = "Cancelar turno",
            description = "Cancela o turno e devolve a reserva inteira ao saldo disponível do "
                    + "lojista. Penaliza o score do motoboy se < 1h antes do início; não há "
                    + "multa financeira (RF07).")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Turno cancelado e reserva liberada"),
        @ApiResponse(responseCode = "404", description = "Turno não encontrado"),
        @ApiResponse(responseCode = "409", description = "Turno já encerrado")
    })
    @PutMapping("/{id}/cancelar")
    public TurnoResponse cancelar(@PathVariable Long id,
                                  @AuthenticationPrincipal UsuarioAutenticado atual) {
        return retentativa.executar("cancelar turno", () -> service.cancelar(id, atual.id()));
    }

    @Operation(summary = "Listar inscritos do turno",
            description = "Entregadores inscritos no turno, com status de pagamento de cada um.")
    @GetMapping("/{id}/inscritos")
    public List<Map<String, Object>> inscritos(@PathVariable Long id,
                                               @AuthenticationPrincipal UsuarioAutenticado atual) {
        return consultas.listarInscritos(id, atual.id());
    }

    // As rotas PUT /{id}/confirmar-pagamento-lojista e
    // PUT /{id}/confirmar-recebimento-motoboy foram removidas.
    //
    // Elas existiam porque o pagamento dependia de as duas partes declararem
    // que o dinheiro tinha mudado de mãos fora do app. Com a liquidação
    // automática não há o que declarar: o lojista compromete o valor ao
    // publicar e a finalização transfere o que já estava reservado. Uma
    // confirmação que não decide nada só adiaria o pagamento de quem trabalhou.
    //
    // A V13 removeu as colunas que as sustentavam (turno_inscricoes.
    // lojista_confirmou_em / motoboy_confirmou_em).
}
