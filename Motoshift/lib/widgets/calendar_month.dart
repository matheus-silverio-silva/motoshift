import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Calendário mensal com marcações de turnos. Fiel ao .cal do protótipo.
class CalendarMonth extends StatelessWidget {
  const CalendarMonth({
    required this.year,
    required this.month,
    required this.markedDays,
    this.selectedDay,
    this.today,
    this.onDayTap,
    super.key,
  });

  final int year;
  final int month;
  final Set<int> markedDays;
  final int? selectedDay;
  final int? today;
  final ValueChanged<int>? onDayTap;

  static const _dayNames = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  static const _monthNames = [
    '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 12),
          _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ArrowBtn(
          icon: Icons.chevron_left_rounded,
          onTap: () {
            // navegação de mês — controlada pelo pai
          },
        ),
        Text(
          '${_monthNames[month]} $year',
          style: tsBricolage(13, FontWeight.w800, color: AppColors.ink),
        ),
        _ArrowBtn(
          icon: Icons.chevron_right_rounded,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildGrid() {
    // Dia da semana do primeiro dia do mês (0=Dom, 6=Sáb)
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    // Total de dias no mês
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Dias do mês anterior para completar primeira linha
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;
    final daysInPrev = DateTime(prevYear, prevMonth + 1, 0).day;

    final cells = <_DayCell>[];
    // Dias do mês anterior (muted)
    for (int i = firstWeekday - 1; i >= 0; i--) {
      cells.add(_DayCell(
          day: daysInPrev - i, muted: true, onTap: null, marked: false));
    }
    // Dias do mês atual
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(_DayCell(
        day: d,
        muted: false,
        marked: markedDays.contains(d),
        selected: d == selectedDay,
        isToday: d == today,
        onTap: () => onDayTap?.call(d),
      ));
    }
    // Preenche até múltiplo de 7
    int nextDay = 1;
    while (cells.length % 7 != 0) {
      cells.add(_DayCell(day: nextDay++, muted: true, onTap: null, marked: false));
    }

    return Column(
      children: [
        // Cabeçalho de dias da semana
        Row(
          children: _dayNames
              .map((d) => Expanded(
                    child: Text(d,
                        textAlign: TextAlign.center,
                        style: tsJakarta(8, FontWeight.w700,
                            color: AppColors.muted)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        // Linhas de semanas
        for (int row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: List.generate(7, (col) {
              final cell = cells[row * 7 + col];
              return Expanded(child: cell);
            }),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.muted,
    required this.marked,
    this.selected = false,
    this.isToday = false,
    this.onTap,
  });

  final int day;
  final bool muted;
  final bool marked;
  final bool selected;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color? bgColor;
    BoxBorder? border;

    if (selected) {
      bgColor = AppColors.teal;
      textColor = const Color(0xFFFFFFFF);
    } else if (muted) {
      textColor = const Color(0xFFC4D2D1);
    } else {
      textColor = AppColors.text;
    }
    if (isToday && !selected) {
      border = Border.all(color: AppColors.teal, width: 1.5);
    }

    return GestureDetector(
      onTap: muted ? null : onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(9),
            border: border,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: tsJakarta(10, FontWeight.w700, color: textColor),
              ),
              if (marked)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFFFFFFF)
                        : AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: AppColors.teal),
      ),
    );
  }
}
