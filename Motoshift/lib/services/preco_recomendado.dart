import 'package:flutter/material.dart';

/// Calcula um **preço recomendado** para o turno com base em fatores objetivos.
///
/// Heurística transparente (sem "caixa-preta"): parte de um valor-base por hora
/// e aplica multiplicadores por raio de entrega, faixa de horário (pico/noturno)
/// e dia da semana. O lojista continua livre para digitar outro valor — a
/// sugestão é só um ponto de partida justo para atrair entregadores.
class PrecoRecomendado {
  PrecoRecomendado._();

  /// Valor-base por hora de turno (R$). Ancora o cálculo.
  static const double baseHora = 22.0;

  /// Piso: nenhum turno é sugerido abaixo disso.
  static const double piso = 25.0;

  /// Resultado detalhado, para poder explicar a sugestão ao lojista.
  static PrecoResultado calcular({
    required DateTime inicio,
    required DateTime fim,
    required double raioKm,
  }) {
    final horas = fim.difference(inicio).inMinutes / 60.0;
    if (horas <= 0) {
      return const PrecoResultado(valor: piso, fatores: []);
    }

    final fatores = <PrecoFator>[];
    double valor = baseHora * horas;

    // ── Raio de entrega ──────────────────────────────────────────────
    // Raios maiores = mais deslocamento/custo → acréscimo proporcional.
    if (raioKm > 10) {
      valor *= 1.20;
      fatores.add(const PrecoFator('Raio acima de 10 km', '+20%'));
    } else if (raioKm > 5) {
      valor *= 1.10;
      fatores.add(const PrecoFator('Raio de 5–10 km', '+10%'));
    }

    // ── Faixa de horário ─────────────────────────────────────────────
    final h = inicio.hour;
    final bool noturno = h >= 22 || h < 6;
    final bool pico = (h >= 11 && h < 14) || (h >= 18 && h < 21);
    if (noturno) {
      valor *= 1.25;
      fatores.add(const PrecoFator('Horário noturno', '+25%'));
    } else if (pico) {
      valor *= 1.15;
      fatores.add(const PrecoFator('Horário de pico', '+15%'));
    }

    // ── Dia da semana ────────────────────────────────────────────────
    final fds =
        inicio.weekday == DateTime.saturday || inicio.weekday == DateTime.sunday;
    if (fds) {
      valor *= 1.10;
      fatores.add(const PrecoFator('Fim de semana', '+10%'));
    }

    // Arredonda para múltiplo de R$5 (valores "redondos" convertem melhor).
    final arredondado = (valor / 5).round() * 5.0;
    final finalValor = arredondado < piso ? piso : arredondado;

    return PrecoResultado(valor: finalValor, fatores: fatores);
  }
}

@immutable
class PrecoFator {
  final String rotulo;
  final String ajuste;
  const PrecoFator(this.rotulo, this.ajuste);
}

@immutable
class PrecoResultado {
  final double valor;
  final List<PrecoFator> fatores;
  const PrecoResultado({required this.valor, required this.fatores});
}
