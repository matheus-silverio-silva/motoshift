import 'package:clock/clock.dart';

import 'turno.dart';

/// "Publicar de novo": um turno que já acabou vira o rascunho do próximo.
///
/// Leva tudo o que descreve o turno — título, descrição, região, ponto, raio,
/// valor, vagas e duração — e muda só a data: o mesmo dia da semana, na
/// semana seguinte à do turno de origem, no mesmo horário. Se essa data já
/// passou (o turno de origem é antigo) ou cai dentro das 2 h de antecedência,
/// avança de semana em semana até a primeira que ainda dá para publicar.
///
/// Não publica nada. O resultado só preenche o formulário, e a publicação
/// passa pelas mesmas regras de sempre: antecedência mínima, confirmação do
/// custo e saldo — conferidos de novo pelo backend.
class RepeticaoDeTurno {
  const RepeticaoDeTurno._({
    required this.origem,
    required this.inicio,
    required this.fim,
    required this.titulo,
  });

  /// A mesma do backend e do formulário.
  static const antecedenciaMinima = Duration(hours: 2);

  /// O título que o formulário gera sozinho ("Turno 12/09"). Repetido tal
  /// qual, o turno novo nasceria com a data do antigo no nome.
  static final _tituloAutomatico = RegExp(r'^Turno \d{2}/\d{2}$');

  final Turno origem;
  final DateTime inicio;
  final DateTime fim;

  /// `null` quando o título era o automático — o formulário gera um novo a
  /// partir da data escolhida.
  final String? titulo;

  String? get descricao => origem.descricao;

  /// Só o que já terminou se repete: o turno aberto ainda está valendo.
  static bool podeRepetir(Turno t) =>
      t.status == StatusTurno.finalizado ||
      t.status == StatusTurno.cancelado ||
      t.status == StatusTurno.expirado;

  factory RepeticaoDeTurno.de(Turno origem, {DateTime? agora}) {
    final limite = (agora ?? clock.now()).add(antecedenciaMinima);
    final duracao = origem.dataFim.difference(origem.dataInicio);

    var semanas = 1;
    var inicio = _maisSemanas(origem.dataInicio, semanas);
    while (inicio.isBefore(limite)) {
      inicio = _maisSemanas(origem.dataInicio, ++semanas);
    }

    final titulo = origem.titulo.trim();
    return RepeticaoDeTurno._(
      origem: origem,
      inicio: inicio,
      fim: inicio.add(duracao),
      titulo: _tituloAutomatico.hasMatch(titulo) || titulo.isEmpty
          ? null
          : titulo,
    );
  }

  /// Pelo calendário, não por 7 × 24 h: o horário de parede é o que o
  /// lojista combinou, e ele não muda de uma semana para a outra.
  static DateTime _maisSemanas(DateTime d, int semanas) => DateTime(
      d.year, d.month, d.day + 7 * semanas, d.hour, d.minute);

  static const _dias = [
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];

  /// "sexta-feira, 09/10" — para o aviso no topo do formulário.
  String get dataPorExtenso {
    final dd = inicio.day.toString().padLeft(2, '0');
    final mm = inicio.month.toString().padLeft(2, '0');
    return '${_dias[inicio.weekday - 1]}, $dd/$mm';
  }
}
