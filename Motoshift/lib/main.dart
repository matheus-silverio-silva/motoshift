import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // As fontes do tema vão embarcadas (assets/fonts, ver pubspec.yaml). Sem
  // esta linha o google_fonts ainda as baixaria de fonts.gstatic.com quando
  // não achasse um peso nos assets — e o app dependeria de rede para ter a
  // cara certa. Desligado, um peso que falte aparece como erro no console em
  // desenvolvimento, em vez de virar um download silencioso em produção.
  GoogleFonts.config.allowRuntimeFetching = false;

  await initializeDateFormatting('pt_BR', null);

  // Status bar transparente para o efeito glassmorphism da AppBar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MotoShiftApp());
}
