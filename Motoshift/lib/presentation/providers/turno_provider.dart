import 'package:flutter/foundation.dart';
import '../../models/turno.dart';
import '../../services/api_service.dart';

class TurnoProvider extends ChangeNotifier {
  final ApiService _api;

  List<Turno> _turnosDisponiveis = [];
  List<Turno> _meusTurnos = [];
  List<Turno> _turnosLojista = [];
  bool _carregando = false;
  String? _erro;

  TurnoProvider(this._api);

  List<Turno> get turnosDisponiveis => _turnosDisponiveis;
  List<Turno> get meusTurnos => _meusTurnos;
  List<Turno> get turnosLojista => _turnosLojista;
  bool get carregando => _carregando;
  String? get erro => _erro;

  void limparErro() {
    _erro = null;
    notifyListeners();
  }

  Future<void> carregarDisponiveis() async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _turnosDisponiveis = await _api.listarTurnosDisponiveis();
    } on ApiException catch (e) {
      _erro = e.message;
    } catch (e) {
      _erro = 'Erro ao carregar turnos disponíveis.';
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> carregarMeusTurnos(int motoboyId) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _meusTurnos = await _api.listarMeusTurnos(motoboyId);
    } on ApiException catch (e) {
      _erro = e.message;
    } catch (e) {
      _erro = 'Erro ao carregar seus turnos.';
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> carregarTurnosLojista(int lojistId) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      _turnosLojista = await _api.listarTurnosLojista(lojistId);
    } on ApiException catch (e) {
      _erro = e.message;
    } catch (e) {
      _erro = 'Erro ao carregar turnos.';
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> aceitarTurno(int turnoId, int motoboyId) async {
    // RF05: verificacao local de conflito antes de chamar a API
    final candidato = _turnosDisponiveis.where((t) => t.id == turnoId).firstOrNull;
    if (candidato != null) {
      final conflito = _meusTurnos.any((t) =>
          (t.status == StatusTurno.aceito || t.status == StatusTurno.emAndamento) &&
          t.dataInicio.isBefore(candidato.dataFim) &&
          t.dataFim.isAfter(candidato.dataInicio));
      if (conflito) {
        _erro = 'Voce ja possui um turno agendado neste horario.';
        notifyListeners();
        return false;
      }
    }

    try {
      final turnoAtualizado = await _api.aceitarTurno(turnoId, motoboyId);
      _turnosDisponiveis.removeWhere((t) => t.id == turnoId);
      _meusTurnos.add(turnoAtualizado);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _erro = 'Sem conexao com o servidor';
      notifyListeners();
      return false;
    }
  }

  Future<bool> finalizarTurno(int turnoId) async {
    try {
      final atualizado = await _api.finalizarTurno(turnoId);
      final idx = _meusTurnos.indexWhere((t) => t.id == turnoId);
      if (idx != -1) _meusTurnos[idx] = atualizado;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _erro = 'Erro ao finalizar turno.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelarTurno(int turnoId) async {
    try {
      final atualizado = await _api.cancelarTurno(turnoId);
      final idx = _meusTurnos.indexWhere((t) => t.id == turnoId);
      if (idx != -1) _meusTurnos[idx] = atualizado;
      final idxL = _turnosLojista.indexWhere((t) => t.id == turnoId);
      if (idxL != -1) _turnosLojista[idxL] = atualizado;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _erro = 'Erro ao cancelar turno.';
      notifyListeners();
      return false;
    }
  }
}
