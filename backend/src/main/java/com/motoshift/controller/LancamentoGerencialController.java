package com.motoshift.controller;

import com.motoshift.dto.CategoriaResponse;
import com.motoshift.dto.LancamentoGerencialRequest;
import com.motoshift.dto.LancamentoGerencialResponse;
import com.motoshift.security.UsuarioAutenticado;
import com.motoshift.service.LancamentoGerencialService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

/**
 * Os custos e as receitas que o usuário informa para a DRE (RF13 / SCRUM-47).
 *
 * <p>Nenhuma rota recebe id de usuário nem papel: os dois saem do token
 * ({@link UsuarioAutenticado}). O papel decide quais categorias existem; o
 * id, de quem é cada lançamento — o de outra pessoa responde 404.
 */
@RestController
@RequestMapping("/api/financeiro")
@Tag(name = "Resultado financeiro",
     description = "DRE simplificada (lucro ou prejuízo) e lançamentos gerenciais (RF13 / SCRUM-47)")
public class LancamentoGerencialController {

    private final LancamentoGerencialService service;

    public LancamentoGerencialController(LancamentoGerencialService service) {
        this.service = service;
    }

    @Operation(summary = "Categorias de lançamento",
               description = "As categorias que o papel do token pode lançar, com rótulo e "
                       + "grupo da DRE — o app monta o formulário com elas.")
    @GetMapping("/categorias")
    public List<CategoriaResponse> categorias(@AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.categorias(atual.tipo());
    }

    @Operation(summary = "Lançamentos do período",
               description = "O que o usuário informou e que conta no período: os avulsos com "
                       + "a data dentro dele e os recorrentes com ocorrência nele (cada um com "
                       + "ocorrenciasNoPeriodo e valorNoPeriodo). Sem datas, o mês corrente. "
                       + "Paginação opcional (?pagina=&tamanho=), com o total em X-Total-Count.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Os lançamentos, do mais recente para o mais antigo"),
        @ApiResponse(responseCode = "400", description = "Data final anterior à inicial")
    })
    @GetMapping("/lancamentos")
    public ResponseEntity<List<LancamentoGerencialResponse>> listar(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataInicio,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataFim,
            @RequestParam(required = false) Integer pagina,
            @RequestParam(required = false) Integer tamanho,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        // A recorrência é resolvida em memória (ver LancamentoGerencialRepository),
        // então a página é uma fatia do resultado já filtrado.
        return Paginacao.fatia(service.listar(atual.id(), dataInicio, dataFim),
                Paginacao.pedido(pagina, tamanho));
    }

    @Operation(summary = "Informar um custo ou uma receita",
               description = "Não é transação: não move saldo, não entra no extrato e não gera "
                       + "documento fiscal. Só alimenta a DRE.")
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Lançamento criado"),
        @ApiResponse(responseCode = "400", description = "Dados inválidos, categoria de outro papel "
                + "ou turno de que o usuário não participou")
    })
    @PostMapping("/lancamentos")
    public ResponseEntity<LancamentoGerencialResponse> criar(
            @Valid @RequestBody LancamentoGerencialRequest req,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(service.criar(atual.id(), atual.tipo(), req));
    }

    @Operation(summary = "Editar um lançamento")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Lançamento atualizado"),
        @ApiResponse(responseCode = "400", description = "Dados inválidos"),
        @ApiResponse(responseCode = "404", description = "Não existe, ou é de outro usuário")
    })
    @PutMapping("/lancamentos/{id}")
    public LancamentoGerencialResponse atualizar(
            @PathVariable Long id,
            @Valid @RequestBody LancamentoGerencialRequest req,
            @AuthenticationPrincipal UsuarioAutenticado atual) {
        return service.atualizar(id, atual.id(), atual.tipo(), req);
    }

    @Operation(summary = "Excluir um lançamento")
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "Lançamento excluído"),
        @ApiResponse(responseCode = "404", description = "Não existe, ou é de outro usuário")
    })
    @DeleteMapping("/lancamentos/{id}")
    public ResponseEntity<Void> excluir(@PathVariable Long id,
                                        @AuthenticationPrincipal UsuarioAutenticado atual) {
        service.excluir(id, atual.id());
        return ResponseEntity.noContent().build();
    }
}
