package com.motoshift.config;

import com.motoshift.dto.ErroResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

/**
 * O corpo de erro da API inteira, em um lugar so.
 *
 * Cada rota lancava {@code ResponseStatusException} com um texto e ia embora.
 * O app so conseguia ler esse texto porque
 * {@code server.error.include-message=always} estava ligado nos dois
 * application.properties — a mensagem de "E-mail ja cadastrado" chegava a tela
 * por causa de uma linha de configuracao, nao de um contrato. Aqui o contrato
 * vira explicito ({@link ErroResponse}) e aquela propriedade sai.
 *
 * Nota sobre 401/403: quando a requisicao morre no Spring Security, o Spring
 * MVC nem chega a rodar e este handler nao e chamado. Quem responde la e o
 * {@code RespostaDeErro} do pacote security, escrevendo o mesmo formato de
 * proposito — o app le um objeto so, venha de onde vier.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    /** O caminho comum: as regras de negocio lancam isto o tempo todo. */
    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<ErroResponse> statusException(ResponseStatusException e) {
        HttpStatusCode status = e.getStatusCode();
        String mensagem = e.getReason() != null ? e.getReason() : padraoPara(status);

        return ResponseEntity.status(status)
                .body(ErroResponse.de(codigoPara(status), mensagem));
    }

    /**
     * Falha de {@code @Valid}. O ganho aqui e o campo: antes o app recebia o
     * texto agregado do Spring ("Validation failed for object...") e nao tinha
     * como destacar o input errado no formulario.
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErroResponse> validacao(MethodArgumentNotValidException e) {
        FieldError primeiro = e.getBindingResult().getFieldError();

        String campo = primeiro != null ? primeiro.getField() : null;
        String mensagem = primeiro != null && primeiro.getDefaultMessage() != null
                ? primeiro.getDefaultMessage()
                : "Dados invalidos.";

        return ResponseEntity.badRequest()
                .body(new ErroResponse("requisicao_invalida", mensagem, campo));
    }

    /**
     * Conflito da trava otimista da carteira.
     *
     * A Carteira ganhou {@code @Version} para impedir lost update: duas
     * operacoes simultaneas na mesma carteira — o entregador sacando enquanto o
     * lojista confirma um pagamento — faziam leitura-modificacao-escrita em
     * cima do mesmo saldo e uma sobrescrevia a outra em silencio.
     *
     * So que a trava sozinha resolve metade do problema: o lost update
     * silencioso virou um HTTP 500 generico, e 500 e "o servidor quebrou".
     * Aqui nao quebrou nada — duas pessoas mexeram no mesmo saldo ao mesmo
     * tempo, uma perdeu a corrida, e refazer a operacao funciona. Isso e 409.
     *
     * A escolha e por mapear em vez de {@code @Retryable}: repetir sozinho uma
     * operacao que mexe em dinheiro exige idempotencia de ponta a ponta (a
     * chave ja existe em Transacao, mas nem todo caminho a preenche). Devolver
     * 409 e deixar o cliente reenviar e o passo honesto enquanto isso nao esta
     * fechado.
     */
    @ExceptionHandler(ObjectOptimisticLockingFailureException.class)
    public ResponseEntity<ErroResponse> conflitoDeVersao(ObjectOptimisticLockingFailureException e) {
        // WARN e nao ERROR: e disputa esperada, nao falha do servico. Vale o
        // registro porque uma enxurrada disto aponta contencao real.
        log.warn("[carteira] conflito de versao em {}: {}",
                e.getPersistentClassName(), e.getMessage());

        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ErroResponse.de("conflito_de_versao",
                        "Outra operação alterou este saldo agora mesmo. Tente de novo."));
    }

    // Nao ha @ExceptionHandler(Exception.class) aqui de proposito: um catch-all
    // neste advice engoliria as excecoes que o proprio Spring MVC traduz em
    // status certos (405 de metodo errado, 404 de rota inexistente, 415 de
    // content-type) e devolveria 500 para todas elas. O que sobra sem
    // tratamento continua caindo no 500 padrao, que o app ja mapeia para
    // "Erro interno, tente novamente".

    /** Codigo estavel por status — o app decide fluxo sem parsear texto. */
    private static String codigoPara(HttpStatusCode status) {
        return switch (status.value()) {
            case 400 -> "requisicao_invalida";
            case 401 -> "nao_autenticado";
            case 403 -> "acesso_negado";
            case 404 -> "nao_encontrado";
            case 409 -> "conflito";
            case 429 -> "muitas_tentativas";
            case 503 -> "servico_indisponivel";
            default  -> status.is4xxClientError() ? "requisicao_invalida" : "erro_interno";
        };
    }

    private static String padraoPara(HttpStatusCode status) {
        return status.is4xxClientError()
                ? "Não foi possível concluir a operação."
                : "Erro interno, tente novamente.";
    }
}
