import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Estado de cada etapa da linha do tempo
enum StepState { done, current, pending }

@immutable
class TimelineStep {
  const TimelineStep({
    required this.label,
    required this.subtitle,
    required this.state,
  });

  final String label;
  final String subtitle;
  final StepState state;
}

/// Linha do tempo vertical de andamento do turno. Fiel ao .timeline do protótipo.
class TimelineStepper extends StatelessWidget {
  const TimelineStepper({required this.steps, super.key});
  final List<TimelineStep> steps;

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
        children: List.generate(steps.length, (i) {
          final step = steps[i];
          final isLast = i == steps.length - 1;
          return _StepRow(step: step, showLine: !isLast);
        }),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.showLine});
  final TimelineStep step;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coluna do dot + linha vertical
          SizedBox(
            width: 18,
            child: Column(
              children: [
                _Dot(state: step.state),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: step.state == StepState.done
                          ? AppColors.teal
                          : AppColors.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          // Texto da etapa
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? 15 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.label,
                    style: tsJakarta(
                      11.5,
                      FontWeight.w700,
                      color: step.state == StepState.pending
                          ? AppColors.muted
                          : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    step.subtitle,
                    style: tsJakarta(9, FontWeight.w400,
                        color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});
  final StepState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      StepState.done => Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: AppColors.teal,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              size: 10, color: Color(0xFFFFFFFF)),
        ),
      StepState.current => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.teal, width: 3),
            boxShadow: const [
              BoxShadow(
                color: AppColors.tealSoft,
                blurRadius: 0,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
      StepState.pending => Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: AppColors.surface3,
            shape: BoxShape.circle,
          ),
        ),
    };
  }
}
