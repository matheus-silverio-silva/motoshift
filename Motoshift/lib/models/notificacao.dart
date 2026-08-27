import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Notificação in-app (RF09 / SCRUM-20).
///
/// Espelha o `toMap` de `NotificacaoController`: id, tipo, titulo, mensagem,
/// referenciaTipo, referenciaId, lida e criadoEm.
class Notificacao {
  const Notificacao({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensagem,
    required this.lida,
    required this.criadoEm,
    this.referenciaTipo,
    this.referenciaId,
  });

  final int id;
  final String tipo;
  final String titulo;
  final String mensagem;
  final bool lida;
  final DateTime criadoEm;
  final String? referenciaTipo;
  final int? referenciaId;

  factory Notificacao.fromJson(Map<String, dynamic> json) {
    return Notificacao(
      id: (json['id'] as num).toInt(),
      tipo: json['tipo'] as String? ?? '',
      titulo: json['titulo'] as String? ?? '',
      mensagem: json['mensagem'] as String? ?? '',
      lida: json['lida'] == true,
      criadoEm: json['criadoEm'] != null
          ? DateTime.parse(json['criadoEm'] as String)
          : DateTime.now(),
      referenciaTipo: json['referenciaTipo'] as String?,
      referenciaId: (json['referenciaId'] as num?)?.toInt(),
    );
  }

  /// Aparência por tipo. Um tipo desconhecido cai no visual neutro em vez de
  /// quebrar — o backend pode ganhar tipos novos sem o app ser atualizado.
  NotificacaoEstilo get estilo => switch (tipo) {
        'turno_aceito' => const NotificacaoEstilo(
            icone: Icons.check_circle_outline,
            fundo: AppColors.tealSoft,
            frente: AppColors.tealDeep,
          ),
        'turno_lotado' => const NotificacaoEstilo(
            icone: Icons.groups_outlined,
            fundo: AppColors.tealSoft,
            frente: AppColors.tealDeep,
          ),
        'pagamento_confirmado' => const NotificacaoEstilo(
            icone: Icons.payments_outlined,
            fundo: AppColors.goodSoft,
            frente: Color(0xFF0F6E4E),
          ),
        'turno_vencendo' => const NotificacaoEstilo(
            icone: Icons.schedule_outlined,
            fundo: AppColors.amberSoft,
            frente: Color(0xFF9A6206),
          ),
        'turno_pendente_finalizacao' => const NotificacaoEstilo(
            icone: Icons.hourglass_bottom_outlined,
            fundo: AppColors.amberSoft,
            frente: Color(0xFF9A6206),
          ),
        'avaliacao_pendente' => const NotificacaoEstilo(
            icone: Icons.star_outline_rounded,
            fundo: AppColors.amberSoft,
            frente: Color(0xFF9A6206),
          ),
        'turno_expirado' => const NotificacaoEstilo(
            icone: Icons.timer_off_outlined,
            fundo: AppColors.surface3,
            frente: AppColors.muted,
          ),
        _ => const NotificacaoEstilo(
            icone: Icons.notifications_outlined,
            fundo: AppColors.surface3,
            frente: AppColors.muted,
          ),
      };

  /// Grupo de dia usado no cabeçalho da lista.
  String get grupoDia {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(criadoEm.year, criadoEm.month, criadoEm.day);
    if (dia == hoje) return 'HOJE';
    if (dia == hoje.subtract(const Duration(days: 1))) return 'ONTEM';
    return '${dia.day.toString().padLeft(2, '0')}/'
        '${dia.month.toString().padLeft(2, '0')}';
  }

  /// "há 12 min", "há 3 h", "há 2 d".
  String get tempoRelativo {
    final d = DateTime.now().difference(criadoEm);
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
    if (d.inHours < 24) return 'há ${d.inHours} h';
    return 'há ${d.inDays} d';
  }
}

class NotificacaoEstilo {
  const NotificacaoEstilo({
    required this.icone,
    required this.fundo,
    required this.frente,
  });

  final IconData icone;
  final Color fundo;
  final Color frente;
}
