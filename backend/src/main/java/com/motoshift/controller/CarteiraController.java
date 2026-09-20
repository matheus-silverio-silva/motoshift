package com.motoshift.controller;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.dto.CobrancaResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.CarteiraService;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.ledger.RetentativaOtimista;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/carteira")
@Tag(name = "Carteira", description = "Saldo, saques e histórico financeiro do usuário")
public class CarteiraController {

    private final CarteiraService service;
    private final CobrancaService cobrancas;

    /** Ver {@link RetentativaOtimista}: o retry mora em quem abre a transação. */
    private final RetentativaOtimista retentativa;

    public CarteiraController(CarteiraService service,
                              CobrancaService cobrancas,
                              RetentativaOtimista retentativa) {
        this.service = service;
        this.cobrancas = cobrancas;
        this.retentativa = retentativa;
    }

    // ── Recarga ──────────────────────────────────────────────────────────────

    @Operation(summary = "Criar recarga (Pix simulado)",
            description = "Abre uma cobrança Pix e devolve o código copia-e-cola. NÃO credita "
                    + "saldo: a cobrança nasce pendente e o dinheiro só entra quando o "
                    + "pagamento for confirmado. Envie o header Idempotency-Key para que "
                    + "repetir o pedido devolva a mesma cobrança em vez de abrir outra.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Cobrança criada, aguardando pagamento"),
        @ApiResponse(responseCode = "400", description = "Valor ausente, zero, negativo ou acima do teto")
    })
    @PostMapping("/recargas")
    @ResponseStatus(HttpStatus.CREATED)
    public CobrancaResponse criarRecarga(
            @RequestBody Map<String, BigDecimal> body,
            @Parameter(description = "Identificador do pedido gerado pelo cliente.")
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        // O dono sai do token. Não há usuarioId no caminho nem no corpo: era
        // por ali que se recarregava a carteira de outra pessoa.
        return cobrancas.criarRecarga(atual.id(), body.get("valor"), idempotencyKey);
    }

    @Operation(summary = "Confirmar recarga (simula o webhook)",
            description = "Simula o aviso de pagamento que o provedor enviaria. Credita o valor "
                    + "no saldo disponível. É idempotente: confirmar a mesma cobrança duas "
                    + "vezes credita uma vez — pelo mesmo motivo que um webhook real precisa "
                    + "ser idempotente, já que o aviso pode chegar repetido.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Recarga confirmada e saldo creditado"),
        @ApiResponse(responseCode = "404", description = "Cobrança não encontrada"),
        @ApiResponse(responseCode = "409", description = "A cobrança é um saque ou já falhou")
    })
    @PostMapping("/recargas/{id}/confirmar")
    public CobrancaResponse confirmarRecarga(@PathVariable Long id,
                                             @AuthenticationPrincipal UsuarioAutenticado atual) {
        return retentativa.executar("confirmar recarga",
                () -> cobrancas.confirmarRecarga(atual.id(), id));
    }

    @Operation(summary = "Listar recargas e saques",
            description = "Cobranças do usuário no gateway, da mais recente para a mais antiga.")
    @ApiResponse(responseCode = "200", description = "Lista de cobranças")
    @GetMapping("/cobrancas")
    public List<CobrancaResponse> listarCobrancas(@AuthenticationPrincipal UsuarioAutenticado atual) {
        return cobrancas.listar(atual.id());
    }

    // ── Saque ────────────────────────────────────────────────────────────────

    @Operation(summary = "Solicitar saque",
            description = "Debita o valor do saldo disponível e envia o Pix pelo gateway. "
                    + "Mínimo R$ 20,00 e chave Pix obrigatória. Se o gateway recusar, um "
                    + "lançamento de estorno devolve o valor — o débito recusado permanece "
                    + "no extrato, porque ele aconteceu. Substitui POST /{usuarioId}/saque.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Saque processado — veja status "
                + "(concluido ou falhou) na resposta"),
        @ApiResponse(responseCode = "400", description = "Mínimo não atingido ou sem chave Pix"),
        @ApiResponse(responseCode = "422", description = "Saldo disponível insuficiente")
    })
    @PostMapping("/saques")
    @ResponseStatus(HttpStatus.CREATED)
    public CobrancaResponse sacar(
            @RequestBody Map<String, BigDecimal> body,
            @Parameter(description = "Identificador do pedido gerado pelo cliente. Repetir o "
                    + "mesmo valor devolve o resultado do primeiro saque sem debitar de novo.")
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return retentativa.executar("sacar",
                () -> cobrancas.sacar(atual.id(), body.get("valor"), idempotencyKey));
    }

    @Operation(summary = "Consultar carteira", description = "Retorna saldo atual, ganhos mensais e histórico de transações.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Dados da carteira"),
        @ApiResponse(responseCode = "404", description = "Motoboy não encontrado")
    })
    @GetMapping("/{usuarioId}")
    public CarteiraResponse buscar(@PathVariable Long usuarioId,
                                  @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return service.buscar(usuarioId);
    }

    @Operation(summary = "Solicitar saque (descontinuado)",
            deprecated = true,
            description = "Mantido enquanto o app não migra para POST /api/carteira/saques, que "
                    + "é a rota de verdade — esta apenas delega para ela e reembala a resposta "
                    + "no formato antigo ({mensagem, novoSaldo}). Sai quando o app migrar.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Saque processado"),
        @ApiResponse(responseCode = "400", description = "Mínimo não atingido ou sem chave Pix"),
        @ApiResponse(responseCode = "422", description = "Saldo disponível insuficiente")
    })
    @Deprecated
    @PostMapping("/{usuarioId}/saque")
    public Map<String, Object> saque(
            @PathVariable Long usuarioId,
            @RequestBody Map<String, BigDecimal> body,
            @Parameter(description = "Identificador do pedido gerado pelo cliente. Repetir o "
                    + "mesmo valor devolve o resultado do primeiro saque sem debitar de novo.")
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return retentativa.executar("sacar (rota antiga)",
                () -> service.saque(usuarioId, body.get("valor"), idempotencyKey));
    }

    @Operation(summary = "Extrato paginado",
               description = "Lançamentos do mais recente para o mais antigo. O total vem no "
                           + "header X-Total-Count.")
    @GetMapping("/{usuarioId}/transacoes")
    public ResponseEntity<List<TransacaoResponse>> extrato(
            @PathVariable Long usuarioId,
            @RequestParam(defaultValue = "0") int pagina,
            @RequestParam(required = false) Integer tamanho,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return Paginacao.resposta(service.extrato(usuarioId, Paginacao.pedido(pagina, tamanho)));
    }

    @Operation(summary = "Atualizar chave Pix", description = "Cadastra ou atualiza a chave Pix para saques.")
    @ApiResponse(responseCode = "200", description = "Chave Pix atualizada")
    @PutMapping("/{usuarioId}/pix")
    public Map<String, String> atualizarPix(
            @PathVariable Long usuarioId,
            @RequestBody Map<String, String> body,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        service.atualizarPix(usuarioId, body.get("chavePix"));
        return Map.of("mensagem", "Chave Pix atualizada com sucesso!");
    }

    @Operation(summary = "Gráfico de ganhos mensais", description = "Retorna ganhos por turno agrupados por mês (últimos N meses).")
    @ApiResponse(responseCode = "200", description = "Dados do gráfico")
    @GetMapping("/{usuarioId}/grafico")
    public List<Map<String, Object>> grafico(
            @PathVariable Long usuarioId,
            @RequestParam(defaultValue = "6") int meses,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        atual.exigirMesmoUsuario(usuarioId);
        return service.grafico(usuarioId, meses);
    }
}
