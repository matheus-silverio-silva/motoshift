import 'transacao.dart';
import 'usuario.dart';

/// O retrato financeiro do período, como o backend o devolve em `/resumo` —
/// um para cada papel.
///
/// Os dois perfis recebiam os mesmos campos, com o do outro papel zerado: o
/// entregador via "Comprometido R$ 0,00" e o lojista "A receber R$ 0,00". Agora
/// o backend manda só o que é de quem pergunta, e aqui o campo do outro papel
/// é `null` — a tela não mostra, em vez de mostrar um zero com o rótulo
/// errado.
///
/// - Entregador ([souPrestador]): [recebido], [retencoes] (só com retenção na
///   fonte), [sacado], [disponivel] e [aReceber].
/// - Lojista ([souTomador]): [recarregado], [pagoAEntregadores], [devolvido],
///   [disponivel], [bloqueado], [comprometido] e [reservasAbertas].
class ResumoFinanceiro {
  /// `prestador` (entregador) ou `tomador` (lojista).
  final String papel;
  final DateTime dataInicio;
  final DateTime dataFim;
  final double disponivel;

  /// Entregador: pagamentos de turno recebidos no período.
  final double? recebido;

  /// Entregador: ISS e IRRF retidos na fonte. Nulo quando a retenção está
  /// desligada e nada foi retido no período.
  final double? retencoes;

  /// Entregador: o que saiu por saque — descontado o saque que o banco
  /// recusou e voltou por estorno.
  final double? sacado;

  /// Entregador: turnos aceitos que ainda não foram finalizados.
  ///
  /// Não é saldo. O dinheiro está bloqueado na carteira do lojista, não na
  /// dele, e o turno ainda pode ser cancelado — por isso aparece separado.
  final double? aReceber;

  /// Lojista: recargas do período.
  final double? recarregado;

  /// Lojista: pagamentos de turno enviados aos entregadores no período.
  final double? pagoAEntregadores;

  /// Lojista: o que voltou ao disponível — liberação de reserva e estorno.
  final double? devolvido;

  /// Lojista: saldo preso em turnos publicados.
  final double? bloqueado;

  /// Lojista: total das reservas abertas. É o mesmo número de [bloqueado],
  /// mostrado ao lado da lista que o explica.
  final double? comprometido;

  final List<ReservaAberta> reservasAbertas;
  final List<TotalPorTipo> porTipo;

  /// Os dois papéis: as gorjetas do período (V17) — recebidas pelo
  /// entregador, dadas pelo lojista. Já estão dentro de [recebido] /
  /// [pagoAEntregadores]; nulas quando não houve gorjeta.
  final double? gorjetas;

  const ResumoFinanceiro({
    required this.papel,
    required this.dataInicio,
    required this.dataFim,
    required this.disponivel,
    this.recebido,
    this.retencoes,
    this.sacado,
    this.aReceber,
    this.recarregado,
    this.pagoAEntregadores,
    this.devolvido,
    this.bloqueado,
    this.comprometido,
    this.reservasAbertas = const [],
    this.porTipo = const [],
    this.gorjetas,
  });

  bool get souPrestador => papel == 'prestador';
  bool get souTomador => papel == 'tomador';

  factory ResumoFinanceiro.fromJson(Map<String, dynamic> json) {
    return ResumoFinanceiro(
      papel: json['papel'] as String? ?? 'prestador',
      dataInicio: DateTime.parse(json['dataInicio'] as String),
      dataFim: DateTime.parse(json['dataFim'] as String),
      disponivel: _num(json['disponivel']),
      recebido: _talvez(json['recebido']),
      retencoes: _talvez(json['retencoes']),
      sacado: _talvez(json['sacado']),
      aReceber: _talvez(json['aReceber']),
      recarregado: _talvez(json['recarregado']),
      pagoAEntregadores: _talvez(json['pagoAEntregadores']),
      devolvido: _talvez(json['devolvido']),
      bloqueado: _talvez(json['bloqueado']),
      comprometido: _talvez(json['comprometido']),
      gorjetas: _talvez(json['gorjetas']),
      reservasAbertas: (json['reservasAbertas'] as List<dynamic>? ?? [])
          .map((e) => ReservaAberta.fromJson(e as Map<String, dynamic>))
          .toList(),
      porTipo: (json['porTipo'] as List<dynamic>? ?? [])
          .map((e) => TotalPorTipo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Disponível mais bloqueado — só existe para quem tem bloqueado (lojista).
  double? get saldoTotal => bloqueado == null ? null : disponivel + bloqueado!;

  /// Os números que o [papel] vê, na ordem e com os rótulos da tela — a tela
  /// de relatórios os desenha em cartões e o PDF em linhas, da mesma lista.
  /// Com [r] nulo (ainda carregando), os rótulos vêm sem valor.
  static List<NumeroDoResumo> numerosPara(TipoUsuario papel, ResumoFinanceiro? r) {
    if (papel == TipoUsuario.lojista) {
      return [
        NumeroDoResumo('recarregado', 'Recarregado', r?.recarregado),
        NumeroDoResumo('pago', 'Pago a entregadores', r?.pagoAEntregadores),
        // Dentro do "pago"; à parte só quando houve gorjeta no período.
        if (r?.gorjetas != null)
          NumeroDoResumo('gorjetas', 'Gorjetas dadas', r?.gorjetas),
        NumeroDoResumo('devolvido', 'Devolvido', r?.devolvido),
        NumeroDoResumo('disponivel', 'Disponível', r?.disponivel),
        NumeroDoResumo('comprometido', 'Comprometido em turnos', r?.comprometido),
      ];
    }
    return [
      NumeroDoResumo('recebido', 'Recebido por serviços', r?.recebido),
      // Dentro do "recebido"; à parte só quando houve gorjeta no período.
      if (r?.gorjetas != null)
        NumeroDoResumo('gorjetas', 'Gorjetas recebidas', r?.gorjetas),
      // Só existe com retenção na fonte: sem ela o backend não manda o campo,
      // e ninguém inventa um "R$ 0,00 retido".
      if (r?.retencoes != null)
        NumeroDoResumo('retencoes', 'Retido na fonte', r?.retencoes),
      NumeroDoResumo('sacado', 'Sacado', r?.sacado),
      NumeroDoResumo('disponivel', 'Disponível', r?.disponivel),
      NumeroDoResumo('a-receber', 'A receber', r?.aReceber),
    ];
  }
}

/// Um número do resumo como a tela e o PDF o mostram.
class NumeroDoResumo {
  const NumeroDoResumo(this.chave, this.rotulo, this.valor);

  /// Identifica o número na tela (`relatorio-<chave>`).
  final String chave;
  final String rotulo;

  /// Nulo enquanto o resumo não chegou.
  final double? valor;
}

/// Quanto um turno específico ainda segura na carteira do lojista.
class ReservaAberta {
  final int turnoId;
  final String titulo;
  final double valor;

  const ReservaAberta({
    required this.turnoId,
    required this.titulo,
    required this.valor,
  });

  factory ReservaAberta.fromJson(Map<String, dynamic> json) => ReservaAberta(
        turnoId: json['turnoId'] as int,
        titulo: json['titulo'] as String? ?? 'Turno',
        valor: _num(json['valor']),
      );
}

/// Uma linha da quebra por tipo, com a natureza já resolvida pelo backend.
class TotalPorTipo {
  final TipoTransacao tipo;
  final NaturezaTransacao? natureza;
  final double total;
  final int quantidade;

  const TotalPorTipo({
    required this.tipo,
    this.natureza,
    required this.total,
    required this.quantidade,
  });

  factory TotalPorTipo.fromJson(Map<String, dynamic> json) {
    final bruto = Transacao.fromJson({
      'tipo': json['tipo'],
      'natureza': json['natureza'],
      'valor': json['total'],
      'descricao': '',
      'status': 'concluido',
      'criadoEm': DateTime.now().toIso8601String(),
      'usuarioId': 0,
    });
    return TotalPorTipo(
      tipo: bruto.tipo,
      natureza: bruto.natureza,
      total: _num(json['total']),
      quantidade: (json['quantidade'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Um ponto da série de fluxo de caixa.
///
/// Entradas e saídas da carteira — reserva e liberação ficam de fora no
/// backend, porque são o dinheiro do lojista trocando de bolso.
class PontoDeFluxo {
  final DateTime inicio;
  final String rotulo;
  final double entradas;
  final double saidas;
  final double liquido;

  const PontoDeFluxo({
    required this.inicio,
    required this.rotulo,
    required this.entradas,
    required this.saidas,
    required this.liquido,
  });

  factory PontoDeFluxo.fromJson(Map<String, dynamic> json) => PontoDeFluxo(
        inicio: DateTime.parse(json['inicio'] as String),
        rotulo: json['rotulo'] as String? ?? '',
        entradas: _num(json['entradas']),
        saidas: _num(json['saidas']),
        liquido: _num(json['liquido']),
      );
}

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// Campo que pode não vir: é de outro papel, e ausente não é zero.
double? _talvez(dynamic v) => (v as num?)?.toDouble();
