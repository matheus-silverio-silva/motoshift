/// A NFS-e no leiaute do DANFSe v2.0 — o Documento Auxiliar da NFS-e do
/// padrão nacional (Nota Técnica SE/CGNFS-e nº 008/2026). SIMULADO.
///
/// Espelha `DanfseResponse` do backend. Os quadros vêm prontos, com os
/// rótulos do modelo oficial e os valores já formatados: as regras fiscais
/// que decidem cada valor ("ISSQN retido?", "IBS/CBS se aplica?") moram no
/// backend (`LeiauteDanfse`), e a tela e o PDF só desenham — não há como os
/// dois mostrarem rótulos diferentes.
class Danfse {
  const Danfse({
    required this.versao,
    required this.norma,
    required this.chaveAcesso,
    required this.municipioEmissor,
    required this.codigoMunicipio,
    required this.conteudoQrCode,
    required this.avisoQrCode,
    required this.quadros,
    this.numeroDps,
    this.serieDps,
  });

  /// "DANFSe v2.0".
  final String versao;

  /// A nota técnica que define o leiaute.
  final String norma;

  /// Os 50 dígitos, sem separadores — ver [chaveFormatada].
  final String chaveAcesso;

  /// "Curitiba - PR".
  final String municipioEmissor;

  /// Código IBGE de 7 dígitos.
  final String codigoMunicipio;

  final int? numeroDps;
  final String? serieDps;

  /// O que o QR Code carrega. Não é o link do portal oficial: a nota é
  /// simulada, e o QR Code só repete a chave dizendo isso.
  final String conteudoQrCode;

  /// O texto que acompanha o QR Code.
  final String avisoQrCode;

  final List<QuadroDanfse> quadros;

  /// A chave em grupos de 5 dígitos — 10 grupos, legível e fácil de conferir.
  String get chaveFormatada {
    final grupos = <String>[];
    for (var i = 0; i < chaveAcesso.length; i += 5) {
      final fim = i + 5 > chaveAcesso.length ? chaveAcesso.length : i + 5;
      grupos.add(chaveAcesso.substring(i, fim));
    }
    return grupos.join(' ');
  }

  QuadroDanfse? quadro(String id) {
    for (final q in quadros) {
      if (q.id == id) return q;
    }
    return null;
  }

  factory Danfse.fromJson(Map<String, dynamic> json) => Danfse(
        versao: json['versao'] as String? ?? 'DANFSe',
        norma: json['norma'] as String? ?? '',
        chaveAcesso: json['chaveAcesso'] as String? ?? '',
        municipioEmissor: json['municipioEmissor'] as String? ?? '-',
        codigoMunicipio: json['codigoMunicipio'] as String? ?? '',
        numeroDps: (json['numeroDps'] as num?)?.toInt(),
        serieDps: json['serieDps'] as String?,
        conteudoQrCode: json['conteudoQrCode'] as String? ?? '',
        avisoQrCode: json['avisoQrCode'] as String? ?? '',
        quadros: [
          for (final q in (json['quadros'] as List<dynamic>? ?? const []))
            QuadroDanfse.fromJson((q as Map).cast<String, dynamic>()),
        ],
      );
}

/// Um bloco do DANFSe: prestador, tomador, serviço, tributos, totais…
class QuadroDanfse {
  const QuadroDanfse({
    required this.id,
    required this.titulo,
    this.campos = const [],
    this.observacao,
  });

  /// Estável ("prestador", "tomador", "totais"…), para a tela reconhecer o
  /// bloco sem depender do título.
  final String id;
  final String titulo;
  final List<CampoDanfse> campos;

  /// Texto corrido abaixo dos campos — ou o bloco inteiro, quando não há
  /// campos ("intermediário não identificado").
  final String? observacao;

  /// A observação já diz o título — "INTERMEDIÁRIO DO SERVIÇO NÃO IDENTIFICADO
  /// NA NFS-e", a frase do modelo oficial. Aí ela vai sozinha, sem repetir.
  bool get observacaoRepeteTitulo =>
      campos.isEmpty &&
      observacao != null &&
      observacao!.toUpperCase().startsWith(titulo.toUpperCase());

  factory QuadroDanfse.fromJson(Map<String, dynamic> json) => QuadroDanfse(
        id: json['id'] as String? ?? '',
        titulo: json['titulo'] as String? ?? '',
        observacao: json['observacao'] as String?,
        campos: [
          for (final c in (json['campos'] as List<dynamic>? ?? const []))
            CampoDanfse.fromJson((c as Map).cast<String, dynamic>()),
        ],
      );
}

/// Um campo do DANFSe: rótulo em cima, valor embaixo.
class CampoDanfse {
  const CampoDanfse(this.rotulo, this.valor,
      {this.largo = false, this.destaque = false});

  final String rotulo;
  final String valor;

  /// Ocupa a linha inteira — nome, endereço, descrição do serviço.
  final bool largo;

  /// Sombreado, como a NT 008 manda fazer com o valor líquido.
  final bool destaque;

  factory CampoDanfse.fromJson(Map<String, dynamic> json) => CampoDanfse(
        json['rotulo'] as String? ?? '',
        json['valor'] as String? ?? '-',
        largo: json['largo'] == true,
        destaque: json['destaque'] == true,
      );
}
