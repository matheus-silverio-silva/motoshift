import 'package:flutter/foundation.dart';

/// Turno selecionado no master-detail do desktop.
///
/// Só existe para telas largas: no mobile o detalhe continua sendo uma rota
/// empilhada e este provider fica inerte. Guarda apenas o id — o objeto vem
/// sempre da lista que a tela já carregou, para não haver duas cópias do
/// mesmo turno divergindo depois de aceitar ou cancelar.
class TurnoSelecionadoProvider extends ChangeNotifier {
  int? _id;

  int? get id => _id;
  bool get temSelecao => _id != null;

  void selecionar(int? id) {
    if (_id == id) return;
    _id = id;
    notifyListeners();
  }

  void limpar() => selecionar(null);
}
