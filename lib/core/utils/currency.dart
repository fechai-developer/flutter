import 'package:intl/intl.dart';

/// Formatação monetária centralizada em R$ (pt-BR).
/// Valores são sempre exibidos com [AppTheme.moneyStyle] nos widgets.
class Money {
  Money._();

  static final NumberFormat _brl =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  static final NumberFormat _plain =
      NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2);

  /// "R$ 1.234,56"
  static String format(double value) => _brl.format(value);

  /// "1.234,56" — sem símbolo, para o padrão EMV do PIX ou campos.
  static String plain(double value) => _plain.format(value).trim();

  /// Formato exigido pelo BR Code do PIX: ponto decimal, sem separador de milhar.
  /// Ex.: 1234.56
  static String pixAmount(double value) => value.toStringAsFixed(2);

  /// Interpreta entrada de texto em pt-BR ("1.234,56" ou "1234,56") como double.
  static double? parse(String input) {
    final cleaned =
        input.replaceAll(RegExp(r'[^0-9,\.]'), '').replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }
}
