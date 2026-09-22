package com.motoshift.controller;

import com.motoshift.dto.CarteiraResponse;
import com.motoshift.dto.CobrancaResponse;
import com.motoshift.dto.ExtratoFiltro;
import com.motoshift.dto.FluxoPontoResponse;
import com.motoshift.dto.ResumoFinanceiroResponse;
import com.motoshift.dto.TransacaoResponse;
import com.motoshift.dto.DocumentoResponse;
import com.motoshift.service.fiscal.DocumentoFiscalService;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.CarteiraService;
import com.motoshift.service.CobrancaService;
import com.motoshift.service.ExtratoService;
import com.motoshift.service.ledger.RetentativaOtimista;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
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
    private final ExtratoService extrato;
    private final DocumentoFiscalService documentos;

    public CarteiraController(CarteiraService service,
                              CobrancaService cobrancas,
                              RetentativaOtimista retentativa,
                              ExtratoService extrato,
                              DocumentoFiscalService documentos) {
        this.service = service;
        this.cobrancas = cobrancas;
        this.retentativa = retentativa;
        this.extrato = extrato;
        this.documentos = documentos;
    }

    // ── Documento de um lançamento ───────────────────────────────────────────

    @Operation(summary = "Gerar o documento de um lançamento (SIMULADO)",
            description = "Emite — ou devolve, se já existir — o documento do lançamento: "
                    + "NFS-e para pagamento de turno (a mesma nota nos dois lados: o "
                    + "entregador pelo pagamento_recebido, o lojista pelo pagamento_enviado), "
                    + "recibo para recarga, comprovante Pix para saque concluído e comprovante "
                    + "de movimentação para o resto. Reserva e liberação não são serviço "
                    + "prestado e nunca geram nota. Idempotente. Tudo simulado: nenhuma "
                    + "transmissão à prefeitura ou à Receita, e o documento traz a marca "
                    + "\"DOCUMENTO SIMULADO — SEM VALOR FISCAL\".")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "NFS-e emitida agora"),
        @ApiResponse(responseCode = "200", description = "Documento que já existia (ou comprovante, que é derivado)"),
        @ApiResponse(responseCode = "403", description = "O lançamento não é do usuário"),
        @ApiResponse(responseCode = "404", description = "Lançamento não encontrado"),
        @ApiResponse(responseCode = "409", description = "Lançamento sem documento ainda (não concluído, Pix pendente)")
    })
    @PostMapping("/transacoes/{id}/documento")
    public ResponseEntity<DocumentoResponse> gerarDocumento(
            @PathVariable Long id,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        DocumentoFiscalService.Resultado r = documentos.emitir(id, atual.id());
        return ResponseEntity.status(r.criado() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(r.documento());
    }

    @Operation(summary = "Consultar o documento de um lançamento (SIMULADO)",
            description = "O documento já gerado. Comprovante sempre existe (é derivado do "
                    + "lançamento); NFS-e responde 404 até ser gerada pelo POST.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Documento"),
        @ApiResponse(responseCode = "403", description = "O lançamento não é do usuário"),
        @ApiResponse(responseCode = "404", description = "Lançamento não encontrado, ou NFS-e ainda não gerada"),
        @ApiResponse(responseCode = "409", description = "Lançamento sem documento ainda")
    })
    @GetMapping("/transacoes/{id}/documento")
    public DocumentoResponse documento(@PathVariable Long id,
                                       @AuthenticationPrincipal UsuarioAutenticado atual) {
        return documentos.buscar(id, atual.id());
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

    // ── Extrato ──────────────────────────────────────────────────────────────

    @Operation(summary = "Extrato filtrado e paginado",
            description = "Lançamentos do usuário autenticado, do mais recente para o mais "
                    + "antigo. Todos os filtros são opcionais e combináveis: dataInicio, "
                    + "dataFim (ambos inclusivos), tipos (lista), status, natureza "
                    + "(credito|debito), turnoId, contraparteId, valorMin, valorMax e busca "
                    + "(texto na descrição). O total vem no header X-Total-Count. O filtro "
                    + "roda no banco — antes o app baixava o extrato inteiro e escondia "
                    + "linhas na tela.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Página do extrato"),
        @ApiResponse(responseCode = "400", description = "Filtro inválido")
    })
    @GetMapping("/extrato")
    public ResponseEntity<List<TransacaoResponse>> extratoFiltrado(
            ExtratoFiltro filtro,
            @RequestParam(defaultValue = "0") int pagina,
            @RequestParam(required = false) Integer tamanho,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        Pageable pedido = PageRequest.of(Math.max(pagina, 0),
                tamanho == null ? 20 : Math.max(tamanho, 1));
        return Paginacao.resposta(extrato.extrato(atual.id(), filtro, pedido));
    }

    @Operation(summary = "Exportar o extrato em CSV",
            description = "Mesmos filtros de /extrato, sem paginação — exportar meia página "
                    + "não exporta nada. Separador ';' porque o Excel em português usa a "
                    + "vírgula como separador decimal.")
    @ApiResponse(responseCode = "200", description = "Arquivo CSV")
    @GetMapping("/extrato/exportar")
    public ResponseEntity<String> exportarExtrato(
            ExtratoFiltro filtro,
            @RequestParam(defaultValue = "csv") String formato,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        if (!"csv".equalsIgnoreCase(formato)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Formato não suportado: use csv.");
        }
        String csv = extrato.exportarCsv(atual.id(), filtro);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"extrato.csv\"")
                .contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .body(csv);
    }

    @Operation(summary = "Resumo financeiro do período",
            description = "Entradas, saídas e líquido do período, mais o retrato atual da "
                    + "carteira: disponível, bloqueado, a receber (entregador: turnos aceitos "
                    + "ainda não finalizados) e comprometido (lojista: reservas abertas, com "
                    + "a lista por turno). Sem datas, usa os últimos 30 dias.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Resumo do período"),
        @ApiResponse(responseCode = "400", description = "Data final anterior à inicial")
    })
    @GetMapping("/resumo")
    public ResumoFinanceiroResponse resumo(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataInicio,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataFim,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return extrato.resumo(atual.id(), dataInicio, dataFim);
    }

    @Operation(summary = "Série de fluxo de caixa",
            description = "Entradas e saídas agrupadas por dia, semana ou mês, somadas no "
                    + "banco. Períodos sem lançamento vêm com zero, para o gráfico não "
                    + "mentir sobre o intervalo. Sem datas, usa os últimos 30 dias.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Série do gráfico"),
        @ApiResponse(responseCode = "400", description = "Agrupamento ou período inválido")
    })
    @GetMapping("/fluxo")
    public List<FluxoPontoResponse> fluxo(
            @RequestParam(defaultValue = "dia") String agrupamento,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataInicio,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataFim,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return extrato.fluxo(atual.id(), agrupamento, dataInicio, dataFim);
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
