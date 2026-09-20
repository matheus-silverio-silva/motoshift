package com.motoshift.dto;

import com.motoshift.entity.Usuario;

/**
 * O que uma conta pode ver do perfil de OUTRA conta.
 *
 * O {@link UsuarioResponse} completo carrega CPF/CNPJ, número e validade da
 * CNH, data de nascimento, e-mail, telefone e endereço. A rota GET
 * /api/usuarios/{id} devolvia isso para qualquer token válido: bastava iterar
 * ids para montar uma base de documentos de todos os cadastrados — exatamente o
 * tipo de tratamento que a LGPD pede para não existir sem finalidade.
 *
 * A finalidade real de ler um perfil alheio é o lojista saber quem aceitou o
 * turno (e o entregador saber para quem vai rodar). Para isso bastam nome,
 * foto, reputação e o veículo que vai aparecer na porta. Tudo o que identifica
 * a pessoa fora da plataforma fica de fora; o perfil completo continua saindo
 * só para o próprio dono.
 */
public class PerfilPublicoResponse {

    private Long id;
    private String nome;
    private String tipo;
    private String fotoPerfil;
    private String cidade;
    private String estado;
    private Double score;
    private Double mediaAvaliacao;
    private String veiculoModelo;
    private String veiculoCor;
    private String nomeFantasia;

    public static PerfilPublicoResponse from(Usuario u) {
        PerfilPublicoResponse r = new PerfilPublicoResponse();
        r.id = u.getId();
        r.nome = u.getNome();
        r.tipo = u.getTipo();
        r.fotoPerfil = u.getFotoPerfil();
        r.cidade = u.getCidade();
        r.estado = u.getEstado();
        r.score = u.getScore();
        r.mediaAvaliacao = u.getMediaAvaliacao();
        // Modelo e cor, sem placa: é o que ajuda a reconhecer o entregador que
        // chegou, sem virar dado de rastreio do veículo.
        r.veiculoModelo = u.getVeiculoModelo();
        r.veiculoCor = u.getVeiculoCor();
        // Nome fantasia é público por natureza — é a fachada da loja.
        r.nomeFantasia = u.getNomeFantasia();
        return r;
    }

    public Long getId() { return id; }
    public String getNome() { return nome; }
    public String getTipo() { return tipo; }
    public String getFotoPerfil() { return fotoPerfil; }
    public String getCidade() { return cidade; }
    public String getEstado() { return estado; }
    public Double getScore() { return score; }
    public Double getMediaAvaliacao() { return mediaAvaliacao; }
    public String getVeiculoModelo() { return veiculoModelo; }
    public String getVeiculoCor() { return veiculoCor; }
    public String getNomeFantasia() { return nomeFantasia; }
}
