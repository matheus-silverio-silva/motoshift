import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ── PrimaryButton ─────────────────────────────────────────────────────────────
/// Botão primário com gradiente teal. Fiel ao .btn-primary do protótipo.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Widget? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scale = Tween(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        if (!widget.loading) widget.onPressed?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0xCC0E8B8C),
                blurRadius: 22,
                spreadRadius: -10,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFFFFF),
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        widget.icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: tsJakarta(13.5, FontWeight.w700,
                            color: const Color(0xFFFFFFFF)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── AmberButton ───────────────────────────────────────────────────────────────
/// Botão amber — CTA de destaque (ex: "Publicar novo turno").
class AmberButton extends StatefulWidget {
  const AmberButton({
    required this.label,
    this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  @override
  State<AmberButton> createState() => _AmberButtonState();
}

class _AmberButtonState extends State<AmberButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 90));
    _scale = Tween(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.amber,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0xBBF6A623),
                blurRadius: 22,
                spreadRadius: -10,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style:
                      tsJakarta(13.5, FontWeight.w700, color: const Color(0xFF3A2603)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── GhostButton ───────────────────────────────────────────────────────────────
/// Botão contornado (ghost) — variante neutra ou de perigo.
class GhostButton extends StatelessWidget {
  const GhostButton({
    required this.label,
    this.onPressed,
    this.danger = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? const Color(0xFFFBE4E2) : AppColors.surface2;
    final border = danger ? const Color(0xFFFBE4E2) : AppColors.line;
    final fg = danger ? const Color(0xFFC0392B) : AppColors.tealDeep;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Text(label,
                  style: tsJakarta(13.5, FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
