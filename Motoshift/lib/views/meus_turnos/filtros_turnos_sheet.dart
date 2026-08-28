import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// BottomSheet de filtros da lista de turnos disponíveis.
///
/// Morava no fim de meus_turnos_screen.dart, que tinha 1.415 linhas com três
/// classes dentro. Já era um widget independente — só não tinha arquivo.
class FiltrosTurnosSheet extends StatefulWidget {
  final String? horarioInicio;
  final String? horarioFim;
  final int? diaSemana;
  final double? raioMax;
  final String ordenarPor;
  final void Function(String?, String?, int?, double?, String) onAplicar;
  final VoidCallback onLimpar;

  const FiltrosTurnosSheet({
    super.key,
    required this.horarioInicio,
    required this.horarioFim,
    required this.diaSemana,
    required this.raioMax,
    required this.ordenarPor,
    required this.onAplicar,
    required this.onLimpar,
  });

  @override
  State<FiltrosTurnosSheet> createState() => _FiltrosTurnosSheetState();
}

class _FiltrosTurnosSheetState extends State<FiltrosTurnosSheet> {
  String? _horarioInicio;
  String? _horarioFim;
  int? _diaSemana;
  double _raioMax = 20.0;
  bool _raioAtivo = false;
  String _ordenarPor = 'valorAsc';

  static const _dias = [
    (1, 'Seg'), (2, 'Ter'), (3, 'Qua'),
    (4, 'Qui'), (5, 'Sex'), (6, 'Sáb'), (7, 'Dom'),
  ];

  static const _ordens = [
    ('valorAsc', 'Maior valor'),
    ('valorDesc', 'Menor valor'),
    ('raioAsc', 'Menor raio'),
    ('dataInicio', 'Mais cedo'),
  ];

  @override
  void initState() {
    super.initState();
    _horarioInicio = widget.horarioInicio;
    _horarioFim = widget.horarioFim;
    _diaSemana = widget.diaSemana;
    _raioAtivo = widget.raioMax != null;
    _raioMax = widget.raioMax ?? 20.0;
    _ordenarPor = widget.ordenarPor;
  }

  Future<void> _pickHorario(bool isInicio) async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (result != null) {
      final str =
          '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isInicio) _horarioInicio = str;
        else _horarioFim = str;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Filtrar Turnos',
                    style: tsBricolage(16, FontWeight.w800,
                        color: AppColors.ink)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.onLimpar();
                    Navigator.pop(context);
                  },
                  child: Text('Limpar',
                      style: tsJakarta(12, FontWeight.w600,
                          color: AppColors.teal)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Horário'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _timeChip(
                          label: _horarioInicio ?? 'Início',
                          onTap: () => _pickHorario(true),
                          active: _horarioInicio != null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _timeChip(
                          label: _horarioFim ?? 'Fim',
                          onTap: () => _pickHorario(false),
                          active: _horarioFim != null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _label('Dia da semana'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _dias.map((d) {
                      final sel = _diaSemana == d.$1;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _diaSemana = sel ? null : d.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.teal
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(d.$2,
                              style: tsJakarta(12, FontWeight.w700,
                                  color: sel
                                      ? Colors.white
                                      : AppColors.ink)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: _label('Raio máximo de entrega')),
                      Switch(
                        value: _raioAtivo,
                        activeColor: AppColors.teal,
                        onChanged: (v) =>
                            setState(() => _raioAtivo = v),
                      ),
                    ],
                  ),
                  if (_raioAtivo) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.teal,
                              inactiveTrackColor: AppColors.surface3,
                              thumbColor: AppColors.teal,
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: _raioMax,
                              min: 2,
                              max: 30,
                              divisions: 14,
                              onChanged: (v) =>
                                  setState(() => _raioMax = v),
                            ),
                          ),
                        ),
                        Text(
                          '${_raioMax.toStringAsFixed(0)} km',
                          style: tsJakarta(12, FontWeight.w700,
                              color: AppColors.teal),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _label('Ordenar por'),
                  const SizedBox(height: 8),
                  ..._ordens.map((o) => RadioListTile<String>(
                        title: Text(o.$2,
                            style: tsJakarta(13, FontWeight.w500)),
                        value: o.$1,
                        groupValue: _ordenarPor,
                        activeColor: AppColors.teal,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setState(() => _ordenarPor = v!),
                      )),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).padding.bottom + 16),
            child: GestureDetector(
              onTap: () {
                widget.onAplicar(
                  _horarioInicio,
                  _horarioFim,
                  _diaSemana,
                  _raioAtivo ? _raioMax : null,
                  _ordenarPor,
                );
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('Aplicar filtros',
                      style: tsJakarta(14, FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: tsJakarta(12.5, FontWeight.w700, color: AppColors.ink));

  Widget _timeChip({
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? AppColors.tealSoft
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.teal.withOpacity(0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_rounded,
                size: 13,
                color: active ? AppColors.teal : AppColors.muted),
            const SizedBox(width: 5),
            Text(label,
                style: tsJakarta(12, FontWeight.w700,
                    color: active ? AppColors.teal : AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

