package com.motoshift.controller;

import com.motoshift.service.ledger.ConsistenciaService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Conferencia das invariantes do ledger — so em desenvolvimento.
 *
 * <p>{@code @Profile("dev")} nao e excesso de zelo: a conferencia varre todas as
 * carteiras e todos os lancamentos, entao e trabalho O(banco inteiro) atras de
 * uma URL. Util para o desenvolvedor, para a massa de demonstracao e para a
 * banca ver o numero fechando ao vivo; nada disso justifica existir em
 * producao. Em producao esta classe nem e instanciada.
 */
@RestController
@RequestMapping("/api/dev/ledger")
@Profile("dev")
@Tag(name = "Ledger (dev)", description = "Conferência das invariantes financeiras — apenas no perfil dev")
public class ConsistenciaController {

    private final ConsistenciaService consistencia;

    public ConsistenciaController(ConsistenciaService consistencia) {
        this.consistencia = consistencia;
    }

    @Operation(summary = "Verificar consistência do ledger",
            description = "Confere as três invariantes: (a) nenhum saldo negativo; "
                    + "(b) saldo de cada carteira igual à soma dos lançamentos concluídos "
                    + "daquele usuário; (c) soma de todas as carteiras igual a recargas "
                    + "menos saques mais estornos. Responde 200 quando tudo fecha e 409 "
                    + "com a lista do que não fecha.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Ledger consistente"),
        @ApiResponse(responseCode = "409", description = "Há divergências — a lista vem no corpo")
    })
    @GetMapping("/consistencia")
    public ResponseEntity<Map<String, Object>> verificar() {
        ConsistenciaService.Resultado r = consistencia.verificarConsistencia();

        Map<String, Object> corpo = new LinkedHashMap<>();
        corpo.put("consistente", r.consistente());
        corpo.put("problemas", r.problemas());
        corpo.put("totais", r.totais());

        // 409 e nao 500: o servidor esta inteiro e respondeu bem; quem esta em
        // conflito e o estado dos dados.
        return ResponseEntity
                .status(r.consistente() ? HttpStatus.OK : HttpStatus.CONFLICT)
                .body(corpo);
    }
}
