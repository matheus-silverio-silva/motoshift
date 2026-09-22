import 'package:intl/intl.dart';

/// Formatação dos documentos fiscais — a mesma na tela e no PDF.
///
/// Se a tela dissesse "R$ 1.234,50" e o PDF "R$ 1234.5", o documento baixado
/// seria outro documento. Um lugar só para os dois.
class FormatoFiscal {
  FormatoFiscal._();

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  static String moeda(double valor) => _moeda.format(valor);

  /// 0.05 → "5%"; 0.015 → "1,5%".
  static String percentual(double aliquota) {
    final pct = aliquota * 100;
    final texto = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    return '${texto.replaceAll('.', ',')}%';
  }

  static String data(DateTime d) => DateFormat('dd/MM/yyyy', 'pt_BR').format(d);

  static String dataHora(DateTime d) =>
      DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(d);

  /// "CNPJ **.345.678/0001-**", ou "CPF não informado no cadastro".
  static String documento(String tipo, String? numero) =>
      numero == null || numero.isEmpty
          ? '$tipo não informado no cadastro'
          : '$tipo $numero';
}
