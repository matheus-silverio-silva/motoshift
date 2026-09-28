import 'selo.dart';

/// O que uma conta pode ver do perfil de OUTRA conta.
///
/// Espelha o `PerfilPublicoResponse` do backend, e o que ele **não** traz é
/// tão importante quanto o que traz: telefone, e-mail, CPF/CNPJ, CNH e
/// endereço ficam de fora por decisão de LGPD — a finalidade de ler o perfil
/// alheio é saber quem aceitou o turno, e para isso bastam nome, reputação e o
/// veículo que vai aparecer na porta.
///
/// É por causa disso que o botão "Contatar" do detalhe do turno virou "Ver
/// perfil": expor o telefone só para aquele botão contrariaria a mesma decisão
/// que tirou o campo da API.
class PerfilPublico {
  const PerfilPublico({
    required this.id,
    required this.nome,
    required this.tipo,
    this.fotoPerfil,
    this.cidade,
    this.estado,
    this.score,
    this.mediaAvaliacao,
    this.veiculoModelo,
    this.veiculoCor,
    this.nomeFantasia,
    this.pontualidade,
    this.checkinsPontualidade = 0,
    this.selos = const [],
  });

  final int id;
  final String nome;
  final String tipo;
  final String? fotoPerfil;
  final String? cidade;
  final String? estado;
  final double? score;
  final double? mediaAvaliacao;

  /// Modelo e cor, sem placa: ajuda a reconhecer quem chegou, sem virar dado
  /// de rastreio do veículo.
  final String? veiculoModelo;
  final String? veiculoCor;

  /// Fachada da loja — público por natureza.
  final String? nomeFantasia;

  /// % de chegadas até 10 min após o início, nos últimos 90 dias (V16). Só do
  /// entregador; nula sem check-in — "Sem histórico", nunca 100%.
  final int? pontualidade;
  final int checkinsPontualidade;

  /// Selos de reputação, com o critério de cada um (calculados no backend).
  final List<Selo> selos;

  factory PerfilPublico.fromJson(Map<String, dynamic> json) => PerfilPublico(
        id: json['id'] as int,
        nome: json['nome'] as String? ?? 'Usuário',
        tipo: json['tipo'] as String? ?? 'motoboy',
        fotoPerfil: json['fotoPerfil'] as String?,
        cidade: json['cidade'] as String?,
        estado: json['estado'] as String?,
        score: (json['score'] as num?)?.toDouble(),
        mediaAvaliacao: (json['mediaAvaliacao'] as num?)?.toDouble(),
        veiculoModelo: json['veiculoModelo'] as String?,
        veiculoCor: json['veiculoCor'] as String?,
        nomeFantasia: json['nomeFantasia'] as String?,
        pontualidade: (json['pontualidade'] as num?)?.toInt(),
        checkinsPontualidade:
            (json['checkinsPontualidade'] as num?)?.toInt() ?? 0,
        selos: Selo.listaDe(json['selos']),
      );

  /// O backend grava `tipo` em minúsculas; o `toLowerCase` é só para o JSON
  /// não decidir isto por nós se a gravação mudar.
  bool get ehLojista => tipo.toLowerCase() == 'lojista';

  /// Como chamar esta pessoa na tela: a loja pelo nome fantasia, quando houver.
  String get nomeDeExibicao =>
      ehLojista ? (nomeFantasia ?? nome) : nome;

  String? get localidade {
    if (cidade == null) return estado;
    return estado == null ? cidade : '$cidade/$estado';
  }

  /// "92% · 13 check-ins", ou "Sem histórico".
  String get pontualidadeRotulo {
    if (pontualidade == null) return 'Sem histórico';
    final n = checkinsPontualidade;
    return '$pontualidade% · $n ${n == 1 ? 'check-in' : 'check-ins'}';
  }

  String? get veiculo {
    if (veiculoModelo == null) return null;
    return veiculoCor == null ? veiculoModelo : '$veiculoModelo · $veiculoCor';
  }
}
