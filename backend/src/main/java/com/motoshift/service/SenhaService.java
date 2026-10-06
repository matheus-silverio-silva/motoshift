package com.motoshift.service;

import com.motoshift.entity.CodigoRecuperacaoSenha;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.CodigoRecuperacaoSenhaRepository;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.service.email.EnvioDeEmail;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Optional;

/**
 * Trocar a senha sabendo a atual, e recuperá-la sem saber (SCRUM-32).
 *
 * <p>São dois caminhos com provas diferentes de que a pessoa é a dona da conta:
 *
 * <ul>
 *   <li><b>Trocar</b> — a prova é o token (está logada) mais a senha atual.
 *   <li><b>Recuperar</b> — a prova é ler a caixa de e-mail da conta: o backend
 *       gera um código de 6 dígitos, entrega por {@link EnvioDeEmail} e só
 *       quem o recebeu redefine a senha.
 * </ul>
 *
 * <p><b>O que a recuperação não revela.</b> {@link #pedirCodigo} não diz se o
 * e-mail tem conta, e {@link #redefinir} responde a mesma coisa para e-mail
 * desconhecido, código errado, vencido ou esgotado. Uma resposta diferente
 * para cada caso seria um oráculo: daria para descobrir quem tem conta e quem
 * tem pedido aberto. O tempo de resposta também é igualado — o BCrypt roda
 * exista ou não a conta.
 *
 * <p><b>Limite conhecido.</b> Seis dígitos com cinco tentativas por código dão
 * uma chance em 200 mil por código. O que segura a repetição é o intervalo
 * mínimo entre códigos da mesma conta ({@link #INTERVALO_ENTRE_CODIGOS_SEGUNDOS})
 * e o limite de requisições por IP da rota (SCRUM-36). Trocar a senha também
 * não derruba as sessões abertas: o JWT não tem revogação, e o token antigo
 * vale até vencer.
 */
@Service
public class SenhaService {

    /** O mesmo mínimo do cadastro ({@code RegistroRequest}). */
    public static final int TAMANHO_MINIMO = 6;

    public static final int VALIDADE_DO_CODIGO_MINUTOS = 15;

    /** Quantas vezes um código pode ser conferido. No quinto erro ele morre. */
    public static final int MAX_TENTATIVAS_POR_CODIGO = 5;

    /**
     * Um código novo para a mesma conta só depois deste intervalo.
     *
     * <p>Cada código novo invalida o anterior e traz cinco tentativas novas.
     * Sem intervalo, um laço em "esqueci minha senha" enche a caixa de entrada
     * da vítima, impede-a de usar qualquer código (o que ela recebe já foi
     * trocado) e ainda multiplica os palpites de quem está tentando adivinhar.
     * Dentro do intervalo o pedido é aceito e ignorado — a resposta continua
     * sendo 202, e o código já enviado continua valendo.
     */
    public static final int INTERVALO_ENTRE_CODIGOS_SEGUNDOS = 60;

    /** Uma só mensagem para toda falha da redefinição — ver o comentário da classe. */
    static final String CODIGO_INVALIDO = "Código inválido ou expirado. Peça um novo código.";

    private final UsuarioRepository usuarios;
    private final CodigoRecuperacaoSenhaRepository codigos;
    private final PasswordEncoder encoder;
    private final EnvioDeEmail email;
    private final TransactionTemplate transacao;
    private final SecureRandom sorteio = new SecureRandom();

    /** Hash de um código qualquer, para conferir "contra nada" no mesmo tempo. */
    private final String hashDeNinguem;

    public SenhaService(UsuarioRepository usuarios,
                        CodigoRecuperacaoSenhaRepository codigos,
                        PasswordEncoder encoder,
                        EnvioDeEmail email,
                        TransactionTemplate transacao) {
        this.usuarios = usuarios;
        this.codigos = codigos;
        this.encoder = encoder;
        this.email = email;
        this.transacao = transacao;
        this.hashDeNinguem = encoder.encode(novoCodigo());
    }

    /**
     * Troca a senha de quem está logado.
     *
     * <p>Senha atual errada é 400, e não 401: a pessoa ESTÁ autenticada — o
     * que está errado é um campo do formulário. E não conta como tentativa de
     * login: o contador do RF01 protege a porta de entrada, e trancar a conta
     * de quem já está dentro por errar um campo só puniria o dono.
     */
    @Transactional
    public void trocar(Long usuarioId, String senhaAtual, String senhaNova) {
        validarNova(senhaNova);
        Usuario u = usuarios.findById(usuarioId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Usuário não encontrado"));

        if (senhaAtual == null || u.getSenha() == null || !encoder.matches(senhaAtual, u.getSenha())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A senha atual não confere.");
        }

        usuarios.trocarSenha(u.getId(), encoder.encode(senhaNova));
        // Um código pedido antes da troca não sobrevive a ela.
        codigos.apagarDoUsuario(u.getId());
    }

    /**
     * "Esqueci minha senha": gera o código e o envia. Nunca diz se a conta existe.
     *
     * <p>O hash é calculado ANTES de procurar a conta, para os dois casos
     * custarem o mesmo: se o BCrypt só rodasse quando a conta existe, o tempo
     * de resposta contaria o que o status 202 esconde.
     */
    @Transactional
    public void pedirCodigo(String emailInformado) {
        String codigo = novoCodigo();
        String hash = encoder.encode(codigo);

        Optional<Usuario> conta = usuarios.findByEmail(Usuario.normalizarEmail(emailInformado));
        if (conta.isEmpty()) return;
        Usuario u = conta.get();

        LocalDateTime agora = LocalDateTime.now();
        Optional<CodigoRecuperacaoSenha> anterior = codigos.findFirstByUsuarioIdOrderByIdDesc(u.getId());
        if (anterior.isPresent() && anterior.get().getCriadoEm()
                .plusSeconds(INTERVALO_ENTRE_CODIGOS_SEGUNDOS).isAfter(agora)) {
            return;
        }

        codigos.apagarDoUsuario(u.getId());
        codigos.save(new CodigoRecuperacaoSenha(
                u.getId(), hash, agora, agora.plusMinutes(VALIDADE_DO_CODIGO_MINUTOS)));

        email.enviar(u.getEmail(), "MotoShift — código para redefinir a senha",
                "Olá, " + u.getNome() + ".\n\n"
              + "Seu código para redefinir a senha do MotoShift é: " + codigo + "\n\n"
              + "Ele vale por " + VALIDADE_DO_CODIGO_MINUTOS + " minutos e só pode ser usado uma vez. "
              + "Se não foi você quem pediu, ignore esta mensagem — sua senha continua a mesma.");
    }

    /**
     * Redefine a senha com o código recebido.
     *
     * <p>Sem {@code @Transactional} de propósito: a tentativa gasta precisa
     * ficar gravada mesmo quando o método termina em exceção (é o caso do
     * código errado). Só o final — senha nova e código apagado — é atômico.
     *
     * <p>A ordem é: gastar a tentativa, DEPOIS conferir. Conferindo antes,
     * palpites simultâneos passariam todos pelo limite.
     */
    public void redefinir(String emailInformado, String codigoInformado, String senhaNova) {
        validarNova(senhaNova);
        String palpite = codigoInformado == null ? "" : codigoInformado.trim();

        Optional<CodigoRecuperacaoSenha> pedido = usuarios
                .findByEmail(Usuario.normalizarEmail(emailInformado))
                .flatMap(u -> codigos.findFirstByUsuarioIdOrderByIdDesc(u.getId()));

        boolean podeConferir = pedido.isPresent()
                && !pedido.get().expirou(LocalDateTime.now())
                && codigos.gastarTentativa(pedido.get().getId(), MAX_TENTATIVAS_POR_CODIGO) == 1;

        // Sem conta, sem pedido, vencido ou esgotado: confere contra nada, só
        // para a resposta levar o mesmo tempo de um código errado.
        boolean confere = encoder.matches(palpite,
                podeConferir ? pedido.get().getCodigoHash() : hashDeNinguem) && podeConferir;

        if (!confere) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, CODIGO_INVALIDO);
        }

        Long usuarioId = pedido.get().getUsuarioId();
        String hash = encoder.encode(senhaNova);
        transacao.executeWithoutResult(status -> {
            // Quem redefiniu a senha provou que é o dono: o bloqueio por
            // tentativas de login (RF01) sai junto, senão a pessoa trocaria a
            // senha e continuaria 15 minutos do lado de fora.
            usuarios.redefinirSenha(usuarioId, hash);
            codigos.apagarDoUsuario(usuarioId);
        });
    }

    private static void validarNova(String senhaNova) {
        if (senhaNova == null || senhaNova.length() < TAMANHO_MINIMO) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A senha deve ter no mínimo " + TAMANHO_MINIMO + " caracteres");
        }
    }

    /** Seis dígitos, com os zeros à esquerda: "004217" é um código válido. */
    private String novoCodigo() {
        return String.format("%06d", sorteio.nextInt(1_000_000));
    }
}
