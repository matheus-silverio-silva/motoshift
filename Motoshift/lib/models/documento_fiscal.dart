import 'nota_fiscal.dart';

/// Que documento um lançamento do extrato gera.
///
/// A tabela é do backend (`service.fiscal.TipoDocumento`): pagamento de turno
/// gera NFS-e — a mesma nos dois lados —, recarga gera recibo, saque com Pix
/// concluído gera comprovante Pix, e o resto gera comprovante de movimentação.
/// Reserva e liberação NÃO são serviço prestado e nunca geram nota.
///
/// Tudo SIMULADO — ver docs/financeiro/FISCAL.md.
enum TipoDocumento {
  nfse,
  reciboRecarga,
  comprovantePix,
  comprovanteMovimentacao;

  /// Tipo desconhecido vira nulo: a linha do extrato só não mostra o botão,
  /// em vez de derrubar a tela.
  static TipoDocumento? parse(String? raw) {
    return switch (raw?.toUpperCase()) {
      'NFSE' => TipoDocumento.nfse,
      'RECIBO_RECARGA' => TipoDocumento.reciboRecarga,
      'COMPROVANTE_PIX' => TipoDocumento.comprovantePix,
      'COMPROVANTE_MOVIMENTACAO' => TipoDocumento.comprovanteMovimentacao,
      _ => null,
    };
  }

  bool get ehNota => this == TipoDocumento.nfse;

  /// O texto do botão que gera o documento.
  String get acao => ehNota ? 'Gerar nota fiscal' : 'Gerar comprovante';

  String get titulo {
    return switch (this) {
      TipoDocumento.nfse => 'Nota fiscal de serviço',
      TipoDocumento.reciboRecarga => 'Recibo de recarga',
      TipoDocumento.comprovantePix => 'Comprovante de transferência Pix',
      TipoDocumento.comprovanteMovimentacao => 'Comprovante de movimentação',
    };
  }
}

/// Uma linha "rótulo: valor" do corpo de um comprovante.
class LinhaComprovante {
  const LinhaComprovante(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  factory LinhaComprovante.fromJson(Map<String, dynamic> json) => LinhaComprovante(
        json['rotulo'] as String? ?? '',
        json['valor'] as String? ?? '',
      );
}

/// Recibo ou comprovante de um lançamento que não é serviço prestado.
///
/// Derivado do lançamento pelo backend: número a partir do id e código de
/// autenticação por HMAC — o mesmo lançamento gera sempre o mesmo comprovante.
class Comprovante {
  const Comprovante({
    required this.tipo,
    required this.titulo,
    required this.numero,
    required this.codigoAutenticacao,
    required this.transacaoId,
    required this.valor,
    required this.descricao,
    required this.dataHora,
    required this.titularNome,
    required this.titularDocumentoTipo,
    required this.detalhes,
    this.credito,
    this.operacaoId,
    this.titularDocumento,
    this.titularCidade,
    this.saldoDisponivelApos,
    this.saldoBloqueadoApos,
  });

  final TipoDocumento tipo;
  final String titulo;
  final String numero;
  final String codigoAutenticacao;
  final int transacaoId;
  final String? operacaoId;
  final double valor;

  /// `true` entrou, `false` saiu — da natureza do lançamento.
  final bool? credito;
  final String descricao;
  final DateTime dataHora;
  final String titularNome;
  final String titularDocumentoTipo;
  final String? titularDocumento;
  final String? titularCidade;
  final double? saldoDisponivelApos;
  final double? saldoBloqueadoApos;
  final List<LinhaComprovante> detalhes;

  factory Comprovante.fromJson(Map<String, dynamic> json) {
    final natureza = (json['natureza'] as String?)?.toLowerCase();
    return Comprovante(
      tipo: TipoDocumento.parse(json['tipoDocumento'] as String?) ??
          TipoDocumento.comprovanteMovimentacao,
      titulo: json['titulo'] as String? ?? 'Comprovante',
      numero: json['numero'] as String? ?? '',
      codigoAutenticacao: json['codigoAutenticacao'] as String? ?? '',
      transacaoId: (json['transacaoId'] as num).toInt(),
      operacaoId: json['operacaoId'] as String?,
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      credito: natureza == null ? null : natureza == 'credito',
      descricao: json['descricao'] as String? ?? '',
      dataHora: DateTime.parse(json['dataHora'] as String),
      titularNome: json['titularNome'] as String? ?? '—',
      titularDocumentoTipo: json['titularDocumentoTipo'] as String? ?? 'CPF',
      titularDocumento: json['titularDocumento'] as String?,
      titularCidade: json['titularCidade'] as String?,
      saldoDisponivelApos: (json['saldoDisponivelApos'] as num?)?.toDouble(),
      saldoBloqueadoApos: (json['saldoBloqueadoApos'] as num?)?.toDouble(),
      detalhes: [
        for (final l in (json['detalhes'] as List<dynamic>? ?? const []))
          LinhaComprovante.fromJson((l as Map).cast<String, dynamic>()),
      ],
    );
  }
}

/// O documento de um lançamento: uma NFS-e ou um comprovante — nunca os dois.
class DocumentoFiscal {
  const DocumentoFiscal({
    required this.tipo,
    required this.transacaoId,
    required this.marca,
    this.simulado = true,
    this.nota,
    this.comprovante,
  });

  /// A frase que TODO documento mostra. Vem do backend junto com o documento;
  /// este valor é só o que a tela usa se o campo não vier.
  static const marcaPadrao = 'DOCUMENTO SIMULADO — SEM VALOR FISCAL';

  final TipoDocumento tipo;
  final int? transacaoId;
  final bool simulado;
  final String marca;
  final NotaFiscal? nota;
  final Comprovante? comprovante;

  factory DocumentoFiscal.fromJson(Map<String, dynamic> json) {
    final nota = json['nota'];
    final comprovante = json['comprovante'];
    return DocumentoFiscal(
      tipo: TipoDocumento.parse(json['tipoDocumento'] as String?) ??
          TipoDocumento.comprovanteMovimentacao,
      transacaoId: (json['transacaoId'] as num?)?.toInt(),
      simulado: json['simulado'] != false,
      marca: json['marca'] as String? ?? marcaPadrao,
      nota: nota is Map ? NotaFiscal.fromJson(nota.cast<String, dynamic>()) : null,
      comprovante: comprovante is Map
          ? Comprovante.fromJson(comprovante.cast<String, dynamic>())
          : null,
    );
  }

  /// Uma NFS-e já carregada (tela de notas), vestida de documento.
  factory DocumentoFiscal.daNota(NotaFiscal nota) => DocumentoFiscal(
        tipo: TipoDocumento.nfse,
        transacaoId: nota.transacaoId,
        marca: marcaPadrao,
        nota: nota,
      );
}
