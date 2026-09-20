import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../services/preco_recomendado.dart';
import '../../theme/app_theme.dart';

/// Os campos do formulário de publicar turno: data, horário, raio, vagas e a
/// recomendação de valor.
///
/// Saíram do State da tela, que passava de mil linhas juntando formulário,
/// mapa, layout de celular e layout de desktop. São widgets sem estado: cada
/// um recebe o valor atual e o que fazer quando ele muda — quem guarda o
/// estado e valida o formulário continua sendo a tela.

/// Data do turno. Abre o seletor no toque.
class CardData extends StatelessWidget {
  const CardData({required this.data, required this.onEscolher, super.key});

  final DateTime? data;
  final VoidCallback onEscolher;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEscolher,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  color: AppColors.teal, size: 14),
              const SizedBox(width: 5),
              Text('DATA',
                  style: tsJakarta(9, FontWeight.w700, color: AppColors.teal)),
            ]),
            const SizedBox(height: 10),
            Text(
              data != null
                  ? DateFormat('dd/MM/yyyy', 'pt_BR').format(data!)
                  : 'Selecionar',
              style: tsJakarta(13, FontWeight.w600,
                  color: data != null ? AppColors.ink : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Início e fim do turno, lado a lado.
class CardHorario extends StatelessWidget {
  const CardHorario({
    required this.inicio,
    required this.fim,
    required this.onEscolherInicio,
    required this.onEscolherFim,
    super.key,
  });

  final TimeOfDay? inicio;
  final TimeOfDay? fim;
  final VoidCallback onEscolherInicio;
  final VoidCallback onEscolherFim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_outlined,
                color: AppColors.teal, size: 14),
            const SizedBox(width: 5),
            Text('HORÁRIO',
                style: tsJakarta(9, FontWeight.w700, color: AppColors.teal)),
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onEscolherInicio,
                  child: _ChipDeHora(hora: inicio),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text('—',
                    style:
                        tsJakarta(12, FontWeight.w400, color: AppColors.muted)),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onEscolherFim,
                  child: _ChipDeHora(hora: fim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipDeHora extends StatelessWidget {
  const _ChipDeHora({required this.hora});

  final TimeOfDay? hora;

  @override
  Widget build(BuildContext context) {
    final t = hora;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        t != null
            ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : '--:--',
        textAlign: TextAlign.center,
        style: tsJakarta(13, FontWeight.w600,
            color: t != null ? AppColors.ink : AppColors.muted),
      ),
    );
  }
}

/// Raio de atuação declarado pelo lojista (1 a 20 km).
class SecaoRaio extends StatelessWidget {
  const SecaoRaio({required this.raioKm, required this.onMudar, super.key});

  final double raioKm;
  final ValueChanged<double> onMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Row(children: [
              const Icon(Icons.straighten_outlined,
                  color: AppColors.teal, size: 14),
              const SizedBox(width: 5),
              Text('RAIO DE ENTREGA',
                  style: tsJakarta(9, FontWeight.w700, color: AppColors.teal)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Até ${raioKm.toStringAsFixed(0)} km',
                style:
                    tsJakarta(9.5, FontWeight.w700, color: AppColors.tealDeep),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.teal,
            inactiveTrackColor: AppColors.surface3,
            thumbColor: AppColors.teal,
            overlayColor: AppColors.teal.withOpacity(0.15),
            trackHeight: 3,
          ),
          child: Slider(
            value: raioKm,
            min: 1,
            max: 20,
            divisions: 19,
            onChanged: onMudar,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['1km', '5km', '10km', '15km', '20km+']
                .map((s) => Text(s,
                    style:
                        tsJakarta(9, FontWeight.w700, color: AppColors.muted)))
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// Quantos entregadores o lojista precisa no mesmo turno (1 a 20).
class SecaoVagas extends StatelessWidget {
  const SecaoVagas({required this.vagas, required this.onMudar, super.key});

  final int vagas;
  final ValueChanged<int> onMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.groups_outlined, color: AppColors.teal, size: 14),
          const SizedBox(width: 5),
          Text('VAGAS DE ENTREGADOR',
              style: tsJakarta(9, FontWeight.w700, color: AppColors.teal)),
          const Spacer(),
          Text(
            vagas == 1 ? '1 entregador' : '$vagas entregadores',
            style: tsJakarta(10, FontWeight.w600, color: AppColors.muted),
          ),
        ]),
        const SizedBox(height: 10),
        Row(
          children: [
            _BotaoDeVaga(
              icon: Icons.remove_rounded,
              enabled: vagas > 1,
              onTap: () => onMudar(vagas - 1),
            ),
            Expanded(
              child: Center(
                child: Text('$vagas',
                    style:
                        tsBricolage(22, FontWeight.w800, color: AppColors.ink)),
              ),
            ),
            _BotaoDeVaga(
              icon: Icons.add_rounded,
              enabled: vagas < 20,
              onTap: () => onMudar(vagas + 1),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Quantos entregadores você precisa neste mesmo turno.',
          style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _BotaoDeVaga extends StatelessWidget {
  const _BotaoDeVaga({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? AppColors.tealSoft : AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Icon(icon,
            size: 20, color: enabled ? AppColors.tealDeep : AppColors.line),
      ),
    );
  }
}

/// Valor recomendado para o turno, com os fatores que o explicam.
///
/// Sem data e horário não há o que recomendar — e dizer isso é melhor do que
/// mostrar um número que não considera o que ainda não foi preenchido.
class CardRecomendacao extends StatelessWidget {
  const CardRecomendacao({
    required this.recomendacao,
    required this.onUsarValor,
    super.key,
  });

  final PrecoResultado? recomendacao;
  final ValueChanged<double> onUsarValor;

  @override
  Widget build(BuildContext context) {
    final rec = recomendacao;
    if (rec == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'Defina data e horário para ver o valor recomendado.',
          style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.teal.withOpacity(0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.tealDeep, size: 15),
              const SizedBox(width: 6),
              Text('Valor recomendado',
                  style: tsJakarta(10.5, FontWeight.w700,
                      color: AppColors.tealDeep)),
              const Spacer(),
              Text('R\$ ${rec.valor.toStringAsFixed(0)}',
                  style: tsBricolage(18, FontWeight.w800,
                      color: AppColors.tealDeep)),
            ],
          ),
          if (rec.fatores.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rec.fatores
                  .map((f) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${f.rotulo} ${f.ajuste}',
                            style: tsJakarta(9, FontWeight.w600,
                                color: AppColors.muted)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => onUsarValor(rec.valor),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'Usar valor recomendado',
                textAlign: TextAlign.center,
                style: tsJakarta(11.5, FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
