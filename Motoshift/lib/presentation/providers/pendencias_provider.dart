import 'package:flutter/foundation.dart';

import '../../models/nota_fiscal.dart';
import '../../models/turno.dart';
import '../../models/usuario.dart';
import '../../services/api_service.dart';

/// Alguém que este usuário ainda precisa avaliar num turno.
class PendenteAvaliacao {
  const PendenteAvaliacao({required this.usuarioId, required this.nome});

  final int usuarioId;
  final String nome;
}

/// Um turno finalizado com avaliação em aberto.
class TurnoAAvaliar {
  const TurnoAAvaliar({required this.turno, required this.pendentes});

  final Turno turno;

  /// Uma entrada por pessoa. Num turno de três vagas o lojista tem três, e
  /// avaliar uma não encerra as outras duas.
  final List<PendenteAvaliacao> pendentes;
}

/// O que ainda falta fazer depois que o turno acabou — avaliar e emitir nota.
///
/// <h3>Por que é um provider, e não uma consulta por tela</h3>
/// A mesma pendência aparecia em quatro lugares (painel do início, central de
/// Avaliações, selo do menu e o bloco "O que falta" do detalhe do turno), e
/// cada um a calculava do seu jeito. Com uma fonte só, os quatro concordam e
/// o número cai para zero em todos assim que a avaliação é registrada.
///
/// <h3>Por que não usa `/avaliacoes/feitas`</h3>
/// Aquela rota devolve ids **distintos** de turno: basta uma avaliação para o
/// turno inteiro entrar na lista de "já avaliados". Num turno multi-vaga, o
/// lojista que avaliou o primeiro de três entregadores perdia o acesso aos
/// outros dois — a pendência sumia da interface sem ter sido resolvida. Só
/// `/avaliacoes/turno/{id}/pendentes/{usuarioId}` sabe quantas faltam, e é
/// por isso que o carregamento faz uma consulta por turno finalizado em vez
/// de uma consulta só.
class PendenciasProvider extends ChangeNotifier {
  PendenciasProvider(this._api);

  final ApiService _api;

  List<TurnoAAvaliar> _avaliacoes = const [];
  List<NotaFiscalPendente> _notas = const [];
  bool _carregando = false;
  bool _carregado = false;
  int? _usuarioCarregado;

  List<TurnoAAvaliar> get turnosAAvaliar => _avaliacoes;
  List<NotaFiscalPendente> get notasAEmitir => _notas;
  bool get carregando => _carregando;
  bool get carregado => _carregado;

  /// Quantas **avaliações** faltam, e não quantos turnos: é o número que o
  /// selo do menu mostra, e ele precisa contar as três vagas de um turno
  /// multi-vaga como três.
  int get quantidadeAvaliacoes =>
      _avaliacoes.fold(0, (soma, t) => soma + t.pendentes.length);

  int get quantidadeNotas => _notas.length;

  /// Quem este usuário ainda precisa avaliar num turno específico.
  List<PendenteAvaliacao> avaliacoesDoTurno(int? turnoId) {
    if (turnoId == null) return const [];
    for (final t in _avaliacoes) {
      if (t.turno.id == turnoId) return t.pendentes;
    }
    return const [];
  }

  /// Notas que ainda podem ser emitidas por este usuário naquele turno — uma
  /// por entregador, quando o turno tem mais de um.
  List<NotaFiscalPendente> notasDoTurno(int? turnoId) {
    if (turnoId == null) return const [];
    return _notas.where((n) => n.turnoId == turnoId).toList();
  }

  /// Carrega uma vez por usuário. Chamado pelo menu, que aparece em toda
  /// tela, e de novo por quem resolve uma pendência.
  Future<void> garantirCarregado(Usuario? usuario) {
    if (_carregando) return Future.value();
    if (_carregado && _usuarioCarregado == usuario?.id) return Future.value();
    return carregar(usuario);
  }

  Future<void> carregar(Usuario? usuario) async {
    final id = usuario?.id;
    if (id == null) return;

    _carregando = true;
    notifyListeners();

    final avaliacoes = await _carregarAvaliacoes(usuario!, id);
    final notas = await _carregarNotas();

    _avaliacoes = avaliacoes;
    _notas = notas;
    _carregando = false;
    _carregado = true;
    _usuarioCarregado = id;
    notifyListeners();
  }

  /// Zera o estado no logout, para a conta seguinte não herdar a pendência da
  /// anterior.
  void limpar() {
    _avaliacoes = const [];
    _notas = const [];
    _carregado = false;
    _usuarioCarregado = null;
    notifyListeners();
  }

  /// Falha de rede devolve lista vazia de propósito: a pendência é um resumo
  /// auxiliar, e derrubar a tela por causa dela seria desproporcional. O que
  /// não pode acontecer é mostrar um número errado — e vazio não é errado, é
  /// "ainda não sei".
  Future<List<TurnoAAvaliar>> _carregarAvaliacoes(
      Usuario usuario, int id) async {
    try {
      final turnos = usuario.tipo == TipoUsuario.lojista
          ? await _api.turnos.listarTurnosLojista(id)
          : await _api.turnos.listarMeusTurnos(id);

      final finalizados = turnos
          .where((t) => t.status == StatusTurno.finalizado && t.id != null)
          .toList()
        ..sort((a, b) => b.dataInicio.compareTo(a.dataInicio));

      final resultados = await Future.wait(
        finalizados.map((t) => _pendentesDo(t, id)),
      );

      return resultados
          .whereType<TurnoAAvaliar>()
          .where((t) => t.pendentes.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<TurnoAAvaliar?> _pendentesDo(Turno turno, int usuarioId) async {
    try {
      final r =
          await _api.avaliacoes.buscarAvaliacoesPendentes(turno.id!, usuarioId);
      return TurnoAAvaliar(
        turno: turno,
        pendentes: [
          for (final p in r.pendentes)
            if (p['usuarioId'] != null)
              PendenteAvaliacao(
                usuarioId: (p['usuarioId'] as num).toInt(),
                nome: p['nome'] as String? ?? 'Usuário',
              ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<NotaFiscalPendente>> _carregarNotas() async {
    try {
      return await _api.notasFiscais.pendentes();
    } catch (_) {
      return const [];
    }
  }
}
