package com.motoshift.service;

import com.motoshift.dto.CobrancaResponse;
import com.motoshift.entity.Carteira;
import com.motoshift.entity.Cobranca;
import com.motoshift.entity.StatusCobranca;
import com.motoshift.entity.TipoCobranca;
import com.motoshift.repository.CobrancaRepository;
import com.motoshift.service.gateway.CobrancaPix;
import com.motoshift.service.gateway.GatewayPagamento;
import com.motoshift.service.ledger.LedgerService;
import com.motoshift.service.ledger.Movimento;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Recarga e saque: as duas portas por onde o dinheiro entra e sai da
 * plataforma.
 *
 * <p>Tudo o que acontece entre elas — reserva, liquidação, liberação — é
 * transferência interna e não passa por aqui. É por isso que a invariante (c)
 * consegue ser tão simples: a soma de todas as carteiras só muda por recarga,
 * saque e estorno, e os três nascem neste arquivo.
 *
 * <p><b>Recarga é em dois tempos, de propósito.</b> Criar a cobrança não
 * credita nada; o crédito só acontece quando a confirmação chega. Num provedor
 * real esse segundo tempo é o webhook, que pode chegar duas vezes, fora de
 * ordem, ou nunca. A confirmação aqui é idempotente pelo mesmo motivo que lá:
 * o dinheiro entra uma vez por cobrança, quantas vezes o aviso chegar.
 *
 * <p><b>Saque debita antes de pedir.</b> Se o débito viesse depois da resposta
 * do gateway, entre uma coisa e outra o mesmo saldo poderia ser sacado de novo
 * ou gasto num turno. Debitar primeiro fecha essa janela; quando o gateway
 * recusa, um lançamento de estorno devolve o valor. O débito recusado continua
 * no extrato — ele aconteceu.
 */
@Service
public class CobrancaService {

    private static final Logger log = LoggerFactory.getLogger(CobrancaService.class);

    /** Valor mínimo de saque (RF: R$ 20,00). */
    private static final BigDecimal SAQUE_MINIMO = new BigDecimal("20.00");

    /**
     * Teto por recarga.
     *
     * Não é regra de negócio herdada: é contenção. O gateway é simulado e
     * confirmar uma recarga não custa nada, então sem teto uma conta poderia
     * criar saldo arbitrário e tornar sem sentido qualquer número da
     * demonstração.
     */
    private static final BigDecimal RECARGA_MAXIMA = new BigDecimal("10000.00");

    private final CobrancaRepository cobrancaRepo;
    private final CarteiraService carteiras;
    private final LedgerService ledger;
    private final GatewayPagamento gateway;

    public CobrancaService(CobrancaRepository cobrancaRepo,
                           CarteiraService carteiras,
                           LedgerService ledger,
                           GatewayPagamento gateway) {
        this.cobrancaRepo = cobrancaRepo;
        this.carteiras = carteiras;
        this.ledger = ledger;
        this.gateway = gateway;
    }

    // -- Recarga -------------------------------------------------------------

    /** Abre a cobrança Pix. Não move saldo nenhum: ninguém pagou ainda. */
    @Transactional
    public CobrancaResponse criarRecarga(Long usuarioId, BigDecimal valor, String chaveDoCliente) {
        exigirValorDeRecarga(valor);

        String chave = chaveDoPedido("recarga", usuarioId, chaveDoCliente);
        Cobranca existente = cobrancaRepo.findByIdempotencyKey(chave).orElse(null);
        if (existente != null) {
            // Duplo toque no botão ou retry depois de um timeout: devolve a
            // mesma cobrança, com o mesmo código Pix, em vez de abrir outra.
            return CobrancaResponse.from(existente);
        }

        CobrancaPix pix = gateway.criarCobrancaPix(usuarioId, valor);

        Cobranca cobranca = new Cobranca();
        cobranca.setUsuarioId(usuarioId);
        cobranca.setTipo(TipoCobranca.RECARGA);
        cobranca.setValor(valor);
        cobranca.setStatus(StatusCobranca.PENDENTE);
        cobranca.setCodigoPix(pix.codigoCopiaECola());
        cobranca.setIdempotencyKey(chave);

        return CobrancaResponse.from(salvar(cobranca));
    }

    /**
     * Confirma o pagamento da cobrança — o que o webhook do provedor faria.
     *
     * <p>Idempotente em dois níveis: a cobrança já concluída devolve o mesmo
     * resultado sem passar pelo ledger, e o próprio lançamento tem chave
     * determinística ({@code recarga:{id}}). Confirmar duas vezes credita uma.
     */
    @Transactional
    public CobrancaResponse confirmarRecarga(Long usuarioId, Long cobrancaId) {
        Cobranca cobranca = exigirCobranca(usuarioId, cobrancaId);

        if (cobranca.getTipo() != TipoCobranca.RECARGA) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Esta cobrança é um saque, não uma recarga.");
        }
        if (cobranca.getStatus() == StatusCobranca.CONCLUIDO) {
            return CobrancaResponse.from(cobranca);
        }
        if (cobranca.getStatus() == StatusCobranca.FALHOU) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Esta cobrança falhou e não pode ser confirmada. Gere uma nova recarga.");
        }

        ledger.aplicar(Movimento.recarga(usuarioId, cobranca.getValor(), cobranca.getId()));

        cobranca.setStatus(StatusCobranca.CONCLUIDO);
        cobranca.setConcluidaEm(LocalDateTime.now());
        return CobrancaResponse.from(cobrancaRepo.save(cobranca));
    }

    // -- Saque ---------------------------------------------------------------

    /**
     * Saque via Pix: debita, pede ao gateway, e estorna se ele recusar.
     *
     * @param chaveDoCliente vem do header {@code Idempotency-Key}; com ela, o
     *                       mesmo pedido repetido devolve o resultado do
     *                       primeiro em vez de sacar de novo
     */
    @Transactional
    public CobrancaResponse sacar(Long usuarioId, BigDecimal valor, String chaveDoCliente) {
        if (valor == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Informe o valor do saque.");
        }
        // compareTo, nunca equals: equals considera a escala, então
        // new BigDecimal("20.0").equals(new BigDecimal("20.00")) é false.
        if (valor.compareTo(SAQUE_MINIMO) < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Valor mínimo para saque é R$ 20,00.");
        }

        String chave = chaveDoPedido("saque", usuarioId, chaveDoCliente);
        Cobranca existente = cobrancaRepo.findByIdempotencyKey(chave).orElse(null);
        if (existente != null) {
            return CobrancaResponse.from(existente);
        }

        Carteira carteira = carteiras.obterOuCriar(usuarioId);
        if (carteira.getChavePix() == null || carteira.getChavePix().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Cadastre uma chave Pix antes de solicitar saque.");
        }
        // O saque sai do disponível: o bloqueado está comprometido com turnos.
        // O ledger recusaria de qualquer forma; aqui a mensagem tem contexto.
        if (carteira.getSaldoDisponivel().compareTo(valor) < 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Saldo insuficiente para saque. Você tem "
                            + LedgerService.emReais(carteira.getSaldoDisponivel())
                            + " disponível e pediu " + LedgerService.emReais(valor) + ".");
        }

        Cobranca cobranca = new Cobranca();
        cobranca.setUsuarioId(usuarioId);
        cobranca.setTipo(TipoCobranca.SAQUE);
        cobranca.setValor(valor);
        cobranca.setStatus(StatusCobranca.PENDENTE);
        cobranca.setCodigoPix(carteira.getChavePix());
        cobranca.setIdempotencyKey(chave);
        cobranca = salvar(cobranca);

        // Debita ANTES de pedir ao gateway: fecha a janela em que o mesmo saldo
        // poderia ser sacado de novo ou gasto num turno.
        ledger.aplicar(Movimento.saque(
                usuarioId, valor, carteira.getChavePix(), cobranca.getId()));

        GatewayPagamento.ResultadoTransferencia resultado = gateway.transferirPix(
                carteira.getChavePix(), valor, "saque:" + cobranca.getId());

        if (resultado.aprovada()) {
            cobranca.setStatus(StatusCobranca.CONCLUIDO);
        } else {
            // O débito NÃO é apagado nem marcado como estornado: ele aconteceu.
            // O estorno é um segundo lançamento, e as duas linhas juntas somam
            // zero — que é a verdade, e o que mantém as invariantes valendo sem
            // uma exceção para "saque que não valeu".
            log.warn("[saque] cobranca {} recusada pelo gateway: {}",
                    cobranca.getId(), resultado.motivo());
            ledger.aplicar(Movimento.estornoDeSaque(usuarioId, valor, cobranca.getId()));
            cobranca.setStatus(StatusCobranca.FALHOU);
        }
        cobranca.setConcluidaEm(LocalDateTime.now());
        return CobrancaResponse.from(cobrancaRepo.save(cobranca));
    }

    // -- Consulta ------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<CobrancaResponse> listar(Long usuarioId) {
        return cobrancaRepo.findByUsuarioIdOrderByCriadaEmDesc(usuarioId).stream()
                .map(CobrancaResponse::from)
                .toList();
    }

    // -- Apoio ---------------------------------------------------------------

    private void exigirValorDeRecarga(BigDecimal valor) {
        if (valor == null || valor.signum() <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Informe um valor de recarga maior que zero.");
        }
        if (valor.compareTo(RECARGA_MAXIMA) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Valor máximo por recarga é " + LedgerService.emReais(RECARGA_MAXIMA) + ".");
        }
    }

    private Cobranca exigirCobranca(Long usuarioId, Long cobrancaId) {
        Cobranca cobranca = cobrancaRepo.findById(cobrancaId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Cobrança não encontrada."));

        // 404 e não 403: quem não é dono não precisa descobrir que a cobrança
        // existe. O dono vem do token, nunca do corpo.
        if (!cobranca.getUsuarioId().equals(usuarioId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Cobrança não encontrada.");
        }
        return cobranca;
    }

    private Cobranca salvar(Cobranca cobranca) {
        try {
            return cobrancaRepo.saveAndFlush(cobranca);
        } catch (DataIntegrityViolationException e) {
            // Dois pedidos com a mesma chave passaram juntos pela checagem
            // acima; o índice único barra o segundo aqui.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Este pedido já está sendo processado.");
        }
    }

    /**
     * Chave de idempotência do PEDIDO.
     *
     * <p>Sem {@code Idempotency-Key} do cliente, a chave carrega um UUID: duas
     * recargas de R$ 100 no mesmo minuto são dois pedidos legítimos, e tratá-las
     * como repetição seria recusar dinheiro que o usuário quis colocar. A
     * proteção contra o duplo toque depende, aí sim, de o cliente mandar a
     * chave — o app manda.
     *
     * <p>Isto é diferente da idempotência do LANÇAMENTO, que é sempre
     * determinística ({@code recarga:{cobrancaId}}): mesmo que dois pedidos
     * virem duas cobranças, cada uma credita no máximo uma vez.
     */
    private static String chaveDoPedido(String prefixo, Long usuarioId, String chaveDoCliente) {
        if (chaveDoCliente == null || chaveDoCliente.isBlank()) {
            return prefixo + ":" + usuarioId + ":" + UUID.randomUUID();
        }
        // O usuário entra na chave: a mesma string vinda de duas contas são dois
        // pedidos diferentes, e nunca um "já processado" do vizinho.
        return prefixo + ":" + usuarioId + ":" + chaveDoCliente.trim();
    }
}
