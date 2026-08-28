import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Cabeçalho com gradiente teal — dois construtores nomeados:
///   AppHeader.back      — seta voltar + título centralizado (telas 3, 6, 7, 10, 11)
///   AppHeader.greeting  — saudação + nome + avatar (telas 2, 4, 5, 8)
class AppHeader extends StatelessWidget {
  // ── variante "voltar + título" ─────────────────────────────────────────
  const AppHeader.back({
    required String title,
    VoidCallback? onBack,
    Widget? trailing,
    super.key,
  })  : _isGreeting = false,
        _title = title,
        _onBack = onBack,
        _trailing = trailing,
        _greeting = null,
        _name = null,
        _avatarInitials = null,
        _notificacoes = 0,
        _onNotificacoes = null;

  // ── variante "saudação + nome + avatar" ───────────────────────────────
  const AppHeader.greeting({
    required String greeting,
    required String name,
    required String avatarInitials,
    int notificacoes = 0,
    VoidCallback? onNotificacoes,
    super.key,
  })  : _isGreeting = true,
        _greeting = greeting,
        _name = name,
        _avatarInitials = avatarInitials,
        _notificacoes = notificacoes,
        _onNotificacoes = onNotificacoes,
        _title = null,
        _onBack = null,
        _trailing = null;

  final bool _isGreeting;
  final String? _title;
  final VoidCallback? _onBack;
  final Widget? _trailing;
  final String? _greeting;
  final String? _name;
  final String? _avatarInitials;
  final int _notificacoes;
  final VoidCallback? _onNotificacoes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // O 8 embaixo no modo "voltar" compensa os 10px que o botão ganhou
          // ao chegar nos 44px de alvo de toque: a altura total do header
          // continua a mesma, e nada abaixo dele se desloca.
          padding: EdgeInsets.fromLTRB(18, 4, 18, _isGreeting ? 28 : 8),
          child: _isGreeting ? _buildGreeting() : _buildBack(context),
        ),
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    return Row(
      children: [
        _BackButton(onTap: _onBack),
        Expanded(
          child: Text(
            _title ?? '',
            textAlign: TextAlign.center,
            style: tsBricolage(16, FontWeight.w800,
                color: const Color(0xFFFFFFFF)),
          ),
        ),
        if (_trailing != null)
          SizedBox(width: 34, height: 34, child: _trailing)
        else
          const SizedBox(width: 34),
      ],
    );
  }

  Widget _buildGreeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _greeting ?? '',
                style: tsJakarta(11, FontWeight.w600,
                    color: const Color(0xFFBFE5E3)),
              ),
              const SizedBox(height: 2),
              Text(
                _name ?? '',
                style: tsBricolage(18, FontWeight.w800,
                    color: const Color(0xFFFFFFFF)),
              ),
            ],
          ),
        ),
        if (_onNotificacoes != null) ...[
          _HeaderSino(
            quantidade: _notificacoes,
            onTap: _onNotificacoes,
          ),
          const SizedBox(width: 10),
        ],
        _HeaderAvatar(initials: _avatarInitials ?? ''),
      ],
    );
  }
}

/// Sino do header mobile — 44px de alvo de toque, badge âmbar quando há
/// não lidas. Só aparece quando a tela passa [onNotificacoes].
class _HeaderSino extends StatelessWidget {
  const _HeaderSino({required this.quantidade, this.onTap});

  final int quantidade;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0x29FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0x38FFFFFF), width: 1.5),
                ),
                child: const Icon(Icons.notifications_outlined,
                    size: 19, color: Color(0xFFEAFFFD)),
              ),
            ),
            if (quantidade > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: AppColors.tealDeep, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      quantidade > 9 ? '9+' : '$quantidade',
                      style: tsJakarta(9.5, FontWeight.w800,
                          color: AppColors.onTertiary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _BackButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    // Mesmo padrão do sino aqui do lado: o quadrado visível continua com 34,
    // mas a área que responde ao toque tem os 44 do mínimo. Sem o `opaque` o
    // espaço em volta do Container não recebe o toque.
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0x24FFFFFF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.chevron_left_rounded,
              color: Color(0xFFFFFFFF),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final String initials;
  const _HeaderAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0x29FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x38FFFFFF), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: tsBricolage(14, FontWeight.w800,
              color: const Color(0xFFEAFFFD)),
        ),
      ),
    );
  }
}
