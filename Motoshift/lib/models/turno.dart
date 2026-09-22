import 'package:clock/clock.dart';
StatusTurno _parseStatus(String raw) {
  return switch (raw.toLowerCase()) {
    'em_andamento' || 'emandamento' => StatusTurno.emAndamento,
    'aceito' => StatusTurno.aceito,
    'finalizado' => StatusTurno.finalizado,
    'cancelado' => StatusTurno.cancelado,
    // O backend expira turnos que ninguém aceitou até o horário de início
    // (SCRUM-19). Sem este caso o turno caía no `_` e voltava como "Aberto".
    'expirado' => StatusTurno.expirado,
    _ => StatusTurno.aberto,
  };
}

// Mapeado para a entidade `Turno` no Spring Boot / MySQL
// Tabela: turnos
class Turno {
  final int? id;
  final int lojistId;         // FK → usuarios.id (tipo = LOJISTA)
  final int? motoboyId;       // FK → usuarios.id (tipo = MOTOBOY), null = aberto
  final String titulo;
  final String? descricao;
  final String regiao;
  final DateTime dataInicio;
  final DateTime dataFim;
  final double valorEstimado;
  final double raioEntregaKm;

  /// Ponto de partida do turno. O backend devolve estes campos desde o
  /// SCRUM-18 e o app simplesmente os descartava — por isso nenhuma tela
  /// conseguia desenhar o turno onde ele realmente é. Nulos nos turnos
  /// publicados antes da coordenada existir.
  final double? latitude;
  final double? longitude;

  /// Endereço textual do ponto de partida, quando o lojista informou.
  final String? endereco;

  final int vagas;             // total de vagas de entregador no turno
  final int vagasPreenchidas;  // quantas já foram aceitas
  final StatusTurno status;
  final PagamentoStatus pagamentoStatus;
  // lojistaConfirmouEm e motoboyConfirmouEm sairam do modelo.
  //
  // Guardavam a dupla confirmacao — cada parte declarando que o dinheiro tinha
  // mudado de maos fora do app. A liquidacao passou a ser automatica: o lojista
  // compromete o valor ao publicar e a finalizacao transfere o que ja estava
  // reservado. O backend deixou de enviar as duas chaves (V13).
  final double? distanciaPercorridaKm;
  final int? totalEntregas;

  /// Distância entre o usuário e o turno. Só vem preenchida quando a busca
  /// manda lat+lng+raioKm (`GET /api/turnos/disponiveis`); nas outras
  /// listagens é nula.
  final double? distanciaKm;

  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  const Turno({
    this.id,
    required this.lojistId,
    this.motoboyId,
    required this.titulo,
    this.descricao,
    required this.regiao,
    required this.dataInicio,
    required this.dataFim,
    required this.valorEstimado,
    required this.raioEntregaKm,
    this.latitude,
    this.longitude,
    this.endereco,
    this.vagas = 1,
    this.vagasPreenchidas = 0,
    this.status = StatusTurno.aberto,
    this.pagamentoStatus = PagamentoStatus.naoAplicavel,
    this.distanciaPercorridaKm,
    this.totalEntregas,
    this.distanciaKm,
    this.criadoEm,
    this.atualizadoEm,
  });

  factory Turno.fromJson(Map<String, dynamic> json) {
    return Turno(
      id: json['id'] as int?,
      lojistId: json['lojistId'] as int,
      motoboyId: json['motoboyId'] as int?,
      titulo: json['titulo'] as String,
      descricao: json['descricao'] as String?,
      regiao: json['regiao'] as String,
      dataInicio: DateTime.parse(json['dataInicio'] as String),
      dataFim: DateTime.parse(json['dataFim'] as String),
      valorEstimado: (json['valorEstimado'] as num).toDouble(),
      raioEntregaKm: (json['raioEntregaKm'] as num).toDouble(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      endereco: json['endereco'] as String?,
      vagas: (json['vagas'] as num?)?.toInt() ?? 1,
      vagasPreenchidas: (json['vagasPreenchidas'] as num?)?.toInt() ?? 0,
      status: _parseStatus(json['status'] as String),
      pagamentoStatus: _parsePagamento(json['pagamentoStatus'] as String?),
      distanciaPercorridaKm: json['distanciaPercorridaKm'] != null
          ? (json['distanciaPercorridaKm'] as num).toDouble()
          : null,
      totalEntregas: json['totalEntregas'] as int?,
      distanciaKm: (json['distanciaKm'] as num?)?.toDouble(),
      criadoEm: json['criadoEm'] != null
          ? DateTime.parse(json['criadoEm'] as String)
          : null,
      atualizadoEm: json['atualizadoEm'] != null
          ? DateTime.parse(json['atualizadoEm'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'lojistId': lojistId,
      if (motoboyId != null) 'motoboyId': motoboyId,
      'titulo': titulo,
      if (descricao != null) 'descricao': descricao,
      'regiao': regiao,
      'dataInicio': dataInicio.toIso8601String(),
      'dataFim': dataFim.toIso8601String(),
      'valorEstimado': valorEstimado,
      'raioEntregaKm': raioEntregaKm,
      // Sem estas três chaves o turno nascia sem coordenada e ficava invisível
      // para o filtro "perto de mim" — publicar pelo app dava um turno que o
      // entregador nunca encontrava.
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (endereco != null) 'endereco': endereco,
      'vagas': vagas,
      'status': status.name.toUpperCase(),
    };
  }

  String get horarioFormatado {
    final hi = '${dataInicio.hour.toString().padLeft(2, '0')}:${dataInicio.minute.toString().padLeft(2, '0')}';
    final hf = '${dataFim.hour.toString().padLeft(2, '0')}:${dataFim.minute.toString().padLeft(2, '0')}';
    return '$hi - $hf';
  }

  Duration get duracao => dataFim.difference(dataInicio);

  /// Vagas ainda disponíveis (nunca negativo).
  int get vagasRestantes =>
      (vagas - vagasPreenchidas) < 0 ? 0 : (vagas - vagasPreenchidas);

  /// Turno que comporta mais de um entregador.
  bool get multiVaga => vagas > 1;

  /// Dá para plotar este turno no mapa? A tela precisa saber disso para
  /// mostrar o aviso certo em vez de um mapa centrado em (0, 0) — que fica no
  /// Atlântico, na costa da África.
  bool get temCoordenada => latitude != null && longitude != null;
}

enum StatusTurno {
  aberto,
  aceito,
  emAndamento,
  finalizado,
  cancelado,
  expirado;

  String get label {
    return switch (this) {
      StatusTurno.aberto => 'Aberto',
      StatusTurno.aceito => 'Aceito',
      StatusTurno.emAndamento => 'Em Andamento',
      StatusTurno.finalizado => 'Finalizado',
      StatusTurno.cancelado => 'Cancelado',
      StatusTurno.expirado => 'Expirado',
    };
  }

  /// Turno que ainda está em jogo — não foi encerrado por nenhuma das partes.
  bool get ativo =>
      this == StatusTurno.aberto ||
      this == StatusTurno.aceito ||
      this == StatusTurno.emAndamento;
}

extension TurnosFiltros on Iterable<Turno> {
  /// Turnos que ainda vão acontecer (ou estão acontecendo), do mais próximo
  /// para o mais distante.
  ///
  /// O corte usa `dataFim` e não `dataInicio` de propósito: um turno que
  /// começou há uma hora e termina daqui a três ainda interessa a quem está
  /// olhando o painel — o que não pode aparecer é turno já encerrado.
  /// Cancelados e finalizados saem pelo filtro de status.
  ///
  /// [hoje] existe pelo mesmo motivo do parâmetro homônimo em
  /// `serieUltimos7Dias`: sem ele, o golden de qualquer tela que use esta
  /// lista fica preso ao relógio da máquina. Só os testes passam a data; em
  /// produção o parâmetro é omitido e o comportamento é o de sempre.
  List<Turno> proximos({DateTime? hoje}) {
    final agora = hoje ?? clock.now();
    final lista = where((t) => t.status.ativo && t.dataFim.isAfter(agora))
        .toList();
    lista.sort((a, b) => a.dataInicio.compareTo(b.dataInicio));
    return lista;
  }
}

PagamentoStatus _parsePagamento(String? raw) {
  return switch (raw?.toLowerCase()) {
    'pendente' => PagamentoStatus.pendente,
    'pago' => PagamentoStatus.pago,
    _ => PagamentoStatus.naoAplicavel,
  };
}

enum PagamentoStatus {
  naoAplicavel,
  pendente,
  pago;

  String get label {
    return switch (this) {
      PagamentoStatus.pendente => 'A receber',
      PagamentoStatus.pago => 'Pago',
      _ => '',
    };
  }
}
