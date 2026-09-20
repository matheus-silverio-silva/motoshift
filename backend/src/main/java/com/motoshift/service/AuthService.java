package com.motoshift.service;

import com.motoshift.dto.AuthResponse;
import com.motoshift.dto.LoginRequest;
import com.motoshift.dto.PerfilPublicoResponse;
import com.motoshift.dto.RegistroRequest;
import com.motoshift.dto.UsuarioResponse;
import com.motoshift.entity.Usuario;
import com.motoshift.repository.UsuarioRepository;
import com.motoshift.security.JwtService;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

@Service
public class AuthService {

    private static final int MAX_TENTATIVAS = 5;
    private static final int BLOQUEIO_MINUTOS = 15;

    private final UsuarioRepository repo;
    private final CarteiraService carteiras;
    private final PasswordEncoder encoder;
    private final JwtService jwt;

    public AuthService(UsuarioRepository repo,
                       CarteiraService carteiras,
                       PasswordEncoder encoder,
                       JwtService jwt) {
        this.repo = repo;
        this.carteiras = carteiras;
        this.encoder = encoder;
        this.jwt = jwt;
    }

    /**
     * Cadastro. Transacional porque grava duas coisas: o usuario e a carteira
     * dele. Sem isso, uma falha na criacao da carteira deixava o usuario
     * gravado e sem carteira — e o retry do cadastro respondia "E-mail ja
     * cadastrado", com a pessoa presa sem conseguir nem entrar nem repetir.
     */
    @Transactional
    public AuthResponse registrar(RegistroRequest req) {
        if (repo.existsByEmail(req.getEmail())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "E-mail já cadastrado");
        }

        // RF03 — Lojista exige CNPJ (14 dígitos); Motoboy exige CNH (11 dígitos)
        String tipoNorm = req.getTipo() == null ? "" : req.getTipo().toLowerCase();
        String doc = req.getDocumentoFederal();
        String digitos = doc == null ? "" : doc.replaceAll("\\D", "");

        if ("lojista".equals(tipoNorm)) {
            if (doc == null || doc.isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNPJ é obrigatório para cadastro como Lojista.");
            }
            if (digitos.length() != 14) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNPJ inválido. Deve conter 14 dígitos.");
            }
        } else if ("motoboy".equals(tipoNorm)) {
            if (doc == null || doc.isBlank()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNH é obrigatória para cadastro como Motoboy.");
            }
            if (digitos.length() != 11) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "CNH inválida. Deve conter 11 dígitos.");
            }
        } else {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Tipo de usuário inválido. Use 'lojista' ou 'motoboy'.");
        }

        Usuario u = new Usuario();
        u.setNome(req.getNome());
        u.setEmail(req.getEmail());
        u.setTelefone(req.getTelefone());
        u.setTipo(req.getTipo().toLowerCase());
        u.setDocumentoFederal(req.getDocumentoFederal());
        u.setSenha(encoder.encode(req.getSenha()));

        Usuario salvo = repo.save(u);

        // Carteira para QUALQUER usuario, nao so entregador: o lojista precisa
        // dela para reservar o valor do turno ao publicar. Criada zerada aqui
        // para que nenhum fluxo posterior precise lidar com carteira ausente.
        carteiras.obterOuCriar(salvo.getId());

        return new AuthResponse(tokenPara(salvo), UsuarioResponse.from(salvo));
    }

    /**
     * Login com bloqueio por tentativas (RF01).
     *
     * O estado do bloqueio mora na linha do usuario (tentativas_login,
     * bloqueado_ate). Antes era um ConcurrentHashMap: sumia a cada deploy, cada
     * replica contava as suas 5 tentativas e a chave era o e-mail DIGITADO — um
     * laco com e-mails inventados enchia a memoria. Agora so conta tentativa
     * quem tem conta, e o contador e o mesmo para todas as instancias.
     *
     * Limite conhecido e aceito: bloquear por conta permite que alguem que sabe
     * o seu e-mail erre a senha 5 vezes e o deixe 15 minutos fora. E o custo do
     * RF01 como esta escrito (bloqueio da conta). Mitigar pede sinal que o
     * backend nao tem hoje — IP confiavel atras do proxy do Railway, captcha ou
     * segundo fator — e fica registrado como evolucao, nao como descuido.
     *
     * E-mail inexistente responde 401 sem contador: nao ha conta para bloquear,
     * e fingir "4 tentativas restantes" nao esconderia nada — o cadastro ja
     * responde "E-mail ja cadastrado" para quem quiser descobrir.
     */
    public AuthResponse login(LoginRequest req) {
        String email = req.getEmail() != null ? req.getEmail().trim() : "";
        Usuario u = repo.findByEmail(email)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                        "Credenciais inválidas."));

        LocalDateTime agora = LocalDateTime.now();
        if (u.getBloqueadoAte() != null && agora.isBefore(u.getBloqueadoAte())) {
            long minutos = ChronoUnit.MINUTES.between(agora, u.getBloqueadoAte()) + 1;
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Conta bloqueada. Tente novamente em " + minutos + " minuto(s).");
        }

        if (!senhaConfere(u, req.getSenha())) {
            int tentativas = u.getTentativasLogin() + 1;
            if (tentativas >= MAX_TENTATIVAS) {
                repo.bloquearLogin(u.getId(), agora.plusMinutes(BLOQUEIO_MINUTOS));
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "Muitas tentativas incorretas. Tente novamente em " + BLOQUEIO_MINUTOS + " minuto(s).");
            }
            repo.registrarFalhaDeLogin(u.getId());
            int restantes = MAX_TENTATIVAS - tentativas;
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                    "Credenciais inválidas. " + restantes + " tentativa(s) restante(s).");
        }

        // Sucesso zera o contador — so escreve se houver o que zerar, para o
        // login normal nao virar um UPDATE a cada entrada.
        if (u.getTentativasLogin() > 0 || u.getBloqueadoAte() != null) {
            repo.liberarLogin(u.getId());
        }
        return new AuthResponse(tokenPara(u), UsuarioResponse.from(u));
    }

    /** Perfil completo — so para o proprio usuario (ver UsuarioController). */
    public UsuarioResponse buscarPorId(Long id) {
        return UsuarioResponse.from(carregar(id));
    }

    /** Perfil reduzido, o unico que uma conta ve de outra. */
    public PerfilPublicoResponse buscarPerfilPublico(Long id) {
        return PerfilPublicoResponse.from(carregar(id));
    }

    private Usuario carregar(Long id) {
        return repo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));
    }

    public UsuarioResponse atualizar(Long id, java.util.Map<String, Object> body) {
        Usuario u = repo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Usuário não encontrado"));

        // SEGURANÇA: campos abaixo são IMUTÁVEIS após o cadastro (anti-fraude).
        // Qualquer envio é silenciosamente ignorado:
        //   - documentoFederal (CNPJ/CNH)
        //   - email, tipo
        //   - cnhNumero, cnhCategoria, cnhValidade (dados legais da CNH)

        if (body.get("nome") instanceof String s && !s.isBlank()) u.setNome(s);
        if (body.get("telefone") instanceof String s) u.setTelefone(s);
        if (body.get("fotoPerfil") instanceof String s) u.setFotoPerfil(s);

        if (body.get("dataNascimento") instanceof String s && !s.isBlank()) {
            u.setDataNascimento(java.time.LocalDate.parse(s));
        }
        if (body.get("cidade") instanceof String s) u.setCidade(s);
        if (body.get("estado") instanceof String s) u.setEstado(s);

        // Veículo: editável (motoboy pode trocar de moto)
        if (body.get("veiculoModelo") instanceof String s) u.setVeiculoModelo(s);
        if (body.get("veiculoPlaca") instanceof String s) u.setVeiculoPlaca(s);
        if (body.get("veiculoAno") instanceof Number n) u.setVeiculoAno(n.intValue());
        if (body.get("veiculoCor") instanceof String s) u.setVeiculoCor(s);

        if (body.get("nomeFantasia") instanceof String s) u.setNomeFantasia(s);
        if (body.get("enderecoComercial") instanceof String s) u.setEnderecoComercial(s);

        return UsuarioResponse.from(repo.save(u));
    }

    private String tokenPara(Usuario u) {
        return jwt.gerar(u.getId(), u.getEmail(), u.getTipo());
    }

    /**
     * Só BCrypt.
     *
     * Existia aqui um segundo ramo que comparava a senha em texto puro e a
     * regravava com hash — para não trancar as contas criadas no Railway antes
     * do BCrypt. Ele mantinha um comparador de senha em claro no caminho crítico
     * da autenticação. A migração V9 fez essa conversão de uma vez, no banco, e
     * o ramo saiu: uma senha que não seja hash simplesmente não confere.
     */
    private boolean senhaConfere(Usuario u, String informada) {
        String armazenada = u.getSenha();
        if (armazenada == null || informada == null) return false;
        return encoder.matches(informada, armazenada);
    }
}
