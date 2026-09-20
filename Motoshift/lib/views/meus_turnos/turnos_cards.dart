import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../models/turno.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shift_card.dart';
import '../../widgets/status_pill.dart';

/// Os dois cartões da tela de turnos do entregador: o turno disponível, que
/// só leva ao detalhe, e o turno em andamento, que age sobre ele.
///
/// Saíram do State da tela — que passava de 800 linhas — pelo mesmo caminho do
/// [TurnosConteudoDesktop]: o que é desenho vira widget com parâmetros
/// explícitos, o que é decisão continua na tela. O cartão em andamento não
/// conhece provider nem SnackBar: recebe o que fazer ao confirmar e ao
/// cancelar, e quem sabe tratar erro é quem passou os callbacks.

/// Turno aberto na lista de disponíveis.
class TurnoDisponivelCard extends StatelessWidget {
  const TurnoDisponivelCard({required this.turno, super.key});

  final Turno turno;

  @override
  Widget build(BuildContext context) {
    return ShiftCard(
      horario: turno.horarioFormatado,
      name: turno.titulo,
      meta: [
        turno.regiao,
        // distanciaKm só vem quando a busca foi por raio; fora disso mostra o
        // raio de entrega do turno, como sempre mostrou.
        if (turno.distanciaKm != null)
          'a ${turno.distanciaKm!.toStringAsFixed(1).replaceAll('.', ',')} km'
        else
          '${turno.raioEntregaKm.toStringAsFixed(0)} km',
        if (turno.multiVaga) '${turno.vagasRestantes} de ${turno.vagas} vagas',
      ],
      value: 'R\$ ${turno.valorEstimado.toStringAsFixed(0)}',
      iconData: Icons.two_wheeler_outlined,
      // O chip "Ver" saiu: ele abria exatamente o que o toque no card já abre,
      // e com 24px de altura ficava abaixo do alvo mínimo de 44px. A pílula de
      // vagas ocupa o lugar e informa mais.
      pillLabel: turno.multiVaga
          ? '${turno.vagasRestantes} ${turno.vagasRestantes == 1 ? 'vaga' : 'vagas'}'
          : null,
      pillVariant: PillVariant.teal,
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.detalheTurno,
        arguments: turno,
      ),
    );
  }
}

/// Turno em andamento, com as duas ações do entregador.
class TurnoAtivoCard extends StatelessWidget {
  const TurnoAtivoCard({
    required this.turno,
    required this.onConfirmarConclusao,
    required this.onCancelar,
    super.key,
  });

  final Turno turno;
  final VoidCallback onConfirmarConclusao;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.tealSoft, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.two_wheeler_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(turno.titulo,
                        style:
                            tsJakarta(13, FontWeight.w700, color: AppColors.ink)),
                    Text(turno.horarioFormatado,
                        style: tsJakarta(10.5, FontWeight.w400,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const StatusPill(
                  label: 'Em andamento',
                  variant: PillVariant.amber,
                  leadingDot: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onConfirmarConclusao,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'Confirmar conclusão',
                        style: tsJakarta(12, FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCancelar,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: Text(
                    'Cancelar',
                    style:
                        tsJakarta(12, FontWeight.w700, color: AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Amanhã, 14:00 – 18:00" / "Hoje, ..." / "Qua, ...".
///
/// A data de referência é parâmetro, como nas outras telas com golden. Sem
/// isso, a seção "Próximos turnos" mudava de rótulo à meia-noite e o golden
/// desta tela ia junto.
String formatarProximoData(DateTime inicio, DateTime fim, {DateTime? agora}) {
  final referencia = agora ?? clock.now();
  final diff = inicio.difference(
      DateTime(referencia.year, referencia.month, referencia.day));
  String dia;
  if (diff.inDays == 1) {
    dia = 'Amanhã';
  } else if (diff.inDays == 0) {
    dia = 'Hoje';
  } else {
    const semana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    dia = semana[inicio.weekday % 7];
  }
  return '$dia, ${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')} – ${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}';
}
