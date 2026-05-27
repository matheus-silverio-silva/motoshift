import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  MotoShift Design System — paleta teal aprovada em protótipo de alta fidelidade
// ══════════════════════════════════════════════════════════════════════════════

class AppColors {
  AppColors._();

  // ── Paleta principal ─────────────────────────────────────────────────────
  static const Color teal       = Color(0xFF0E8B8C);
  static const Color tealBright = Color(0xFF16B5B0);
  static const Color tealDeep   = Color(0xFF0A4D52);
  static const Color ink        = Color(0xFF062E33);

  static const Color surface  = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF2F6F5);
  static const Color surface3 = Color(0xFFE7EFEE);
  static const Color line     = Color(0xFFE2EAE9);

  static const Color text  = Color(0xFF0F2C30);
  static const Color muted = Color(0xFF6B8487);

  static const Color amber     = Color(0xFFF6A623);
  static const Color amberSoft = Color(0xFFFFF1D6);
  static const Color tealSoft  = Color(0xFFDEF1F0);
  static const Color good      = Color(0xFF1B9E73);
  static const Color goodSoft  = Color(0xFFDDF3EA);

  static const Color error          = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);

  // ── Gradientes ───────────────────────────────────────────────────────────
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, tealDeep],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tealBright, teal],
  );

  static const LinearGradient loginBgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [tealDeep, Color(0xFF062E33), Color(0xFF04181b)],
    stops: [0.0, 0.62, 1.0],
  );

  static const LinearGradient walletGradient = LinearGradient(
    begin: Alignment(-0.7, -0.7),
    end: Alignment(0.7, 0.7),
    colors: [teal, tealDeep],
  );

  // ── Aliases legados — usados pelos kinetic_* widgets; remover após migração ─
  static const Color primary                 = teal;
  static const Color primaryContainer        = tealBright;
  static const Color onPrimary               = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer      = tealSoft;
  static const Color secondary               = muted;
  static const Color onSecondary             = Color(0xFFFFFFFF);
  static const Color secondaryContainer      = surface3;
  static const Color onSecondaryContainer    = text;
  static const Color tertiary                = amber;
  static const Color onTertiary              = Color(0xFF3A2603);
  static const Color tertiaryContainer       = amberSoft;
  static const Color onTertiaryContainer     = Color(0xFF9A6206);
  static const Color background              = surface2;
  static const Color surfaceBright           = surface;
  static const Color surfaceDim              = surface3;
  static const Color onBackground            = text;
  static const Color onSurface              = text;
  static const Color onSurfaceVariant        = muted;
  static const Color surfaceContainerLowest  = surface;
  static const Color surfaceContainerLow     = surface2;
  static const Color surfaceContainer        = surface3;
  static const Color surfaceContainerHigh    = line;
  static const Color surfaceContainerHighest = line;
  static const Color surfaceVariant          = surface3;
  static const Color surfaceTint             = teal;
  static const Color outline                 = muted;
  static const Color outlineVariant          = line;
  static const Color onError                 = Color(0xFFFFFFFF);
  static const Color onErrorContainer        = Color(0xFF93000A);
  static const Color inverseSurface          = ink;
  static const Color inverseOnSurface        = surface2;
  static const Color inversePrimary          = tealSoft;
  static const Color primaryFixed            = tealSoft;
  static const Color primaryFixedDim         = Color(0xFFBCE0DF);
  static const Color onPrimaryFixed          = tealDeep;
  static const Color onPrimaryFixedVariant   = teal;
  static const LinearGradient kineticGradient = primaryGradient;

  static List<BoxShadow> kineticShadow = const [
    BoxShadow(color: Color(0x140E8B8C), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static List<BoxShadow> bottomNavShadow = const [
    BoxShadow(color: Color(0x140E8B8C), blurRadius: 24, offset: Offset(0, -8)),
  ];
}

// ── Helpers de estilo de texto ───────────────────────────────────────────────
TextStyle tsBricolage(double size, FontWeight w, {Color? color}) =>
    GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: w,
      color: color ?? AppColors.text,
      height: 1.2,
    );

TextStyle tsJakarta(double size, FontWeight w, {Color? color, double? height}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: w,
      color: color ?? AppColors.text,
      height: height,
    );

// ── Tema central ─────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface2,
      colorScheme: const ColorScheme.light(
        primary: AppColors.teal,
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: AppColors.tealSoft,
        onPrimaryContainer: AppColors.tealDeep,
        secondary: AppColors.amber,
        onSecondary: Color(0xFF3A2603),
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.error,
        onError: Color(0xFFFFFFFF),
        outline: AppColors.line,
        outlineVariant: AppColors.surface3,
      ),
      textTheme: TextTheme(
        displayLarge:   tsBricolage(32,   FontWeight.w800),
        displayMedium:  tsBricolage(26,   FontWeight.w800),
        displaySmall:   tsBricolage(22,   FontWeight.w800),
        headlineLarge:  tsBricolage(20,   FontWeight.w800),
        headlineMedium: tsBricolage(18,   FontWeight.w800),
        headlineSmall:  tsBricolage(16,   FontWeight.w800),
        titleLarge:     tsBricolage(15,   FontWeight.w700),
        titleMedium:    tsJakarta(14,     FontWeight.w700),
        titleSmall:     tsJakarta(13,     FontWeight.w700),
        bodyLarge:      tsJakarta(14,     FontWeight.w400),
        bodyMedium:     tsJakarta(13,     FontWeight.w400, color: AppColors.muted),
        bodySmall:      tsJakarta(11,     FontWeight.w400, color: AppColors.muted),
        labelLarge:     tsJakarta(13.5,   FontWeight.w700),
        labelMedium:    tsJakarta(11,     FontWeight.w700),
        labelSmall:     tsJakarta(9.5,    FontWeight.w700, color: AppColors.muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.teal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.muted,
          fontSize: 12.5,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.line, width: 1.5),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
      ),
    );
  }
}
