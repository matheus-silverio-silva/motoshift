import 'package:flutter/widgets.dart';

/// Breakpoints de largura da janela — decisão de implementação (o protótipo v2
/// traz artboards de 390px e 1440px; os cortes abaixo definem qual shell entra).
///
///   mobile   < 600
///   tablet   600 .. 1023
///   desktop  >= 1024
class Breakpoints {
  Breakpoints._();

  static const double tablet = 600;
  static const double desktop = 1024;
}

extension BreakpointContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  bool get isMobile => _width < Breakpoints.tablet;

  bool get isTablet =>
      _width >= Breakpoints.tablet && _width < Breakpoints.desktop;

  bool get isDesktop => _width >= Breakpoints.desktop;
}
