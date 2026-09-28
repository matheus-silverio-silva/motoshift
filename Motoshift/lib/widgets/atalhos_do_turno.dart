import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/turno.dart';
import '../models/usuario.dart';
import '../presentation/providers/turno_provider.dart';
import '../services/abrir_rota.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/baixar_arquivo.dart';
import '../utils/calendario_ics.dart';
import 'app_buttons.dart';

/// Dois atalhos para levar o turno para fora do app: a rota até o ponto e o
/// evento no calendário.
///
/// * **Abrir rota** — para o entregador, em turno que ainda vale e tem ponto
///   no mapa. Google Maps sempre; Waze também, quando instalado no celular.
/// * **Adicionar ao calendário** — um `.ics` com o horário de Curitiba e
///   alarme de 1 h ([CalendarioIcs]), pelo mesmo [baixarArquivo] da planilha.
///   Para o entregador, nos turnos em que está; para a loja, nos que publicou
///   e ainda não acabaram.
///
/// Some inteiro quando nenhum dos dois cabe.
class AtalhosDoTurno extends StatelessWidget {
  const AtalhosDoTurno({required this.turno, this.margem, super.key});

  final Turno turno;
  final EdgeInsetsGeometry? margem;

  static AbrirRota _rota(BuildContext context) {
    try {
      return Provider.of<AbrirRota>(context, listen: false);
    } on ProviderNotFoundException {
      return AbrirRota();
    }
  }

  bool get _vivo =>
      turno.status == StatusTurno.aberto ||
      turno.status == StatusTurno.aceito ||
      turno.status == StatusTurno.emAndamento;

  @override
  Widget build(BuildContext context) {
    final eu = context.watch<AuthService>().usuario;
    final ehLojista = eu?.tipo == TipoUsuario.lojista;
    final estouNoTurno = !ehLojista &&
        context
            .watch<TurnoProvider>()
            .meusTurnos
            .any((t) => t.id != null && t.id == turno.id);

    final rota = !ehLojista &&
        _vivo &&
        turno.latitude != null &&
        turno.longitude != null;
    final calendario = _vivo && (ehLojista || estouNoTurno);
    if (!rota && !calendario) return const SizedBox.shrink();

    final botoes = <Widget>[
      if (rota)
        GhostButton(
          key: const Key('atalho-rota'),
          label: 'Abrir rota',
          icon: const Icon(Icons.directions_outlined,
              size: 17, color: AppColors.tealDeep),
          onPressed: () => _abrirRota(context),
        ),
      if (calendario)
        GhostButton(
          key: const Key('atalho-calendario'),
          label: rota ? 'Calendário' : 'Adicionar ao calendário',
          icon: const Icon(Icons.event_outlined,
              size: 17, color: AppColors.tealDeep),
          onPressed: () => _adicionarAoCalendario(context),
        ),
    ];

    return Padding(
      padding: margem ?? EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < botoes.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: botoes[i]),
          ],
        ],
      ),
    );
  }

  Future<void> _abrirRota(BuildContext context) async {
    final rota = _rota(context);
    final lat = turno.latitude!, lng = turno.longitude!;
    final apps = await rota.disponiveis();
    if (!context.mounted) return;

    // Com um app só, abre direto; com dois, a pessoa escolhe.
    AppDeRota? escolhido = apps.length == 1 ? apps.first : null;
    escolhido ??= await showModalBottomSheet<AppDeRota>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text('Abrir rota com',
                style: tsBricolage(15, FontWeight.w800, color: AppColors.ink)),
            for (final app in apps)
              ListTile(
                key: Key('rota-${app.name}'),
                leading: Icon(
                    app == AppDeRota.waze
                        ? Icons.navigation_outlined
                        : Icons.map_outlined,
                    color: AppColors.tealDeep),
                title: Text(app == AppDeRota.waze ? 'Waze' : 'Google Maps'),
                onTap: () => Navigator.pop(ctx, app),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (escolhido == null) return;

    final ok = await rota.abrir(escolhido, lat, lng);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível abrir o mapa.'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _adicionarAoCalendario(BuildContext context) async {
    final bytes =
        Uint8List.fromList(CalendarioIcs.bytes(turno, agora: clock.now()));
    try {
      await baixarArquivo(
          bytes, CalendarioIcs.nomeDoArquivo(turno), 'text/calendar');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Evento "${turno.titulo}" pronto — abra o arquivo para '
            'adicionar ao calendário.'),
        backgroundColor: AppColors.teal,
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível gerar o evento.'),
        backgroundColor: AppColors.error,
      ));
    }
  }
}
